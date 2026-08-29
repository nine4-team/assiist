from fastapi import APIRouter, Request, HTTPException, Depends, status
from pydantic import BaseModel
import logging
from google.cloud.firestore_v1.base_query import FieldFilter

# Potentially other necessary imports like settings, specific repository types if needed for type hints
# REMOVE: from assiist_back_end.containers import Container 

logger = logging.getLogger(__name__)

# Dependency provider for the container
def get_container() -> "Container": # TYPE HINT AS STRING
    from assiist_back_end.containers import Container as AppContainer 
    return AppContainer()

router = APIRouter(
    prefix="/internal/tasks", # Prefix for all task handlers
    tags=["Google Cloud Task Handlers"], # OpenAPI tag
)

class GoogleCalendarSyncPayload(BaseModel):
    user_id: str
    connection_email: str
    channel_id: str # Though channel_id might not be strictly needed by perform_incremental_sync, 
                    # it was in the original Celery task, so keeping for consistency.
                    # Review if perform_incremental_sync actually uses it.

@router.post("/google-calendar-incremental-sync", status_code=status.HTTP_202_ACCEPTED)
async def task_process_google_calendar_incremental_sync(
    payload: GoogleCalendarSyncPayload,
    container: "Container" = Depends(get_container) # TYPE HINT AS STRING
    # If your container or specific services are typically injected:
    # firestore_client: AsyncClient = Depends(container.firestore_async_client), # Example
    # app_settings: Settings = Depends(container.config), # Example
    # appointment_repo = Depends(container.appointment_repository), # Example
    # contact_repo = Depends(container.contact_repository), # Example
    # pending_contact_repo = Depends(container.pending_contact_repository) # Example
):
    """
    HTTP handler for Google Cloud Task to process incremental Google Calendar updates.
    This replaces the process_google_calendar_update Celery task.
    """
    logger.info(f"Task 'task_process_google_calendar_incremental_sync' received for user {payload.user_id}, email {payload.connection_email}")

    try:
        from assiist_back_end.services.google_calendar_service import perform_incremental_sync # MOVED IMPORT
        # Obtain dependencies directly from the container if not using Depends for them
        # This assumes the container is already initialized (e.g., at app startup)
        db_client = container.firestore_async_client()
        app_settings = container.config()
        appointment_repo = container.appointment_repository()
        contact_repo = container.contact_repository()
        pending_contact_repo = container.pending_contact_repository()

        # Fetch full connection_data for the service function
        # This logic is similar to the original Celery task
        doc_ref = db_client.collection("users").document(payload.user_id).collection("connected_calendars").document(payload.connection_email)
        connection_doc = await doc_ref.get()

        if not connection_doc.exists:
            logger.error(f"Task 'task_process_google_calendar_incremental_sync': Could not find connection for User {payload.user_id}, Email {payload.connection_email}")
            # Return a 404 or similar, but Google Tasks might retry. 
            # Consider if this should be a non-retryable error for Tasks.
            # For now, let's raise an HTTPException which will result in a non-2xx response.
            # Google Cloud Tasks will retry by default on non-2xx. 
            # You might want specific error codes to control retry behavior.
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Calendar connection not found")

        connection_data = connection_doc.to_dict()
        connection_data.setdefault('user_id', payload.user_id)
        connection_data.setdefault('email', payload.connection_email)

        sync_successful = await perform_incremental_sync(
            user_id=payload.user_id, 
            connection_data=connection_data, 
            db_client=db_client, 
            settings=app_settings
        )

        if not sync_successful:
            logger.warning(f"Incremental sync via task for {payload.connection_email} indicated failure or needs full resync.")
            # perform_incremental_sync should ideally handle its own status updates in Firestore.
            # Decide on the HTTP response. If it's a state that shouldn't be retried by Cloud Tasks,
            # return a success (2xx) to prevent retries, or specific non-retryable 4xx.
            # If it might be resolved by a retry, a 5xx or appropriate 4xx could be used.
            # For now, let's assume a failure here means we don't want Cloud Tasks to retry indefinitely.
            # So we still return 202 Accepted, but log the warning.
            # Alternatively, raise HTTPException(status_code=500, detail="Incremental sync failed") for retries.
            return {"message": "Sync attempted, but underlying operation reported issues. Check logs."}
        
        logger.info(f"Successfully processed incremental sync for {payload.connection_email} via task.")
        return {"message": "Incremental sync processed successfully"}

    except HTTPException:
        raise # Re-raise HTTPExceptions to let FastAPI handle them
    except Exception as e:
        logger.error(f"Unhandled error in 'task_process_google_calendar_incremental_sync' for {payload.connection_email}: {e}", exc_info=True)
        # This will result in a 500 error, and Google Cloud Tasks will retry.
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error during task processing")

# You will need to include this router in your main FastAPI application setup.
# For example, in your main.py or app.py:
# from assiist_back_end.api.endpoints.v1 import google_cloud_task_handlers
# app.include_router(google_cloud_task_handlers.router) 

# --- New Handler for Scheduled Channel Checks ---

# Import services needed by check_google_channels logic
from datetime import datetime, timedelta, timezone # Ensure these are available for the new handler

