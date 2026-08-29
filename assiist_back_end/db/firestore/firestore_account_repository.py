from google.cloud import firestore
from ..repositories.interfaces.account_repository import AccountRepository
from ...models.account_models import AccountDetailsResponse, AccountDetailsUpdateRequest
from typing import Optional

class FirestoreAccountRepository(AccountRepository):
    """Firestore implementation of the account repository."""
    
    def __init__(self, db: firestore.AsyncClient):
        self._db = db
        # Collection name can be more generic like 'user_profiles' or 'accounts' depending on multi-tenancy model
        # For now, assuming 'accounts' directly stores documents keyed by account_id
        self._accounts_collection = db.collection('accounts') 
    
    async def get_account_details(self, account_id: str) -> Optional[AccountDetailsResponse]:
        """Get the account's details from Firestore using account_id."""
        if not account_id: # Basic validation
            # Consider logging this or raising a specific error
            return AccountDetailsResponse(business_description=None, business_type=None)

        account_doc_ref = self._accounts_collection.document(account_id)
        account_doc = await account_doc_ref.get()
        if not account_doc.exists:
            # If no doc for this account_id, return default/empty response
            return AccountDetailsResponse(business_description=None, business_type=None)
            
        data = account_doc.to_dict() or {}
        return AccountDetailsResponse(
            business_description=data.get('business_description'),
            business_type=data.get('business_type')
        )
    
    async def update_account_details(self, account_id: str, details: AccountDetailsUpdateRequest) -> AccountDetailsResponse:
        """Update the account's details in Firestore using account_id."""
        if not account_id: # Basic validation
            # This case should ideally be prevented by auth/context layer
            # Consider raising an error or logging
            # For now, returning a default empty response if account_id is missing.
            return AccountDetailsResponse(business_description=None, business_type=None)

        account_doc_ref = self._accounts_collection.document(account_id)
        
        update_data = {}
        if details.business_description is not None:
            update_data['business_description'] = details.business_description
        if details.business_type is not None:
            update_data['business_type'] = details.business_type
        
        if not update_data: 
            # No actual update values provided, fetch and return current state
            current_details = await self.get_account_details(account_id=account_id)
            return current_details if current_details is not None else AccountDetailsResponse(business_description=None, business_type=None)

        # Using set with merge=True will create the document if it doesn't exist,
        # or update it if it does. This is suitable if account creation is handled elsewhere
        # and this endpoint only manages these specific details.
        await account_doc_ref.set(update_data, merge=True) 
        
        # Fetch the updated document to return the full current state
        updated_doc = await account_doc_ref.get()
        if not updated_doc.exists:
             # This case should ideally not happen if set worked, implies an issue.
            return AccountDetailsResponse(business_description=None, business_type=None)
        
        updated_data = updated_doc.to_dict() or {}
        return AccountDetailsResponse(
            business_description=updated_data.get('business_description'),
            business_type=updated_data.get('business_type')
        ) 