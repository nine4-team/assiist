import uuid
from datetime import datetime, timezone
from typing import List, Optional
from google.cloud.firestore_v1.async_client import AsyncClient
from google.cloud.firestore_v1.base_query import FieldFilter
import logging

from ...models.feedback import Feedback
from ..repositories.interfaces.feedback_repository import FeedbackRepository

logger = logging.getLogger(__name__)

class FirestoreFeedbackRepository(FeedbackRepository):
    """Firestore implementation of FeedbackRepository."""
    
    def __init__(self, db: AsyncClient):
        self.db = db
        self.collection = "feedback"
    
    async def create(self, feedback: Feedback) -> Feedback:
        """Create a new feedback entry with proper timestamps."""
        try:
            if not feedback.id:
                feedback.id = str(uuid.uuid4())
            
            now = datetime.now(timezone.utc)
            feedback.created_on = now
            feedback.updated_on = now
            
            doc_ref = self.db.collection(self.collection).document(feedback.id)
            await doc_ref.set(feedback.dict())
            
            logger.info(f"Successfully created feedback {feedback.id} for account {feedback.account_id}")
            return feedback
            
        except Exception as e:
            logger.error(f"Error creating feedback: {e}", exc_info=True)
            raise
    
    async def get_by_id(self, feedback_id: str, account_id: str) -> Optional[Feedback]:
        """Get feedback by ID within account scope."""
        try:
            doc_ref = self.db.collection(self.collection).document(feedback_id)
            doc = await doc_ref.get()
            
            if not doc.exists:
                return None
            
            data = doc.to_dict()
            if data.get("account_id") != account_id or data.get("is_deleted"):
                return None
            
            return Feedback(**data)
            
        except Exception as e:
            logger.error(f"Error getting feedback {feedback_id}: {e}", exc_info=True)
            raise
    
    async def list_by_account(self, account_id: str) -> List[Feedback]:
        """List all feedback for an account ordered by creation date."""
        try:
            query = self.db.collection(self.collection).where(
                filter=FieldFilter("account_id", "==", account_id)
            ).where(
                filter=FieldFilter("is_deleted", "==", False)
            ).order_by("created_on", direction="DESCENDING")
            
            docs = query.stream()
            feedback_list = []
            async for doc in docs:
                if doc.exists:
                    feedback_list.append(Feedback(**doc.to_dict()))
            
            logger.info(f"Retrieved {len(feedback_list)} feedback entries for account {account_id}")
            return feedback_list
            
        except Exception as e:
            logger.error(f"Error listing feedback for account {account_id}: {e}", exc_info=True)
            raise
    
    async def update(self, feedback: Feedback) -> Feedback:
        """Update existing feedback."""
        try:
            feedback.updated_on = datetime.now(timezone.utc)
            
            doc_ref = self.db.collection(self.collection).document(feedback.id)
            await doc_ref.update(feedback.dict(exclude={"created_on"}))
            
            logger.info(f"Successfully updated feedback {feedback.id}")
            return feedback
            
        except Exception as e:
            logger.error(f"Error updating feedback {feedback.id}: {e}", exc_info=True)
            raise
    
    async def soft_delete(self, feedback_id: str, account_id: str) -> bool:
        """Soft delete feedback entry."""
        try:
            doc_ref = self.db.collection(self.collection).document(feedback_id)
            doc = await doc_ref.get()
            
            if not doc.exists:
                return False
            
            data = doc.to_dict()
            if data.get("account_id") != account_id:
                return False
            
            await doc_ref.update({
                "is_deleted": True,
                "updated_on": datetime.now(timezone.utc)
            })
            
            logger.info(f"Successfully soft deleted feedback {feedback_id}")
            return True
            
        except Exception as e:
            logger.error(f"Error soft deleting feedback {feedback_id}: {e}", exc_info=True)
            raise 