from typing import List, Optional, Dict, Any
from datetime import datetime, timezone # Import timezone

# Firestore Admin SDK
from firebase_admin import firestore
from google.cloud.firestore_v1 import AsyncClient, SERVER_TIMESTAMP
from google.cloud import firestore # type: ignore
from google.cloud.firestore_v1.base_query import FieldFilter # type: ignore
from google.cloud.firestore_v1.async_transaction import AsyncTransaction # Import AsyncTransaction
from fastapi import HTTPException, status # Import for raising HTTP errors
from google.cloud.firestore_v1.async_client import AsyncClient # Ensure this is imported
from dependency_injector import providers # Import for type checking if needed

# --- CORRECT Algolia Import --- #
# Correct Algolia import path
from algoliasearch.search_client import SearchClient
import re  # For phone number normalisation
# from algoliasearch.search_client_async import SearchClientAsync # Incorrect for v4

# Core components
from assiist_back_end.db.repositories.interfaces.contact_repository import ContactRepository # ADJUSTED PATH
from assiist_back_end.models.contact import (
    Contact, PhoneNumber, EmailAddress, Address, 
    PersonalDetails, RelationshipDetail, BusinessDetails, BusinessOpportunity # <<< IMPORT ALL NESTED MODELS - ADJUSTED PATH
)
from assiist_back_end.config import Settings # <<< IMPORT Settings CLASS - ADJUSTED PATH

# Assume mappers are in the same directory or adjust import
from .mappers import contact_to_firestore, firestore_to_contact

import asyncio

