from assiist_back_end.db.repositories.interfaces.notification_repository import NotificationRepository
from assiist_back_end.db.repositories.interfaces.user_repository import UserRepository
from firebase_admin import messaging
from assiist_back_end.utils.time import utc_now
from typing import Dict, Any, List
import logging

logger = logging.getLogger(__name__)

class NotificationService:
    def __init__(self, notification_repo: NotificationRepository, user_repo: UserRepository):
        self.notification_repo = notification_repo
        self.user_repo = user_repo
    
    async def send_task_notification(
        self, 
        task_id: str, 
        notification_type: str, 
        task_data: Dict[str, Any],
        contact_name: str
    ):
        """Send push notification for a task."""
        
        try:
            # Get account and user info
            account_id = task_data.get('account_id')
            if not account_id:
                raise ValueError("No account_id in task data")
            
            # Get the task owner's user ID
            user_id = task_data.get('user_id')
            if not user_id:
                raise ValueError("No user_id in task data")
            
            # Build notification content
            title, body = self._build_notification_content(
                task_data, notification_type, contact_name
            )
            
            # Send to the task owner
            user_tokens = await self.user_repo.get_fcm_tokens(user_id)
            logger.info(f"📱 Retrieved {len(user_tokens)} FCM tokens for user {user_id}")
            if user_tokens:
                # Log first few chars of each token for debugging
                for i, token in enumerate(user_tokens):
                    logger.info(f"\ud83d\udcf1 Token {i+1}: {token[:20]}...")
                
                sent_count = await self._send_fcm_to_user(user_tokens, title, body, task_data, notification_type)
                logger.info(f"📱 FCM send result: sent_count={sent_count}")
                if sent_count == 0:
                    logger.error(f"❌ All FCM sends failed for user {user_id} (task {task_id})")
                    raise RuntimeError(f"All FCM sends failed for user {user_id} (task {task_id})")
            else:
                logger.warning(f"\ud83d\udcf1 No FCM tokens found for user {user_id}")
                sent_count = 0
            
            # Record that notification was sent (only if at least one send succeeded)
            if sent_count > 0:
                await self.notification_repo.record_notification_sent(
                    task_id=task_id,
                    notification_type=notification_type,
                    sent_at=utc_now(),
                    account_id=account_id
                )
                logger.info(f"✅ Sent {notification_type} notification for task {task_id} to {sent_count} user(s)")
            else:
                logger.warning(f"⚠️ Notification for task {task_id} not recorded as sent (no successful FCM sends)")
            
        except Exception as e:
            logger.error(f"❌ Failed to send notification: {e}")
            raise
    
    async def cancel_notifications_for_task(self, account_id: str, task_id: str):
        """Cancel all pending notifications for a task."""
        
        try:
            # Cancel in database
            await self.notification_repo.cancel_pending_notifications(account_id, task_id)
            
            # Note: Cloud Task cancellation is handled by the Firestore trigger functions
            # They reconstruct task names and cancel the actual scheduled tasks
            
            logger.info(f"✅ Cancelled notifications for task {task_id}")
            
        except Exception as e:
            logger.error(f"❌ Failed to cancel notifications for task {task_id}: {e}")
            raise
    
    def _build_notification_content(self, task_data: Dict, notification_type: str, contact_name: str):
        """Build notification title and body."""
        
        task_type = task_data.get('type')
        task_title = task_data.get('title', '')
        task_body = task_data.get('body', '')
        
        # Truncate body for preview
        preview = task_body[:100] + "..." if len(task_body) > 100 else task_body
        
        if task_type == 'message':
            if notification_type == 'actionable':
                title = f"New Message Draft: {contact_name}"
            else:  # due
                title = f"Message Due: {contact_name}"
            body = preview
            
        elif task_type == 'action':
            if notification_type == 'actionable':
                title = f"New Task: {task_title}"
            else:  # due
                title = f"Task Due: {task_title}"
            body = preview
            
        else:
            title = "New Task"
            body = preview
        
        return title, body
    
    async def _send_fcm_to_user(self, tokens: List[str], title: str, body: str, task_data: Dict, notification_type: str) -> int:
        """Send FCM notification to user's devices."""
        
        successful_sends = 0
        
        logger.info(f"📱 Sending FCM notification - Title: '{title}', Body: '{body[:50]}...'")
        
        for i, token in enumerate(tokens):
            try:
                # Build deep link
                task_id_str = task_data.get('id', '')
                contact_id_str = task_data.get('contact_id', '')
                task_type_str = task_data.get('type', '')
                account_id_str = task_data.get('account_id', '')

                deep_link = (
                    f"assiist://task?task_id={task_id_str}"  # base
                    f"&contact_id={contact_id_str}"
                    f"&task_type={task_type_str}"
                    f"&account_id={account_id_str}"
                )

                message = messaging.Message(
                    notification=messaging.Notification(
                        title=title,
                        body=body,
                    ),
                    data={
                        'type': f'task_{notification_type}',
                        'task_type': task_type_str,
                        'task_id': task_id_str,
                        'contact_id': contact_id_str,
                        'account_id': account_id_str,
                        'link': deep_link,
                    },
                    token=token,
                )
                
                logger.info(f"📱 Sending to token {i+1}/{len(tokens)}: {token[:20]}...")
                response = messaging.send(message)
                logger.info(f"📱 FCM send successful - Response: {response}")
                successful_sends += 1
                
            except Exception as e:
                logger.error(f"❌ Failed to send FCM to token {i+1}/{len(tokens)} ({token[:10]}...): {e}")
                logger.error(f"❌ Error type: {type(e).__name__}")
                if hasattr(e, 'cause'):
                    logger.error(f"❌ Cause: {e.cause}")
         
        logger.info(f"📱 FCM batch complete: {successful_sends}/{len(tokens)} successful sends")
        return successful_sends 