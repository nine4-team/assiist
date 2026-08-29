from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from typing import Dict, Any, List
import logging

from .dependencies import verify_internal_secret, UserContext, verify_firebase_token
from dependency_injector.wiring import inject, Provide
from assiist_back_end.containers import Container
from assiist_back_end.services.notification_service import NotificationService
from assiist_back_end.db.repositories.interfaces.notification_repository import NotificationRepository

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Notifications"])

# Notification schemas
from assiist_back_end.api.schemas.notification import (
    SendNotificationRequest,
    NotificationHistoryResponse,
    CancelNotificationsRequest
)

@router.post("/send")
@inject
async def send_notification(
    request: SendNotificationRequest,
    _: bool = Depends(verify_internal_secret),  # Internal API only
    notification_service: NotificationService = Depends(Provide[Container.notification_service])
):
    """
    Internal endpoint to send push notifications for tasks.
    Called by Cloud Functions when scheduled notifications are due.
    """
    try:
        await notification_service.send_task_notification(
            task_id=request.task_id,
            notification_type=request.notification_type,
            task_data=request.task_data,
            contact_name=request.contact_name
        )
        
        return {"status": "success", "message": "Notification sent"}
        
    except Exception as e:
        logger.error(f"❌ Failed to send notification: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to send notification"
        )

@router.get("/history/{task_id}")
@inject
async def get_notification_history(
    task_id: str,
    user_ctx: UserContext = Depends(verify_firebase_token),
    notification_repo: NotificationRepository = Depends(Provide[Container.notification_repository])
) -> NotificationHistoryResponse:
    """
    Get notification history for a specific task.
    """
    try:
        notifications = await notification_repo.get_notification_history(
            task_id=task_id,
            account_id=user_ctx.account_id
        )
        
        return NotificationHistoryResponse(notifications=notifications)
        
    except Exception as e:
        logger.error(f"❌ Failed to get notification history: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get notification history"
        )

@router.post("/cancel")
@inject
async def cancel_notifications(
    request: CancelNotificationsRequest,
    user_ctx: UserContext = Depends(verify_firebase_token),
    notification_service: NotificationService = Depends(Provide[Container.notification_service])
):
    """
    Cancel all pending notifications for a task.
    """
    try:
        await notification_service.cancel_notifications_for_task(
            account_id=user_ctx.account_id,
            task_id=request.task_id
        )
        
        return {"status": "success", "message": "Notifications cancelled"}
        
    except Exception as e:
        logger.error(f"❌ Failed to cancel notifications: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to cancel notifications"
        )

@router.get("/scheduled/{task_id}")
@inject
async def get_scheduled_notifications(
    task_id: str,
    user_ctx: UserContext = Depends(verify_firebase_token),
    notification_repo: NotificationRepository = Depends(Provide[Container.notification_repository])
):
    """
    Get all scheduled notifications for a task.
    """
    try:
        notifications = await notification_repo.get_scheduled_notifications(
            account_id=user_ctx.account_id,
            task_id=task_id
        )
        
        return {"scheduled_notifications": notifications}
        
    except Exception as e:
        logger.error(f"❌ Failed to get scheduled notifications: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get scheduled notifications"
        ) 