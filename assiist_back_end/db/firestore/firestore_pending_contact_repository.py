from typing import List, Optional, Dict, Any
from google.cloud.firestore_v1.async_client import AsyncClient
from google.cloud.firestore_v1 import FieldFilter, SERVER_TIMESTAMP # Import FieldFilter for where clauses and SERVER_TIMESTAMP
import logging
import uuid # Import uuid

# Import the interface using the four-dot relative path like other repositories
# from ...core.repositories.pending_contact_repository import PendingContactRepository
from assiist_back_end.db.repositories.interfaces.pending_contact_repository import PendingContactRepository # ADJUSTED PATH
# TODO: Import the domain model when created
# from ...core.models.pending_contact import PendingContact # Keep original relative path for now
# Or update this too if needed: from ....core.models.pending_contact import PendingContact

from assiist_back_end.models.pending_contact import PendingContact # Import the model

logger = logging.getLogger(__name__)

class FirestorePendingContactRepository(PendingContactRepository):
    """Firestore implementation for managing pending contacts as a subcollection under users."""

    COLLECTION_NAME = "pending_contacts" # Name of the subcollection

    def __init__(self, db: AsyncClient):
        self._db = db

    def _get_pending_coll_ref(self, user_id: str):
        """Helper to get the reference to a user's pendingContacts subcollection."""
        return self._db.collection('users').document(user_id).collection(self.COLLECTION_NAME)

    async def add(self, pending_contact: PendingContact) -> PendingContact:
        """Adds a new pending contact. user_id must be set on the input object."""
        if not pending_contact.user_id:
            raise ValueError("user_id must be set on the PendingContact object.")

        # Optional: Check for existing contact with the same source_event_id for this user to prevent duplicates
        # This logic was in the old create_pending_contact method. Consider if still needed and how.
        # For now, we assume the caller handles duplicate checks if necessary, or that duplicates are allowed initially.
        # If a strict check is needed here, it adds complexity (query before write).

        coll_ref = self._get_pending_coll_ref(pending_contact.user_id)
        doc_ref = coll_ref.document(pending_contact.id) # Use model's generated ID

        firestore_data = pending_contact.model_dump(exclude_none=True)
        # Ensure user_id from the model is used, not potentially a different one if path and model differ
        firestore_data['user_id'] = pending_contact.user_id 
        firestore_data['created_on'] = SERVER_TIMESTAMP
        firestore_data['updated_on'] = SERVER_TIMESTAMP
        
        await doc_ref.set(firestore_data)
        # To return the object with server-generated timestamps, a fetch would be needed.
        # For now, returning the input object which is mostly complete.
        # Update the model instance with server timestamps if fetched.
        # pending_contact.created_on = # from fetched doc if needed
        # pending_contact.updated_on = # from fetched doc if needed
        return pending_contact

    async def get_by_id(self, user_id: str, pending_contact_id: str) -> Optional[PendingContact]:
        """Fetches a pending contact by its ID for a specific user."""
        coll_ref = self._get_pending_coll_ref(user_id)
        doc_ref = coll_ref.document(pending_contact_id)
        snapshot = await doc_ref.get()

        if not snapshot.exists:
            return None
        
        data = snapshot.to_dict()
        if data:
            # data['id'] = snapshot.id # ID is already in the model if doc ID was used as model ID
            return PendingContact(**data)
        return None

    async def get_by_email(self, user_id: str, email: str) -> Optional[PendingContact]:
        """Fetches a pending contact by email for a specific user."""
        coll_ref = self._get_pending_coll_ref(user_id)
        query = (
            coll_ref
            .where(filter=FieldFilter("email", "==", email))
            # .where(filter=FieldFilter("user_id", "==", user_id)) # Not needed if querying subcollection
            .limit(1)
        )
        doc_snapshot = None
        async for doc in query.stream():
            doc_snapshot = doc
            break
        
        if not doc_snapshot or not doc_snapshot.exists:
            return None
        
        data = doc_snapshot.to_dict()
        if data:
            # data['id'] = doc_snapshot.id # ID is in model if doc ID was used
            return PendingContact(**data)
        return None

    async def get_pending_contacts(
        self, user_id: str, status: Optional[str] = None
    ) -> List[PendingContact]:
        """Fetches pending contacts for a user, optionally filtered by status."""
        coll_ref = self._get_pending_coll_ref(user_id)
        query = coll_ref
        if status:
            query = query.where(filter=FieldFilter("status", "==", status))
        
        contacts = []
        async for doc in query.stream():
            data = doc.to_dict()
            if data:
                # data['id'] = doc.id
                contacts.append(PendingContact(**data))
        logger.info(f"Fetched {len(contacts)} pending contacts with status '{status or 'any'}' for user {user_id}")
        return contacts

    async def update_status(self, user_id: str, pending_contact_id: str, status: str) -> Optional[PendingContact]:
        """Updates the status of a specific pending contact document for a user."""
        coll_ref = self._get_pending_coll_ref(user_id)
        doc_ref = coll_ref.document(pending_contact_id)
        
        try:
            await doc_ref.update({
                "status": status,
                "updated_on": SERVER_TIMESTAMP
            })
            logger.info(f"Updated status to '{status}' for pending contact {pending_contact_id} of user {user_id}")
            # Fetch and return the updated model
            updated_doc = await doc_ref.get()
            if updated_doc.exists:
                data = updated_doc.to_dict()
                if data:
                    return PendingContact(**data)
            # This part is reached if updated_doc doesn't exist or data is empty after update.
            logger.warning(f"Pending contact {pending_contact_id} for user {user_id} not found or empty after update attempt.")
            return None 
        except Exception as e:
            logger.error(f"Error updating status for pending contact {pending_contact_id} of user {user_id}: {e}", exc_info=True)
            return None

    # Deprecated create_pending_contact - use add instead
    # async def create_pending_contact(self, user_id: str, email: str, display_name: str, source_event_id: str, phone: str | None = None) -> dict | None:
    #     pass

    # TODO: Implement mapping functions from Firestore dict to PendingContact domain model 