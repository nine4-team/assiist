from google.cloud.firestore_v1.async_client import AsyncClient
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from assiist_back_end.db.repositories.interfaces.notification_repository import NotificationRepository
from datetime import datetime
from typing import List
import logging

logger = logging.getLogger(__name__)

class FirestoreNotificationRepository(NotificationRepository):
    def __init__(self, db: AsyncClient):
        self.db = db
    
    async def record_notification_sent(
        self, 
        task_id: str, 
        notification_type: str, 
        sent_at: datetime,
        account_id: str
    ) -> bool:
        """Record that a notification was sent following the standard pattern."""
        
        try:
            doc_ref = self.db.collection("notifications").document()
            document_data = {
                "task_id": task_id,
                "notification_type": notification_type,  # 'actionable' or 'due'
                "sent_at": sent_at,
                "account_id": account_id,  # Account isolation like all collections
                "created_on": firestore.SERVER_TIMESTAMP,
                "is_deleted": False,  # Standard soft deletion pattern
                "status": "sent"
            }
            await doc_ref.set(document_data)
            logger.info(f"📱 Recorded notification sent for task {task_id}")
            return True
            
        except Exception as e:
            logger.error(f"❌ Failed to record notification: {e}")
            return False
    
    async def get_notification_history(self, task_id: str, account_id: str) -> List[dict]:
        """Get notification history with account isolation."""
        
        try:
            query = (self.db.collection("notifications")
                    .where(filter=FieldFilter("task_id", "==", task_id))
                    .where(filter=FieldFilter("account_id", "==", account_id))
                    .where(filter=FieldFilter("is_deleted", "==", False))
                    .order_by("sent_at", direction=firestore.Query.DESCENDING))
            
            docs = await query.get()
            return [doc.to_dict() for doc in docs]
            
        except Exception as e:
            logger.error(f"❌ Failed to get notification history: {e}")
            return []
    
    async def cancel_pending_notifications(self, account_id: str, task_id: str) -> bool:
        """Cancel pending notifications for a task."""
        
        try:
            query = (self.db.collection("scheduled_notifications")
                    .where(filter=FieldFilter("account_id", "==", account_id))
                    .where(filter=FieldFilter("task_id", "==", task_id))
                    .where(filter=FieldFilter("status", "==", "pending"))
                    .where(filter=FieldFilter("is_deleted", "==", False)))
            
            docs = await query.get()
            batch = self.db.batch()
            
            for doc in docs:
                batch.update(doc.reference, {
                    "status": "cancelled",
                    "updated_on": firestore.SERVER_TIMESTAMP
                })
            
            await batch.commit()
            logger.info(f"📱 Cancelled {len(docs)} pending notifications for task {task_id}")
            return True
            
        except Exception as e:
            logger.error(f"❌ Failed to cancel notifications: {e}")
            return False
    
    async def get_scheduled_notifications(self, account_id: str, task_id: str) -> List[dict]:
        """Get scheduled notifications for a task."""
        
        try:
            query = (self.db.collection("scheduled_notifications")
                    .where(filter=FieldFilter("account_id", "==", account_id))
                    .where(filter=FieldFilter("task_id", "==", task_id))
                    .where(filter=FieldFilter("is_deleted", "==", False)))
            
            docs = await query.get()
            return [doc.to_dict() for doc in docs]
            
        except Exception as e:
            logger.error(f"❌ Failed to get scheduled notifications: {e}")
            return []
    
    async def get_pending_notifications(self, account_id: str, task_id: str) -> List[dict]:
        """Get pending notifications for a task."""
        
        try:
            query = (self.db.collection("scheduled_notifications")
                    .where(filter=FieldFilter("account_id", "==", account_id))
                    .where(filter=FieldFilter("task_id", "==", task_id))
                    .where(filter=FieldFilter("status", "==", "pending"))
                    .where(filter=FieldFilter("is_deleted", "==", False)))
            
            docs = await query.get()
            return [doc.to_dict() for doc in docs]
            
        except Exception as e:
            logger.error(f"❌ Failed to get pending notifications: {e}")
            return [] 