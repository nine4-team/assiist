from pydantic import BaseModel
from typing import Dict, Any, List

class SendNotificationRequest(BaseModel):
    task_id: str
    notification_type: str  # 'actionable' or 'due'
    task_data: Dict[str, Any]
    contact_name: str

class NotificationHistoryResponse(BaseModel):
    notifications: List[Dict[str, Any]]

class CancelNotificationsRequest(BaseModel):
    task_id: str 