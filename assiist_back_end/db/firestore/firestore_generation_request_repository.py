import uuid
import logging
from firebase_admin import firestore
from google.cloud.firestore_v1 import AsyncClient
from google.cloud.firestore_v1.base_query import FieldFilter
from typing import Optional, Dict, Any, List
from datetime import datetime
from assiist_back_end.db.repositories.interfaces.generation_request_repository import (
    BaseGenAIRequestRepository,
    GenAIRequestRepository as GenAIRequestRepositoryInterface
)

logger = logging.getLogger(__name__)

class GenAIRequestRepository(GenAIRequestRepositoryInterface):
    """
    Unified Firestore repository for all GenAI request types.
    Implements dynamic request_data and result_data population to decouple
    collection structure from GenAI endpoint implementations.
    """
    
    def __init__(self, db: AsyncClient):
        self._db = db
        self._collection = "genai_requests"  # Single unified collection
    
    async def create_request(
        self,
        id: str,
        request_type: str,
        user_id: str,
        contact_id: str,
        account_id: str,
        request_data: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Create a new GenAI request with dynamic request_data population.
        
        Args:
            request_id: Unique identifier for the request
            request_type: Type of GenAI operation (quick_draft, revise_draft, etc.)
            user_id: User making the request
            contact_id: Associated contact ID
            account_id: Account ID for security
            request_data: Dynamic payload sent to cloud function
        
        Returns:
            Created document data
        """
        try:
            doc_ref = self._db.collection(self._collection).document(id)
            
            # Unified document structure with dynamic population
            document_data = {
                "id": id,
                "request_type": request_type,
                "user_id": user_id,
                "contact_id": contact_id,
                "account_id": account_id,
                "status": "pending",
                "created_on": firestore.SERVER_TIMESTAMP,
                "processed_on": None,
                
                # DYNAMIC: Populated from actual GenAI endpoint payloads
                "request_data": request_data,
                
                # Will be populated when results are received
                "result_data": {},
                "processing_metadata": {
                    "callback_url": None,
                    "llm_provider": None,
                    "llm_model": None,
                    "processing_time_ms": 0,
                    "error_message": None
                }
            }
            
            await doc_ref.set(document_data)
            logger.info(f"Created {request_type} request {id}")
            
            return document_data
            
        except Exception as e:
            logger.error(f"Error creating {request_type} request {id}: {e}")
            raise
    

    
    async def update_status_with_error(
        self,
        id: str,
        status: str,
        error_message: str
    ) -> bool:
        """
        Update request status with error information.
        
        Args:
            request_id: Request to update
            status: New status (typically "failed")
            error_message: Error description
        
        Returns:
            True if successful
        """
        try:
            doc_ref = self._db.collection(self._collection).document(id)
            
            update_data = {
                "status": status,
                "processed_on": firestore.SERVER_TIMESTAMP,
                "processing_metadata.genai_errors": error_message
            }
            
            await doc_ref.update(update_data)
            logger.info(f"Updated request {id} status to {status}")
            return True
            
        except Exception as e:
            logger.error(f"Error updating request {id} status: {e}")
            return False
    
    async def get_by_id(self, account_id: str, request_id: str) -> Optional[Dict[str, Any]]:
        """
        Get a GenAI request by ID with account security check.
        
        Args:
            account_id: Account ID for security validation
            request_id: Request identifier
        
        Returns:
            Request document data or None if not found/unauthorized
        """
        try:
            doc_ref = self._db.collection(self._collection).document(request_id)
            doc = await doc_ref.get()
            
            if not doc.exists:
                return None
            
            data = doc.to_dict()
            
            # Security check: verify account_id matches
            if data.get("account_id") != account_id:
                logger.warning(f"Account mismatch for request {request_id}: {data.get('account_id')} != {account_id}")
                return None
            
            return data
            
        except Exception as e:
            logger.error(f"Error retrieving request {request_id}: {e}")
            raise
    
    async def get_generation_request(self, request_id: str, account_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
        """
        Get generation request by ID.
        If account_id provided, validates ownership (external API calls).
        If account_id is None, skips ownership check (internal callback processing).
        
        Args:
            request_id: Request identifier
            account_id: Optional account ID for security validation
        
        Returns:
            Request document data or None if not found/unauthorized
        """
        try:
            doc_ref = self._db.collection(self._collection).document(request_id)
            doc = await doc_ref.get()
            
            if not doc.exists:
                return None
            
            data = doc.to_dict()
            
            # Security check only if account_id is provided (external API calls)
            if account_id is not None:
                if data.get("account_id") != account_id:
                    logger.warning(f"Account mismatch for request {request_id}: {data.get('account_id')} != {account_id}")
                    return None
            
            return data
            
        except Exception as e:
            logger.error(f"Error retrieving request {request_id}: {e}")
            raise
    
    async def get_by_type_and_user(
        self,
        request_type: str,
        user_id: str,
        limit: int = 50
    ) -> List[Dict[str, Any]]:
        """
        Get requests by type and user with optional pagination.
        
        Args:
            request_type: Type of requests to retrieve
            user_id: User ID filter
            limit: Maximum number of requests to return
        
        Returns:
            List of request documents
        """
        try:
            query = (self._db.collection(self._collection)
                    .where(filter=FieldFilter("request_type", "==", request_type))
                    .where(filter=FieldFilter("user_id", "==", user_id))
                    .order_by("created_on", direction=firestore.Query.DESCENDING)
                    .limit(limit))
            
            docs = await query.get()
            
            requests = []
            for doc in docs:
                data = doc.to_dict()
                data["id"] = doc.id  # Ensure ID is included
                requests.append(data)
            
            logger.info(f"Retrieved {len(requests)} {request_type} requests for user {user_id}")
            return requests
            
        except Exception as e:
            logger.error(f"Error retrieving {request_type} requests for user {user_id}: {e}")
            raise
    
    async def get_by_account(
        self,
        account_id: Optional[str] = None,
        request_type: Optional[str] = None,
        status: Optional[str] = None,
        limit: int = 100
    ) -> List[Dict[str, Any]]:
        """
        Get requests by account with optional filters.
        If account_id is None, returns all requests (for internal use only).
        
        Args:
            account_id: Optional account ID filter
            request_type: Optional request type filter
            status: Optional status filter
            limit: Maximum number of requests to return
        
        Returns:
            List of request documents
        """
        try:
            # Start with base query
            query = self._db.collection(self._collection)
            
            # Add filters if provided
            if account_id is not None:
                query = query.where(filter=FieldFilter("account_id", "==", account_id))
            
            if request_type:
                query = query.where(filter=FieldFilter("request_type", "==", request_type))
            
            if status:
                query = query.where(filter=FieldFilter("status", "==", status))
            
            # Always order by created_on descending
            query = query.order_by("created_on", direction=firestore.Query.DESCENDING).limit(limit)
            
            docs = await query.get()
            
            requests = []
            for doc in docs:
                data = doc.to_dict()
                data["id"] = doc.id  # Ensure ID is included
                requests.append(data)
            
            if account_id:
                logger.info(f"Retrieved {len(requests)} requests for account {account_id}")
            else:
                logger.info(f"Retrieved {len(requests)} requests (no account filter)")
            return requests
            
        except Exception as e:
            if account_id:
                logger.error(f"Error retrieving requests for account {account_id}: {e}")
            else:
                logger.error(f"Error retrieving requests: {e}")
            raise

    # Legacy compatibility methods to support existing interfaces
    async def add(self, request) -> object:
        """Legacy method for backward compatibility."""
        # This shouldn't be used in the new implementation
        # but kept for interface compliance during transition
        raise NotImplementedError("Use create_request() instead of add()")
    
    async def update_status(
        self,
        id: str,
        status: str,
        result_data: Optional[Dict[str, Any]] = None,
        processing_metadata: Optional[Dict[str, Any]] = None
    ) -> bool:
        """Update request status with optional result data and processing metadata."""
        try:
            # Check for duplicate callback
            doc_ref = self._db.collection(self._collection).document(id)
            doc = await doc_ref.get()
            if doc.exists:
                current_data = doc.to_dict()
                if current_data.get("status") == "completed":
                    logger.info(f"Ignoring duplicate callback for request {id}")
                    return False
            
            # Prepare update with clean data separation
            update_data = {
                "status": status,
                "processed_on": firestore.SERVER_TIMESTAMP
            }
            
            # Store pure GenAI output only (for testing/debugging)
            if result_data:
                update_data["result_data"] = result_data
            
            # Store pre-built metadata object (no extraction from result_data)
            if processing_metadata:
                update_data["processing_metadata"] = processing_metadata
            
            await doc_ref.update(update_data)
            logger.info(f"Updated request {id} with results")
            return True
            
        except Exception as e:
            logger.error(f"Error updating request {id} with results: {e}")
            return False

 