from abc import ABC, abstractmethod
from typing import List, Optional, Dict, Any
from datetime import datetime

class NotificationRepository(ABC):
    @abstractmethod
    async def record_notification_sent(
        self, 
        task_id: str, 
        notification_type: str, 
        sent_at: datetime,
        account_id: str
    ) -> bool:
        """Record that a notification was sent."""
        pass
    
    @abstractmethod
    async def get_notification_history(
        self, 
        task_id: str, 
        account_id: str
    ) -> List[dict]:
        """Get notification history for a task."""
        pass
    
    @abstractmethod
    async def cancel_pending_notifications(
        self,
        account_id: str,
        task_id: str
    ) -> bool:
        """Cancel pending notifications for a task."""
        pass
    
    @abstractmethod
    async def get_scheduled_notifications(
        self,
        account_id: str,
        task_id: str
    ) -> List[dict]:
        """Get scheduled notifications for a task."""
        pass
    
    @abstractmethod
    async def get_pending_notifications(
        self,
        account_id: str,
        task_id: str
    ) -> List[dict]:
        """Get pending notifications for a task."""
        pass 