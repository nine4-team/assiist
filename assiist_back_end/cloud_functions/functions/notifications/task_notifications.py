import os
import sys
import json
from datetime import datetime, timedelta, timezone
from typing import Dict, Any

# Add the project root to sys.path for imports
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from firebase_functions import firestore_fn
from firebase_admin import firestore as admin_fs
from google.cloud import firestore
from google.cloud import tasks_v2
from google.cloud.firestore_v1.base_query import FieldFilter
import logging

logger = logging.getLogger(__name__)

@firestore_fn.on_document_created(document="contacts/{contactId}/tasks/{taskId}", database="assiist-app", secrets=["ASSIIST_API_KEY"])
def on_task_created(event: firestore_fn.Event[firestore_fn.Change]):
    """
    Firestore trigger that runs when a new task is created.
    Schedules notifications based on task dates.
    """
    try:
        # Get the task data
        task_data = event.data.to_dict()
        task_id = event.params.get('taskId')
        contact_id = event.params.get('contactId')
        
        logger.info(f"📝 Task created: {task_id} for contact: {contact_id}")
        
        # Get account_id for isolation
        account_id = task_data.get('account_id')
        if not account_id:
            logger.error(f"❌ No account_id found for task {task_id}")
            return
        
        # Schedule notifications based on task dates
        _schedule_task_notifications(task_id, contact_id, task_data, account_id)
        
        logger.info(f"✅ Processed task creation for {task_id}")
        
    except Exception as e:
        logger.error(f"❌ Error processing task creation: {e}")
        raise

@firestore_fn.on_document_updated(document="contacts/{contactId}/tasks/{taskId}", database="assiist-app", secrets=["ASSIIST_API_KEY"])
def on_task_updated(event: firestore_fn.Event[firestore_fn.Change]):
    """
    Firestore trigger that runs when a task is updated.
    Cancels old notifications and schedules new ones if dates changed.
    """
    try:
        # Get the task data
        old_data = event.data.before.to_dict()
        new_data = event.data.after.to_dict()
        task_id = event.params.get('taskId')
        contact_id = event.params.get('contactId')
        
        logger.info(f"📝 Task updated: {task_id} for contact: {contact_id}")
        
        # Get account_id for isolation
        account_id = new_data.get('account_id')
        if not account_id:
            logger.error(f"❌ No account_id found for task {task_id}")
            return
        
        # Check if dates changed or task was completed/deleted
        old_actionable = old_data.get('actionable_date')
        new_actionable = new_data.get('actionable_date')
        old_due = old_data.get('due_date')
        new_due = new_data.get('due_date')
        old_status = old_data.get('status')
        new_status = new_data.get('status')
        
        dates_changed = (old_actionable != new_actionable) or (old_due != new_due)
        status_changed = old_status != new_status
        
        if dates_changed or status_changed:
            # Cancel existing notifications
            _cancel_task_notifications(account_id, task_id)
            
            # If task is still pending, schedule new notifications
            if new_status == 'pending':
                _schedule_task_notifications(task_id, contact_id, new_data, account_id)
            
            logger.info(f"✅ Updated notifications for task {task_id}")
        
    except Exception as e:
        logger.error(f"❌ Error processing task update: {e}")
        raise

@firestore_fn.on_document_deleted(document="contacts/{contactId}/tasks/{taskId}", database="assiist-app", secrets=["ASSIIST_API_KEY"])
def on_task_deleted(event: firestore_fn.Event[firestore_fn.Change]):
    """
    Firestore trigger that runs when a task is deleted.
    Cancels all scheduled notifications for the task.
    """
    try:
        task_id = event.params.get('taskId')
        contact_id = event.params.get('contactId')
        
        # Get account_id from the deleted task data
        task_data = event.data.to_dict()
        account_id = task_data.get('account_id')
        
        if not account_id:
            logger.error(f"❌ No account_id found for deleted task {task_id}")
            return
        
        logger.info(f"🗑️ Task deleted: {task_id} for contact: {contact_id}")
        
        # Cancel all notifications for this task
        _cancel_task_notifications(account_id, task_id)
        
        logger.info(f"✅ Cancelled notifications for deleted task {task_id}")
        
    except Exception as e:
        logger.error(f"❌ Error processing task deletion: {e}")
        raise

def _schedule_task_notifications(task_id: str, contact_id: str, task_data: Dict[str, Any], account_id: str):
    """Schedule notifications for a task based on its dates."""
    
    try:
        db = firestore.Client(database="assiist-app")
        # Use timezone-aware UTC datetime
        now = datetime.now(timezone.utc)
        
        # Get actionable and due dates
        actionable_date = task_data.get('actionable_date')
        due_date = task_data.get('due_date')
        
        # In Python Cloud Functions, Firestore timestamps are already `datetime` instances.
        # Only convert if the field is a Firestore `Timestamp` object that exposes `to_datetime`.
        if actionable_date and hasattr(actionable_date, 'to_datetime'):
            actionable_date = actionable_date.to_datetime()
        if due_date and hasattr(due_date, 'to_datetime'):
            due_date = due_date.to_datetime()
        
        notifications_to_schedule = []
        
        # Schedule actionable notification
        if actionable_date and actionable_date > now:
            notifications_to_schedule.append({
                'type': 'actionable',
                'scheduled_for': actionable_date,
                'task_id': task_id,
                'contact_id': contact_id,
                'account_id': account_id,
                'task_data': task_data
            })
        
        # Deduplicate: if due_date is effectively the same as actionable_date (within 1 second),
        # do NOT schedule a separate due notification.
        is_duplicate_due = False
        if actionable_date and due_date:
            time_diff = abs((due_date - actionable_date).total_seconds())
            is_duplicate_due = time_diff < 1  # treat <1-second difference as identical

        if due_date and due_date > now and not is_duplicate_due:
            notifications_to_schedule.append({
                'type': 'due',
                'scheduled_for': due_date,
                'task_id': task_id,
                'contact_id': contact_id,
                'account_id': account_id,
                'task_data': task_data
            })
        
        # Create scheduled notification documents and Cloud Tasks
        for notification in notifications_to_schedule:
            _create_scheduled_notification(db, notification)
        
        logger.info(f"📅 Scheduled {len(notifications_to_schedule)} notifications for task {task_id}")
        
    except Exception as e:
        logger.error(f"❌ Failed to schedule notifications for task {task_id}: {e}")
        raise

