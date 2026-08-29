import os
import sys
import json
from datetime import datetime
from typing import Dict, Any

# Add the project root to sys.path for imports
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from firebase_functions import https_fn
from firebase_admin import firestore as admin_fs
from google.cloud import firestore
import logging
import requests

logger = logging.getLogger(__name__)

@https_fn.on_request(secrets=["ASSIIST_API_KEY"])
def send_notification(request: https_fn.Request) -> https_fn.Response:
    """
    Cloud Function triggered by Cloud Tasks to send push notifications.
    This function delegates to the internal API for actual notification sending.
    """
    try:
        # Verify internal API key
        api_key = request.headers.get('X-Internal-API-Key')
        expected_key = os.environ.get('ASSIIST_API_KEY')
        
        if not api_key or api_key != expected_key:
            logger.warning("❌ Unauthorized request to send_notification")
            return https_fn.Response("Unauthorized", status=401)
        
        # Parse request data
        try:
            data = request.get_json()
        except Exception as e:
            logger.error(f"❌ Invalid JSON in request: {e}")
            return https_fn.Response("Invalid JSON", status=400)
        
        if not data:
            logger.error("❌ No data in request")
            return https_fn.Response("No data provided", status=400)
        
        # Extract notification details
        notification_id = data.get('notification_id')
        task_id = data.get('task_id')
        contact_id = data.get('contact_id')
        account_id = data.get('account_id')
        notification_type = data.get('notification_type')
        task_data = data.get('task_data', {})
        
        if not all([notification_id, task_id, account_id, notification_type]):
            logger.error("❌ Missing required fields in notification request")
            return https_fn.Response("Missing required fields", status=400)
        
        logger.info(f"📱 Processing notification {notification_id} for task {task_id}")
        
        # Get contact name for notification content
        contact_name = _get_contact_name(contact_id, account_id)
        
        # Mark notification as processing
        _update_notification_status(notification_id, 'processing')
        
        # Delegate to internal API for sending
        success = _send_via_internal_api(
            task_id=task_id,
            notification_type=notification_type,
            task_data=task_data,
            contact_name=contact_name
        )
        
        if success:
            # Mark notification as sent
            _update_notification_status(notification_id, 'sent')
            logger.info(f"✅ Successfully sent notification {notification_id}")
            return https_fn.Response("Notification sent", status=200)
        else:
            # Mark notification as failed
            _update_notification_status(notification_id, 'failed')
            logger.error(f"❌ Failed to send notification {notification_id}")
            return https_fn.Response("Failed to send notification", status=500)
        
    except Exception as e:
        logger.error(f"❌ Error in send_notification: {e}")
        
        # Try to mark notification as failed if we have the ID
        notification_id = None
        try:
            data = request.get_json()
            if data:
                notification_id = data.get('notification_id')
        except:
            pass
        
        if notification_id:
            _update_notification_status(notification_id, 'failed')
        
        return https_fn.Response("Internal server error", status=500)

def _get_contact_name(contact_id: str, account_id: str) -> str:
    """Get contact display name from Firestore."""
    
    try:
        if not contact_id:
            return "Unknown Contact"
        
        db = firestore.Client(database="assiist-app")
        contact_ref = db.collection("contacts").document(contact_id)
        contact_doc = contact_ref.get()
        
        if contact_doc.exists:
            contact_data = contact_doc.to_dict()
            # Verify account isolation
            if contact_data.get('account_id') == account_id:
                # Calculate display name from first_name and last_name
                first_name = contact_data.get('first_name', '')
                last_name = contact_data.get('last_name', '')
                if first_name and last_name:
                    return f"{first_name} {last_name}".strip()
                elif first_name:
                    return first_name
                elif last_name:
                    return last_name
                else:
                    return 'Unknown Contact'
        
        return "Unknown Contact"
        
    except Exception as e:
        logger.error(f"❌ Failed to get contact name for {contact_id}: {e}")
        return "Unknown Contact"

def _update_notification_status(notification_id: str, status: str):
    """Update the status of a scheduled notification."""
    
    try:
        db = firestore.Client(database="assiist-app")
        notification_ref = db.collection("scheduled_notifications").document(notification_id)
        
        notification_ref.update({
            'status': status,
            'updated_on': firestore.SERVER_TIMESTAMP
        })
        
        logger.info(f"📋 Updated notification {notification_id} status to {status}")
        
    except Exception as e:
        logger.error(f"❌ Failed to update notification status: {e}")

def _send_via_internal_api(
    task_id: str,
    notification_type: str,
    task_data: Dict[str, Any],
    contact_name: str
) -> bool:
    """Send notification via the internal API."""
    
    try:
        # Determine the internal API base URL
        # Prefer explicitly set API_URL (e.g. https://my-api-run-url/api/v1)
        api_base = os.environ.get('API_URL')

        if api_base:
            # Ensure we are working with the root of the API (strip any trailing /api/v1)
            api_base = api_base.replace("/api/v1", "").rstrip("/")
        else:
            # Fallback: attempt to construct a default URL based on the Cloud Run service if provided
            # Cloud Run services typically have the form https://<region>-<project>.run.app
            project = os.environ.get("GCP_PROJECT", "assiist-app")
            region = os.environ.get("FUNCTION_REGION", os.environ.get("GOOGLE_CLOUD_REGION", "us-central1"))
            # Default to Cloud Functions domain as last-resort (primarily for local emulator)
            api_base = f"https://{region}-{project}.a.run.app"  # 1-gen Cloud Run URL pattern

        # Final endpoint URL
        api_url = f"{api_base}/api/v1/notifications/send"

        # Log the URL and env var for visibility in standard INFO level
        logger.info(f"ENV API_URL value: {os.environ.get('API_URL')}")
        logger.info(f"Internal API URL resolved to: {api_url}")
        
        # Prepare the request payload
        payload = {
            'task_id': task_id,
            'notification_type': notification_type,
            'task_data': task_data,
            'contact_name': contact_name
        }
        
        # Prepare headers
        headers = {
            'Content-Type': 'application/json',
            'X-Internal-API-Key': os.environ.get('ASSIIST_API_KEY', '')
        }
        
        # Make the request
        response = requests.post(
            api_url,
            json=payload,
            headers=headers,
            timeout=30
        )
        
        if response.status_code == 200:
            logger.info(f"✅ Internal API successfully sent notification for task {task_id}")
            return True
        else:
            logger.error(f"❌ Internal API failed with status {response.status_code}: {response.text}")
            return False
        
    except Exception as e:
        logger.error(f"❌ Failed to send via internal API: {e}")
        return False 