class FirestoreContactRepository(ContactRepository):
    """Firestore implementation for contact data operations.
    Uses Algolia for searching if algolia_client is provided.
    """

    # Update __init__ to accept Algolia client and Settings
    def __init__(self, 
                 firestore_async_client: AsyncClient, 
                 settings: Settings, # <<< Inject Settings object
                 algolia_client: SearchClient = None):
        self.db = firestore_async_client
        if not self.db:
             raise RuntimeError("Failed to initialize Firestore AsyncClient via injection")
        self.contacts_ref = self.db.collection('contacts')
        self._settings = settings # <<< STORE the injected settings object
        self.algolia_client = algolia_client # Store the injected Algolia client
        self.algolia_index_name = self._settings.ALGOLIA_INDEX_NAME # Use stored settings
        # if self.algolia_client and self.algolia_index_name:
        #     print(f"DEBUG: FirestoreContactRepository initialized WITH Algolia client for index '{self.algolia_index_name}'.")
        # else:
        #     print("DEBUG: FirestoreContactRepository initialized WITHOUT Algolia client/index name.")

    async def get_contact_by_id(self, account_id: str, contact_id: str) -> Optional[Contact]:
        doc_ref = self.contacts_ref.document(contact_id)
        
        doc_snapshot = await doc_ref.get()
        
        if not doc_snapshot.exists:
            return None

        data = doc_snapshot.to_dict()
        data['id'] = doc_snapshot.id # Add the document ID back

        try:
            contact = Contact.model_validate(data)
        except Exception as e: 
            print(f"Error validating Firestore data for contact {contact_id}: {e}. Data: {data}")
            return None

        # Security check: Ensure the fetched contact belongs to the requesting account
        if contact.account_id == account_id:
            return contact
        return None

    async def get_contact_by_email(self, account_id: str, email: str) -> Optional[Contact]:
        """Fetch a single contact by email.

        The primary query attempts to use Firestore's nested field filter
        (`emails.address == email`).  In production we have occasionally seen
        this raise *FAILED_PRECONDITION* errors when the required composite
        index is missing.  To make the system more resilient we now:

        1. Try the efficient nested-field query (requires proper index).
        2. If that fails due to a missing index **or** returns no document,
           fall back to a broader query on the account and perform the e-mail
           match client-side.

        Because this method is only invoked for a *single* e-mail look-up
        during calendar-sync the slight performance hit of the fallback is
        acceptable and avoids silent failures that previously caused the
        auto-note scheduler to treat real contacts as unknown, leading to the
        "Pending contact already exists" log the user reported.
        """

        # Normalise the e-mail for case-insensitive comparison
        normalized_email = email.strip().lower()

        # -----------------------------------------------------
        # 1) Primary – index-based lookup on nested array field
        # -----------------------------------------------------
        try:
            query = (
                self.contacts_ref
                .where(filter=FieldFilter("account_id", "==", account_id))
                .where(filter=FieldFilter("emails.address", "==", normalized_email))
                .where(filter=FieldFilter("is_deleted", "==", False))
                .limit(1)
            )

            doc_snapshot: Optional[Any] = None
            async for doc in query.stream():
                doc_snapshot = doc
                break

            if doc_snapshot and doc_snapshot.exists:
                data = doc_snapshot.to_dict() or {}
                data["id"] = doc_snapshot.id
                try:
                    contact = Contact.model_validate(data)
                except Exception as e:
                    print(f"Error validating Firestore data for contact with email {email}: {e}. Data: {data}")
                    return None

                # Extra safety – ensure the e-mail truly belongs to the contact
                if any((em.get("address") or "").lower() == normalized_email for em in data.get("emails", [])):
                    return contact
                # If somehow the email wasn't actually present, fall through to fallback
        except Exception as primary_exc:
            # Log and continue to fallback rather than bailing out – the most
            # common reason here is a missing composite index (FAILED_PRECONDITION).
            print(
                f"Warning: primary email lookup for '{email}' failed – {primary_exc}. Falling back to client-side scan."
            )

        # -----------------------------------------------------
        # 2) Fallback – iterate all contacts for the account (filtered by
        #    is_deleted) and locate the e-mail client side.
        # -----------------------------------------------------
        broad_query = (
            self.contacts_ref
            .where(filter=FieldFilter("account_id", "==", account_id))
            .where(filter=FieldFilter("is_deleted", "==", False))
        )

        try:
            async for doc in broad_query.stream():
                data = doc.to_dict() or {}
                for em in data.get("emails", []):
                    if (em.get("address") or "").lower() == normalized_email:
                        data["id"] = doc.id
                        try:
                            return Contact.model_validate(data)
                        except Exception as e:
                            print(
                                f"Error validating Firestore data for contact {doc.id} during fallback lookup: {e}. Data: {data}"
                            )
                            return None
        except Exception as fallback_exc:
            print(f"Error during fallback email lookup for '{email}': {fallback_exc}")

        # No match found
        return None

    async def get_contact_by_phone(self, account_id: str, phone: str) -> Optional[Contact]:
        """Fetch a single contact by phone number (digits only match).

        Because phone number formats vary greatly, we normalise both the
        candidate number and stored numbers to digits-only strings before
        comparison.  The lookup scans contacts for the given account that are
        not deleted and returns the first contact whose normalised phone
        number exactly matches or whose last 7 digits match (to allow country
        code variance).
        """

        # Remove all non-digit characters for comparison (e.g. '+1 (555) 123-4567' → '15551234567')
        normalised_query = re.sub(r"[^0-9]", "", phone or "")
        if not normalised_query:
            return None  # Nothing to search

        broad_query = (
            self.contacts_ref
            .where(filter=FieldFilter("account_id", "==", account_id))
            .where(filter=FieldFilter("is_deleted", "==", False))
        )

        try:
            async for doc in broad_query.stream():
                data = doc.to_dict() or {}
                for pn in data.get("phone_numbers", []):
                    digits = re.sub(r"[^0-9]", "", (pn.get("number") or ""))
                    if not digits:
                        continue

                    # Consider it a match if the full digits match OR the last 7 digits match.
                    if (
                        digits == normalised_query
                        or digits.endswith(normalised_query)
                        or normalised_query.endswith(digits)
                    ):
                        data["id"] = doc.id
                        try:
                            return Contact.model_validate(data)
                        except Exception as e:
                            print(
                                f"Error validating Firestore data for contact {doc.id} during phone lookup: {e}. Data: {data}"
                            )
                            return None
        except Exception as exc:
            print(f"Error during phone lookup for '{phone}': {exc}")

        # No match found
        return None

    async def get_contacts_by_account(
        self, account_id: str, limit: int = 50, offset: int = 0
    ) -> List[Contact]:
        query = (
            self.contacts_ref
            .where(filter=FieldFilter("account_id", "==", account_id))
            .where(filter=FieldFilter("is_deleted", "==", False))
            .order_by("first_name") # Assuming first_name is indexed or low cardinality
            .limit(limit + offset)
        )
        
        docs_stream = query.stream()
        contacts = []
        count = 0
        async for doc in docs_stream:
            if count >= offset:
                data = doc.to_dict()
                data['id'] = doc.id
                try:
                    contact = Contact.model_validate(data)
                    contacts.append(contact)
                except Exception as e:
                    print(f"Error validating Firestore data for contact {doc.id} in list view: {e}")
                    # Decide whether to skip the contact or raise an error
                    continue 
            count += 1
            if len(contacts) >= limit:
                 break
                 
        return contacts

    # ------------------------------------------------------------------
    # Incremental-sync helper – NEW
    # ------------------------------------------------------------------
    async def get_contacts_changed_since(
        self,
        account_id: str,
        timestamp: datetime,
        limit: int = 500,
    ) -> List[Contact]:
        """Firestore implementation of incremental change fetch.

        We filter on:
        • account_id equality
        • updated_on > timestamp
        • is_deleted == False – deleted contacts will have their own sync path later
        """

        if not timestamp:
            # If no timestamp given, fall back to get_contacts_by_account (up to limit).
            return await self.get_contacts_by_account(account_id, limit=limit, offset=0)

        query = (
            self.contacts_ref
            .where(filter=FieldFilter("account_id", "==", account_id))
            .where(filter=FieldFilter("updated_on", ">", timestamp))
            .where(filter=FieldFilter("is_deleted", "==", False))
            .order_by("updated_on")
            .limit(limit)
        )

        changed: List[Contact] = []
        async for doc in query.stream():
            data = doc.to_dict() or {}
            data["id"] = doc.id
            try:
                changed.append(Contact.model_validate(data))
            except Exception as e:
                print(f"Failed to validate contact {doc.id} during incremental fetch: {e}")
                continue

        return changed

    async def create_contact(self, contact: Contact) -> Contact:
        if not contact.account_id:
            raise ValueError("Contact must have an account_id set before creation.")
            
        # Use Pydantic's model_dump, excluding 'id' and None values
        contact_dict = contact.model_dump(exclude={'id'}, exclude_none=True, by_alias=True) 
        
        # Set addressed_as to first_name if not provided and first_name exists
        if not contact_dict.get('addressed_as') and contact_dict.get('first_name'):
            contact_dict['addressed_as'] = contact_dict['first_name']
            
        # Add server timestamp for creation (overwrites any client-set value)
        contact_dict['created_on'] = firestore.SERVER_TIMESTAMP 
        
        doc_ref = self.contacts_ref.document(contact.id)
        await doc_ref.set(contact_dict)
        
        # Note: The returned contact object won't have the server-generated timestamp yet.
        # A follow-up get() would be needed if the exact timestamp is required immediately.
        return contact

    async def update_contact(self, account_id: str, contact_id: str, updates: Dict[str, Any], updater_user_id: str) -> Optional[Contact]:
        """Updates a contact using an atomic transaction for the write operation only."""
        
        doc_ref = self.contacts_ref.document(contact_id)

        # 1. Read and perform checks OUTSIDE the transaction
        try:
            doc_snapshot = await doc_ref.get()
            if not doc_snapshot.exists:
                print(f"Update failed pre-check: Contact {contact_id} not found.")
                raise FileNotFoundError(f"Contact {contact_id} not found.")

            existing_data = doc_snapshot.to_dict()
            if existing_data.get('account_id') != account_id:
                print(f"Update failed pre-check: Account {account_id} cannot update contact {contact_id}")
                raise PermissionError(f"Account {account_id} lacks permission to update contact {contact_id}.")
            
        except (FileNotFoundError, PermissionError) as e:
            # Let these specific errors propagate to the API layer
            raise e
        except Exception as e:
            # Catch other errors during the pre-check read
            print(f"Error during pre-transaction read for contact {contact_id}: {e}")
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to read contact before update: {e}")
            
        # If pre-checks passed, proceed with the write transaction
        transaction = self.db.transaction()
        try:
            # 2. Prepare update data and perform write WITHIN the transaction
            update_data = updates.copy()
            update_data['updated_on'] = firestore.SERVER_TIMESTAMP
            update_data['updated_by'] = updater_user_id
            
            transaction.update(doc_ref, update_data)
            
            # 3. Commit the transaction
            await transaction.commit()

        except Exception as e:
            # Catch potential errors during transaction update/commit
            print(f"Error during write transaction commit for contact {contact_id}: {e}")
            # Transaction might have failed, state is uncertain
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Database write transaction failed: {e}")

        # 4. If we reach here, the transaction was successful.
        # Fetch the updated document outside the transaction.
        try:
            updated_doc_snapshot = await doc_ref.get()
            if not updated_doc_snapshot.exists:
                 print(f"Error: Could not fetch updated contact {contact_id} after successful write commit.")
                 raise HTTPException(status_code=500, detail="Failed to retrieve contact after successful update.") 
            
            data = updated_doc_snapshot.to_dict()
            data['id'] = updated_doc_snapshot.id
            updated_contact = Contact.model_validate(data)
            return updated_contact
        except Exception as e:
            print(f"Error validating/fetching updated Firestore data for contact {contact_id}: {e}")
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to retrieve or validate contact after update: {e}")

    # --- Remove the _delete_contact_transactional helper ---
    # async def _delete_contact_transactional(self, transaction: AsyncTransaction, doc_ref, account_id: str, deleter_user_id: str):
    #    ...

    async def delete_contact(self, account_id: str, contact_id: str, deleter_user_id: str, hard_delete: bool = False) -> bool:
        """Deletes a contact using an atomic transaction for the write operation only.
        
        Args:
            account_id: The account ID that owns the contact
            contact_id: The ID of the contact to delete
            deleter_user_id: The ID of the user performing the deletion
            hard_delete: If True, permanently deletes the contact from Firestore.
                        If False (default), performs soft delete by setting is_deleted=True.
        
        Returns:
            bool: True if deletion was successful
        """
        
        doc_ref = self.contacts_ref.document(contact_id) # Get doc reference

        # 1. Read and perform checks OUTSIDE the transaction
        try:
            doc_snapshot = await doc_ref.get()
            if not doc_snapshot.exists:
                print(f"Delete failed pre-check: Contact {contact_id} not found.")
                raise FileNotFoundError(f"Contact {contact_id} not found.")

            existing_data = doc_snapshot.to_dict()
            if existing_data.get('account_id') != account_id:
                print(f"Delete failed pre-check: Account {account_id} cannot delete contact {contact_id}")
                raise PermissionError(f"Account {account_id} lacks permission to delete contact {contact_id}.")

            # For soft delete, check if already deleted (idempotency)
            # For hard delete, we proceed regardless of is_deleted status
            if not hard_delete and existing_data.get('is_deleted', False):
                print(f"Contact {contact_id} already marked as deleted (pre-check).")
                return True # Idempotency: Already deleted is considered success
            
        except (FileNotFoundError, PermissionError) as e:
            # Let these specific errors propagate to the API layer
            raise e
        except Exception as e:
            # Catch other errors during the pre-check read
            print(f"Error during pre-transaction read for deleting contact {contact_id}: {e}")
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to read contact before delete: {e}")
            
        # If pre-checks passed, proceed with the write transaction
        transaction = self.db.transaction()
        try:
            if hard_delete:
                # Hard delete: Remove the document entirely from Firestore
                transaction.delete(doc_ref)
            else:
                # Soft delete: Mark as deleted
                update_data = {
                    'is_deleted': True,
                    'updated_on': firestore.SERVER_TIMESTAMP,
                    'updated_by': deleter_user_id
                }
                transaction.update(doc_ref, update_data)
            
            # Commit the transaction
            await transaction.commit()
            return True # Indicate success

        except Exception as e:
            # Catch potential errors during transaction update/commit
            print(f"Error during {'hard' if hard_delete else 'soft'} delete write transaction commit for contact {contact_id}: {e}")
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Database delete write transaction failed: {e}")

    # --- REWRITE searchContacts to use Algolia Client --- #
    async def search_contacts_by_account(
        self, 
        account_id: str, 
        search_term: str, 
        limit: int = 10,
        offset: int = 0,
        search_fields: List[str] = None # Add parameter to match interface
    ) -> List[Contact]:
        """Searches contacts using Algolia if available, falling back to basic Firestore filter if not."""
        
        # Use default fields if None provided (matches interface default)
        if search_fields is None:
            search_fields = ['first_name', 'last_name', 'email', 'phone_mobile', 'phone_work', 'phone_home', 'business_name', 'addressed_as']

        # If Algolia client is configured, use it
        if self.algolia_client and self.algolia_index_name:
            # print(f"DEBUG: Searching Algolia index '{self.algolia_index_name}' for term '{search_term}' in account '{account_id}'")
            try:
                # 1. Define search parameters (restoring query)
                search_params = {
                    'filters': f'account_id:"{account_id}" AND is_deleted:false',
                    'hitsPerPage': limit,
                    'offset': offset,
                }
                # print(f"DEBUG: Algolia search_params dict: {search_params}") # Restore log message

                # 2. Perform the search using await client.search_single_index()
                # print(f"DEBUG: Calling await client.search_single_index(index_name='{self.algolia_index_name}', search_params=...)") # Restore log message
                
                # Strip whitespace/newlines from API key to prevent header injection issues
                algolia_api_key = self._settings.ALGOLIA_API_KEY.get_secret_value().strip()
                
                # Modern Algolia SDK (v3) uses index.search synchronously.
                index = self.algolia_client.init_index(self.algolia_index_name)

                # Offload blocking search to a thread
                res = await asyncio.to_thread(
                    index.search,
                    search_term,
                    search_params,
                )

                # If hits list empty and SearchResponse doesn't expose hits properly, fall back to index.search
                # Some Algolia client versions only populate `hits` when using `index.search`.
                extracted_hits = []
                if isinstance(res, dict):
                    extracted_hits = res.get("hits", [])
                else:
                    extracted_hits = getattr(res, "hits", [])
                    if callable(extracted_hits):
                        extracted_hits = extracted_hits()

                if not extracted_hits:
                    # Fallback: call classic index.search which reliably returns dict
                    index = self.algolia_client.init_index(self.algolia_index_name)
                    fallback_res = await asyncio.to_thread(
                        index.search,
                        search_term,
                        {
                            "filters": search_params["filters"],
                            "hitsPerPage": limit,
                            "offset": offset,
                        },
                    )
                    extracted_hits = fallback_res.get("hits", [])

                algolia_hits = extracted_hits
                # print(f"DEBUG Algolia hits len: {len(algolia_hits)}")

                # If nothing came back, retry without filters and filter client-side (safety net).
                if not algolia_hits:
                    raw_no_filter = await asyncio.to_thread(
                        index.search,
                        search_term,
                        {
                            "hitsPerPage": limit,
                            "offset": offset,
                        },
                    )
                    algolia_hits = [
                        hit for hit in raw_no_filter.get("hits", [])
                        if hit.get("account_id") == account_id and not hit.get("is_deleted", False)
                    ]

                # Map Algolia hits to domain models
                contacts_domain = [self._map_algolia_hit_to_domain(hit) for hit in algolia_hits]
                # print(f"DEBUG: Mapped domain contacts: {len(contacts_domain)}")
                return contacts_domain

            except Exception as e:
                print(f"Error searching Algolia: {e}")
                import traceback
                traceback.print_exc()
                raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=f"Search service unavailable: {e}")

        else:
            print("WARN: Algolia client or index name not configured. Falling back to basic Firestore query.")
            # --- Fallback Firestore Query ---
            # ... (existing fallback logic remains the same) ...
            query_ref = self.db.collection("contacts") \
                .where(filter=FieldFilter("account_id", "==", account_id)) \
                .where(filter=FieldFilter("is_deleted", "==", False)) \
                .limit(limit) \
                .offset(offset)
            # Add basic filtering if needed, though Algolia is preferred for real search
            # Example: .where("name", ">=", search_term).where("name", "<=", search_term + u'\uf8ff')

            docs = await query_ref.stream()
            contacts_domain = [Contact.from_dict({**doc.to_dict(), "id": doc.id}) async for doc in docs]
            return contacts_domain

    # Helper method to map Algolia hit object to Contact domain model
    def _map_algolia_hit_to_domain(self, hit) -> Contact:
        """Converts an Algolia hit (dict or Pydantic model) into our Contact domain model."""

        # If the hit is a Pydantic model, convert to dict first
        if not isinstance(hit, dict):
            try:
                hit = hit.model_dump()
            except Exception:
                # Fallback: try `dict(hit)` if model_dump unavailable
                hit = dict(hit)  # type: ignore

        # Helper to safely parse timestamp (assuming milliseconds)
        def parse_timestamp(timestamp_ms):
            if timestamp_ms:
                try:
                    # Convert ms to seconds and create timezone-aware datetime (UTC)
                    return datetime.fromtimestamp(timestamp_ms / 1000.0, tz=timezone.utc)
                except Exception as e:
                    print(f"Warning: Could not parse timestamp {timestamp_ms}: {e}")
                    return None
            return None

        # Map lists by iterating and creating model instances
        emails_list = [
            EmailAddress(**email_data)
            for email_data in hit.get("emails", [])
            if isinstance(email_data, dict)
        ]
        phone_numbers_list = [
            PhoneNumber(**phone_data)
            for phone_data in hit.get("phone_numbers", [])
            if isinstance(phone_data, dict)
        ]
        addresses_list = [
            Address(**addr_data)
            for addr_data in hit.get("addresses", [])
            if isinstance(addr_data, dict)
        ]

        # Nested objects
        personal_details_data = hit.get("personal_details")
        personal_details_obj = (
            PersonalDetails(**personal_details_data)
            if isinstance(personal_details_data, dict)
            else None
        )

        business_details_obj = None
        business_details_data = hit.get("business_details")
        if isinstance(business_details_data, dict):
            business_opp_data = business_details_data.get("business_opportunity")
            business_opp_obj = (
                BusinessOpportunity(**business_opp_data)
                if isinstance(business_opp_data, dict)
                else None
            )
            business_details_obj = BusinessDetails(business_opportunity=business_opp_obj)

        relationship_details_dict = {}
        relationship_details_data = hit.get("relationship_details")
        if isinstance(relationship_details_data, dict):
            relationship_details_dict = {
                user_id: RelationshipDetail(**details_data)
                for user_id, details_data in relationship_details_data.items()
                if isinstance(details_data, dict)
            }

        # Assemble Contact
        return Contact(
            id=hit.get("objectID") or hit.get("object_id"),
            account_id=hit.get("account_id"),
            first_name=hit.get("first_name"),
            last_name=hit.get("last_name"),
            addressed_as=hit.get("addressed_as"),
            date_of_birth=parse_timestamp(hit.get("date_of_birth")),
            business_name=hit.get("business_name"),
            business_type=hit.get("business_type"),
            phone_numbers=phone_numbers_list,
            emails=emails_list,
            addresses=addresses_list,
            personal_details=personal_details_obj,
            relationship_details=relationship_details_dict,
            business_details=business_details_obj,
            source=hit.get("source"),
            tags=hit.get("tags", []),
            created_on=parse_timestamp(hit.get("created_on")),
            updated_on=parse_timestamp(hit.get("updated_on")),
            updated_by=hit.get("updated_by"),
            is_deleted=hit.get("is_deleted", False),
            assigned_user=hit.get("assigned_user"),
            created_by=hit.get("created_by"),
            is_vip=hit.get("is_vip", False),
        )

    # TODO: Implement other methods like search if needed 

    async def update_last_contacted(self, account_id: str, contact_id: str, user_id: str) -> bool:
        """Update the last_contacted_on field for a contact."""
        try:
            doc_ref = self.db.collection("contacts").document(contact_id)
            doc = await doc_ref.get()
            
            if not doc.exists:
                return False
                
            data = doc.to_dict()
            
            # Verify account ownership
            if data.get("account_id") != account_id:
                raise PermissionError(f"Contact {contact_id} not found in account {account_id}")
            
            # Update last_contacted_on timestamp
            await doc_ref.update({
                "last_contacted_on": firestore.SERVER_TIMESTAMP,
                "updated_on": firestore.SERVER_TIMESTAMP,
                "updated_by": user_id
            })
            
            return True
            
        except Exception as e:
            logger.error(f"Error updating last contacted date for contact {contact_id}: {e}")
            raise 