def _create_scheduled_notification(db, notification_data: Dict[str, Any]):
    """Create a scheduled notification document and Cloud Task."""
    
    try:
        # Create document in scheduled_notifications collection
        doc_ref = db.collection("scheduled_notifications").document()
        
        notification_doc = {
            'id': doc_ref.id,
            'task_id': notification_data['task_id'],
            'contact_id': notification_data['contact_id'],
            'account_id': notification_data['account_id'],
            'notification_type': notification_data['type'],
            'scheduled_for': notification_data['scheduled_for'],
            'status': 'pending',
            'created_on': firestore.SERVER_TIMESTAMP,
            'is_deleted': False,
            'cloud_task_name': None  # Will be set after creating Cloud Task
        }
        
        doc_ref.set(notification_doc)
        
        # Create Cloud Task for delayed execution
        task_name = _create_cloud_task(notification_data, doc_ref.id)
        
        # Update document with Cloud Task name for cancellation
        if task_name:
            doc_ref.update({'cloud_task_name': task_name})
        
        logger.info(f"📋 Created scheduled notification {doc_ref.id} for task {notification_data['task_id']}")
        
    except Exception as e:
        logger.error(f"❌ Failed to create scheduled notification: {e}")
        raise

def _create_cloud_task(notification_data: Dict[str, Any], notification_id: str) -> str:
    """Create a Cloud Task to send the notification at the scheduled time."""
    
    try:
        # Initialize Cloud Tasks client
        client = tasks_v2.CloudTasksClient()
        
        # Get project and location from environment
        project = os.environ.get('GCP_PROJECT', 'assiist-app')
        location = os.environ.get('CLOUD_TASKS_LOCATION', 'us-central1')
        queue = os.environ.get('CLOUD_TASKS_QUEUE', 'notification-queue')
        
        # Construct the target URL for the send_notification function
        send_notification_url = os.environ.get('SEND_NOTIFICATION_URL')
        if not send_notification_url:
            # For 2nd-gen functions the hostname is REGION-PROJECT_ID.cloudfunctions.net
            region = os.environ.get('FUNCTION_REGION', location)
            send_notification_url = f"https://{region}-{project}.cloudfunctions.net/send_notification"
        
        # Build full queue path (required by Cloud Tasks API)
        parent = client.queue_path(project, location, queue)

        # Create the task
        task = {
            'http_request': {
                'http_method': tasks_v2.HttpMethod.POST,
                'url': send_notification_url,
                'headers': {
                    'Content-Type': 'application/json',
                    'X-Internal-API-Key': os.environ.get('ASSIIST_API_KEY', '')
                },
                'body': json.dumps({
                    'notification_id': notification_id,
                    'task_id': notification_data['task_id'],
                    'contact_id': notification_data['contact_id'],
                    'account_id': notification_data['account_id'],
                    'notification_type': notification_data['type'],
                    'task_data': notification_data['task_data']
                }, default=str).encode()
            },
            'schedule_time': {
                'seconds': int(notification_data['scheduled_for'].timestamp())
            }
        }
        
        # Create the task
        response = client.create_task(parent=parent, task=task)
        
        logger.info(f"⏰ Created Cloud Task: {response.name}")
        return response.name
        
    except Exception as e:
        logger.error(f"❌ Failed to create Cloud Task: {e}")
        return None

def _cancel_task_notifications(account_id: str, task_id: str):
    """Cancel all pending notifications for a task."""
    
    try:
        db = firestore.Client(database="assiist-app")
        
        # Query for pending notifications
        query = (db.collection("scheduled_notifications")
                .where(filter=FieldFilter("account_id", "==", account_id))
                .where(filter=FieldFilter("task_id", "==", task_id))
                .where(filter=FieldFilter("status", "==", "pending"))
                .where(filter=FieldFilter("is_deleted", "==", False)))
        
        docs = query.get()
        
        # Cancel each notification
        for doc in docs:
            doc_data = doc.to_dict()
            
            # Cancel the Cloud Task if it exists
            cloud_task_name = doc_data.get('cloud_task_name')
            if cloud_task_name:
                _cancel_cloud_task(cloud_task_name)
            
            # Update the notification status
            doc.reference.update({
                'status': 'cancelled',
                'updated_on': firestore.SERVER_TIMESTAMP
            })
        
        logger.info(f"🚫 Cancelled {len(docs)} notifications for task {task_id}")
        
    except Exception as e:
        logger.error(f"❌ Failed to cancel notifications for task {task_id}: {e}")
        raise

def _cancel_cloud_task(task_name: str):
    """Cancel a specific Cloud Task."""
    
    try:
        client = tasks_v2.CloudTasksClient()
        client.delete_task(name=task_name)
        logger.info(f"🚫 Cancelled Cloud Task: {task_name}")
        
    except Exception as e:
        logger.error(f"❌ Failed to cancel Cloud Task {task_name}: {e}")
        # Don't raise - notification status will still be updated 