@router.post("/check-google-channels", status_code=status.HTTP_200_OK) # Or 202 if preferred for long-running background
async def scheduled_check_google_channels(
    container: "Container" = Depends(get_container) # TYPE HINT AS STRING
    # This endpoint might be secured by checking a specific header/token from Cloud Scheduler
    # or by ensuring it's only callable by the Cloud Scheduler service account via IAM.
    # For simplicity, starting without specific auth checks here, but it's important for production.
):
    """
    HTTP handler for Google Cloud Scheduler to periodically check Google Calendar channels.
    This replaces the check_google_channels Celery Beat task.
    """
    logger.info("Scheduled task 'scheduled_check_google_channels' started.")

    try:
        from assiist_back_end.services.google_calendar_service import create_google_watch, perform_initial_sync # MOVED IMPORTS
        db_client = container.firestore_async_client()
        app_settings = container.config() # This is your Settings object
        appointment_repo = container.appointment_repository()
        contact_repo = container.contact_repository()
        pending_contact_repo = container.pending_contact_repository()

        webhook_url = app_settings.GOOGLE_CALENDAR_WEBHOOK_URL
        if not webhook_url:
            logger.error("'scheduled_check_google_channels': GOOGLE_CALENDAR_WEBHOOK_URL not set in settings. Cannot renew channels.")
            # Return an error status that Cloud Scheduler understands as a failure if this is critical
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Webhook URL not configured for channel renewal.")

        users_ref = db_client.collection("users")
        async for user_doc in users_ref.stream():
            user_id = user_doc.id
            connections_ref = users_ref.document(user_id).collection("connected_calendars")
            # Query for Google connections that are active or might need attention
            # Example: .where("provider", "==", "google").where("sync_status", "not-in", ["disabled", "needs_reauthentication"]) 
            # For now, keeping it simple as in the original Celery task.
            async for conn_doc in connections_ref.where(filter=FieldFilter("provider", "==", "google")).stream():
                connection_data = conn_doc.to_dict()
                connection_data['user_id'] = user_id # Ensure user_id is in the dict
                connection_data['email'] = conn_doc.id  # Ensure email is in the dict
                connection_email = conn_doc.id

                logger.info(f"Checking Google channel for User {user_id}, Email {connection_email}")

                needs_renewal = False
                expiration_dt_from_db = connection_data.get('google_channel_expiration')
                
                # Ensure expiration_dt_from_db is a datetime object if it comes from Firestore
                # Firestore might store it as a Timestamp, which needs conversion, or already as datetime.
                # Assuming it's already a timezone-aware datetime object here (as stored by create_google_watch).
                expiration_dt = None
                if isinstance(expiration_dt_from_db, datetime):
                    expiration_dt = expiration_dt_from_db
                # Add handling if it's a string or Firestore Timestamp if necessary

                if expiration_dt:
                    # Ensure app_settings.GOOGLE_CHANNEL_RENEWAL_THRESHOLD_DAYS is an int
                    renewal_threshold_days = int(app_settings.GOOGLE_CHANNEL_RENEWAL_THRESHOLD_DAYS)
                    if expiration_dt < (datetime.now(timezone.utc) + timedelta(days=renewal_threshold_days)):
                        needs_renewal = True
                        logger.info(f"Channel for {connection_email} needs renewal (expires {expiration_dt}).")
                elif connection_data.get('google_channel_id'): # Channel exists but expiration is weird/missing
                    needs_renewal = True
                    logger.warning(f"Channel for {connection_email} has ID but invalid/missing expiration. Attempting renewal.")
                else: # No channel ID, likely needs initial watch or rewatch
                    if connection_data.get("sync_status") == "needs_rewatch" or not connection_data.get('google_channel_id'):
                        needs_renewal = True
                        logger.info(f"Channel for {connection_email} needs initial watch or rewatch (status: {connection_data.get('sync_status')}).")

                if needs_renewal:
                    logger.info(f"Attempting to renew/create watch for {connection_email} via scheduled task...")
                    # create_google_watch is already an async function
                    await create_google_watch(user_id, connection_data, db_client, app_settings, webhook_url)
                
                # Periodic full resync logic (similar to Celery task)
                last_full_sync_attempt_dt = None
                last_full_sync_attempt_from_db = connection_data.get("last_full_sync_attempt")
                if isinstance(last_full_sync_attempt_from_db, datetime):
                    last_full_sync_attempt_dt = last_full_sync_attempt_from_db
                # Add handling for Firestore Timestamp if necessary
                
                periodic_sync_days = int(app_settings.GOOGLE_CALENDAR_PERIODIC_FULL_SYNC_DAYS)
                trigger_full_sync = False
                if connection_data.get("sync_status") == "needs_full_resync":
                    trigger_full_sync = True
                elif periodic_sync_days > 0:
                    if not last_full_sync_attempt_dt or \
                       (last_full_sync_attempt_dt < (datetime.now(timezone.utc) - timedelta(days=periodic_sync_days))):
                        trigger_full_sync = True

                if trigger_full_sync:
                    logger.info(f"Triggering periodic full sync for {connection_email} (Status: {connection_data.get('sync_status')}) via scheduled task.")
                    await connections_ref.document(connection_email).update({"last_full_sync_attempt": datetime.now(timezone.utc)})
                    
                    # perform_initial_sync is already an async function
                    # Fix: Only pass the arguments that perform_initial_sync expects
                    logger.info(f"Calling perform_initial_sync with correct argument list")
                    await perform_initial_sync(
                        user_id=user_id,
                        connection_data=connection_data,
                        db_client=db_client,
                        settings=app_settings
                    )
        
        logger.info("Scheduled task 'scheduled_check_google_channels' finished successfully.")
        return {"message": "Google channel check process completed."}

    except HTTPException: # Re-raise HTTPExceptions to let FastAPI handle them for proper responses
        raise
    except Exception as e:
        logger.error(f"Unhandled error in 'scheduled_check_google_channels': {e}", exc_info=True)
        # This will result in a 500 error, which Cloud Scheduler can interpret as a failed job run.
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error during scheduled channel check.") 