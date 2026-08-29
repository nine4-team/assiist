from abc import ABC, abstractmethod
from typing import List, Optional
from ....models.feedback import Feedback

class FeedbackRepository(ABC):
    """Repository interface for feedback operations."""
    
    @abstractmethod
    async def create(self, feedback: Feedback) -> Feedback:
        """Create a new feedback entry."""
        pass
    
    @abstractmethod
    async def get_by_id(self, feedback_id: str, account_id: str) -> Optional[Feedback]:
        """Get feedback by ID within account scope."""
        pass
    
    @abstractmethod
    async def list_by_account(self, account_id: str) -> List[Feedback]:
        """List all feedback for an account."""
        pass
    
    @abstractmethod
    async def update(self, feedback: Feedback) -> Feedback:
        """Update existing feedback."""
        pass
    
    @abstractmethod
    async def soft_delete(self, feedback_id: str, account_id: str) -> bool:
        """Soft delete feedback entry."""
        pass 