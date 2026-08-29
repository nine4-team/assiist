from abc import ABC, abstractmethod
from typing import List, Optional, Dict, Any
from datetime import datetime

# Base interface for all GenAI operations
class BaseGenAIRequestRepository(ABC):
    @abstractmethod
    async def add(self, request) -> object:
        """Add a new generation request."""
        pass
    
    @abstractmethod
    async def get_by_id(self, account_id: str, id: str) -> Optional[object]:
        """Get a generation request by ID."""
        pass
    
    @abstractmethod
    async def update_status(
        self, 
        id: str, 
        status: str, 
        error_message: Optional[str] = None,
        result_data: Optional[Dict[str, Any]] = None,
        processing_metadata: Optional[Dict[str, Any]] = None
    ) -> bool:
        """Update the status of a generation request with result data and processing metadata."""
        pass

# NEW: Unified repository interface for the single genai_requests collection
class GenAIRequestRepository(BaseGenAIRequestRepository):
    """
    Unified repository interface for all GenAI request types.
    Supports dynamic request_data and result_data population.
    """
    
    @abstractmethod
    async def create_request(
        self,
        id: str,
        request_type: str,
        user_id: str,
        contact_id: str,
        account_id: str,
        request_data: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Create a new GenAI request with dynamic request_data population."""
        pass
    
    @abstractmethod
    async def get_generation_request(self, request_id: str, account_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
        """
        Get generation request by ID.
        If account_id provided, validates ownership (external API calls).
        If account_id is None, skips ownership check (internal callback processing).
        """
        pass
    
    @abstractmethod
    async def update_status_with_error(
        self,
        id: str,
        status: str,
        error_message: str
    ) -> bool:
        """Update request status with error information."""
        pass
    
    @abstractmethod
    async def get_by_type_and_user(
        self,
        request_type: str,
        user_id: str,
        limit: int = 50
    ) -> List[Dict[str, Any]]:
        """Get requests by type and user with pagination."""
        pass
    
    @abstractmethod
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
        """
        pass

class QuickDraftRequestRepository(BaseGenAIRequestRepository):
    """Repository interface for quick draft generation requests."""
    pass

class ReviseDraftRequestRepository(BaseGenAIRequestRepository):
    """Repository interface for draft revision requests."""
    pass

class ProcessNoteRequestRepository(BaseGenAIRequestRepository):
    """Repository interface for note processing requests."""
    pass

class UpdateTasksRequestRepository(BaseGenAIRequestRepository):
    """Repository interface for task update requests."""
    pass

class UpdateContextRequestRepository(BaseGenAIRequestRepository):
    """Repository interface for context update requests."""
    pass

# Legacy interface for backward compatibility during transition
class GenerationRequestRepository(BaseGenAIRequestRepository):
    """Legacy interface - use specific operation repositories instead."""
    
    @abstractmethod
    async def get_by_account(self, account_id: str, **filters) -> List[object]:
        """Get generation requests by account with optional filters."""
        pass
    
    @abstractmethod
    async def update_status(
        self, 
        request_id: str, 
        status: str, 
        error_message: Optional[str] = None, 
        generated_doc_id: Optional[str] = None,
        task_data: Optional[Dict[str, Any]] = None
    ) -> bool:
        """Legacy update_status method."""
        pass

    # Potentially add methods to update status later
    # @abstractmethod
    # async def update_status(self, request_id: str, status: GenerationRequestStatus, error_message: Optional[str] = None, result_task_id: Optional[str] = None) -> bool:
    #     pass 