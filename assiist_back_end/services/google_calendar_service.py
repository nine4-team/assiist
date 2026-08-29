import logging
from typing import Optional, Dict, Any, List
from datetime import datetime, timezone, timedelta
import uuid
import asyncio
from datetime import datetime, timezone, timedelta
# --- ADDED: urllib.parse for URL manipulation ---
from urllib.parse import urlparse, urlunparse

from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from google.auth.exceptions import RefreshError
from google.cloud.firestore_v1.async_client import AsyncClient
from google.cloud.firestore_v1.base_query import FieldFilter
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

from assiist_back_end.config import Settings # Assuming your Settings class is here
# from assiist_back_end.models.calendar_connection import CalendarConnection # We'll use dict for connection_data initially
# Import models needed for mapping and processing
from assiist_back_end.models.calendar_connection import CalendarConnection 
from assiist_back_end.models.appointment import Appointment, Attendee, Attachment
from assiist_back_end.models.pending_contact import PendingContact 
# Import repository interfaces for type hinting
from assiist_back_end.db.repositories.interfaces.appointment_repository import AppointmentRepository
from assiist_back_end.db.repositories.interfaces.contact_repository import ContactRepository
from assiist_back_end.db.repositories.interfaces.pending_contact_repository import PendingContactRepository

# Add GCloud Tasks imports
from google.cloud import tasks_v2
import json
# Import the payload model for the new task handler
from assiist_back_end.api.endpoints.v1.google_cloud_task_handlers import GoogleCalendarSyncPayload

logger = logging.getLogger(__name__)

async def _get_account_id_from_user_id(db_client: AsyncClient, user_id: str) -> str:
    """Helper to get account_id from user document."""
    try:
        user_ref = db_client.collection("users").document(user_id)
        user_doc = await user_ref.get()
        if user_doc.exists:
            account_id = user_doc.to_dict().get("account_id")
            if account_id:
                return account_id
        
        raise ValueError(f"Account ID not found for user {user_id}")
        
    except Exception as e:
        logger.error(f"Error getting account_id for user {user_id}: {e}")
        raise

async def get_valid_google_credentials(
    user_id: str,
    connection_data: Dict[str, Any],  # Pass data from Firestore as a dict
    db_client: AsyncClient,
    settings: Settings # Pass settings explicitly or load globally
) -> Optional[Credentials]:
    """Gets valid Google credentials from stored data, handling refresh."""
    logger.debug(f"Getting credentials for user {user_id}, email {connection_data.get('email')}")
    
    if not connection_data.get('access_token'):
        logger.warning(f"No access_token for {connection_data.get('email')}")
        # Potentially mark for re-authentication here if this state is unexpected
        # For now, just returning None as the watch/sync will fail anyway.
        return None

    creds_info = {
        "token": connection_data['access_token'],
        "refresh_token": connection_data.get('refresh_token'),
        "token_uri": settings.GOOGLE_TOKEN_URI,
        "client_id": settings.GOOGLE_CLIENT_ID,
        "client_secret": settings.GOOGLE_CLIENT_SECRET.get_secret_value() if settings.GOOGLE_CLIENT_SECRET else None,
        "scopes": connection_data.get('scopes', [
            "https://www.googleapis.com/auth/calendar.readonly",
            "https://www.googleapis.com/auth/calendar.events.readonly",
            "https://www.googleapis.com/auth/calendar.freebusy"
        ]),
        # The from_authorized_user_info method expects 'expiry' to be an ISO 8601 string
        # if the original token_expiry was stored as datetime, it needs conversion here
        # For now, assuming connection_data['token_expiry'] is already an ISO string
        "expiry": connection_data.get('token_expiry'),
        "user_timezone": connection_data.get('user_timezone', "UTC")
    }

    # --- DEBUG: Log types of creds_info values to quickly spot type mismatches (does not leak secrets) ---
    logger.debug("creds_info value types: %s", {k: type(v).__name__ for k, v in creds_info.items()})

    try:
        creds = Credentials.from_authorized_user_info(creds_info)
    except Exception as e:
        logger.error(f"Error creating Credentials object for {connection_data.get('email')}: {e}", exc_info=True)
        return None

    if not creds.valid:
        if creds.expired and creds.refresh_token:
            logger.info(f"Refreshing Google token for {connection_data.get('email')}")
            try:
                creds.refresh(Request())
                logger.info(f"Google token for {connection_data.get('email')} refreshed successfully.")
                
                # Persist the refreshed token to Firestore
                calendar_doc_ref = db_client.collection("users").document(user_id)\
                    .collection("connected_calendars").document(connection_data['email'])
                
                update_payload = {
                    "access_token": creds.token,
                    "token_expiry": creds.expiry.isoformat() if creds.expiry else None,
                    # Google might issue a new refresh token during refresh, though rare.
                    # If creds.refresh_token changed and is different from connection_data['refresh_token'], update it.
                }
                if creds.refresh_token and creds.refresh_token != connection_data.get('refresh_token'):
                    update_payload['refresh_token'] = creds.refresh_token

                await calendar_doc_ref.update(update_payload)
                logger.info(f"Successfully persisted refreshed token for {connection_data.get('email')}")
            
            except RefreshError as e_refresh:
                error_details = getattr(e_refresh, 'args', [{}])[0]
                error_description = "Unknown token refresh error."
                if isinstance(error_details, dict):
                    error_description = error_details.get('error_description', str(error_details.get('error', e_refresh)))
                elif isinstance(error_details, str):
                    error_description = error_details

                logger.error(f"Failed to refresh token for {connection_data.get('email')}: {error_description}", exc_info=True)
                calendar_doc_ref = db_client.collection("users").document(user_id)\
                    .collection("connected_calendars").document(connection_data['email'])
                await calendar_doc_ref.update({
                    "sync_status": "needs_reauthentication",
                    "sync_status_message": f"Token refresh failed: {error_description}",
                    "access_token": None, # Clear stale access token
                    "google_channel_id": None, # Stop notifications if auth fails
                    "google_sync_token": None,
                })
                return None
            except Exception as e_other:
                logger.error(f"An unexpected error occurred during token refresh for {connection_data.get('email')}: {e_other}", exc_info=True)
                # Potentially update sync_status to a generic error here
                return None
        else:
            logger.warning(f"Google token for {connection_data.get('email')} is invalid and no refresh token is available or not expired yet but invalid.")
            # Mark for re-authentication if not already marked by a failed refresh attempt
            if connection_data.get("sync_status") != "needs_reauthentication":
                calendar_doc_ref = db_client.collection("users").document(user_id)\
                    .collection("connected_calendars").document(connection_data['email'])
                await calendar_doc_ref.update({
                    "sync_status": "needs_reauthentication",
                    "sync_status_message": "Token invalid and cannot be refreshed.",
                    "access_token": None,
                    "google_channel_id": None,
                    "google_sync_token": None,
                })
            return None
            
    logger.debug(f"Credentials for {connection_data.get('email')} are valid.")
    return creds

async def create_google_watch(
    user_id: str,
    connection_data: Dict[str, Any], # Pass data from Firestore as a dict
    db_client: AsyncClient,
    settings: Settings,
    webhook_url: str # Publicly accessible URL for the webhook receiver endpoint
) -> bool:
    """Creates or renews a Google Calendar Push Notification channel."""
    connection_email = connection_data.get('email')
    if not connection_email:
        logger.error(f"Cannot create watch for user {user_id}: connection_data missing 'email'.")
        return False
        
    logger.info(f"Attempting to create/renew watch channel for user {user_id}, email {connection_email}")

    creds = await get_valid_google_credentials(user_id, connection_data, db_client, settings)
    if not creds:
        logger.error(f"Failed to get valid credentials for {connection_email} (User: {user_id}). Cannot create watch channel.")
        # get_valid_google_credentials already updated Firestore status
        return False

    calendar_doc_ref = db_client.collection("users").document(user_id).collection("connected_calendars").document(connection_email)

    try:
        service = build('calendar', 'v3', credentials=creds, static_discovery=False)
        
        channel_id = str(uuid.uuid4()) # Generate a unique ID for this channel instance
        # Optional: Add a secret token for validation at the webhook receiver
        # channel_token = f"user:{user_id}:conn:{connection_email}" 

        watch_request_body = {
            'id': channel_id,
            'type': 'web_hook',
            'address': webhook_url,
            # 'token': channel_token, # Uncomment to include validation token
            # 'params': { 'ttl': str(int(timedelta(days=7).total_seconds())) } # Optional: Suggest TTL (Google might ignore)
        }
        
        logger.critical(f"DEBUG: Webhook URL being sent to Google: {webhook_url}")
        logger.critical(f"Calling Google Calendar API events.watch for {connection_email} with channel ID {channel_id}...")
        watch_response = service.events().watch(calendarId='primary', body=watch_request_body).execute()
        logger.critical(f"Google Calendar API events.watch call successful for {connection_email}. Response: {watch_response}")

        channel_id_resp = watch_response.get('id')
        resource_id_resp = watch_response.get('resourceId')
        expiration_ms_str = watch_response.get('expiration') # Expiration time in milliseconds since epoch (string)

        if not all([channel_id_resp, resource_id_resp, expiration_ms_str]):
            logger.error(f"Watch response missing required fields for {connection_email}: {watch_response}")
            await calendar_doc_ref.update({"sync_status": "channel_error", "sync_status_message": "Watch API response missing required fields."})
            return False
            
        # Convert expiration from ms string to datetime
        expiration_dt = datetime.fromtimestamp(int(expiration_ms_str) / 1000, tz=timezone.utc)
        
        # Update Firestore with new channel details
        await calendar_doc_ref.update({
            "google_channel_id": channel_id_resp,
            "google_resource_id": resource_id_resp,
            "google_channel_expiration": expiration_dt, # Store as datetime object
            "sync_status": "channel_active",
            "sync_status_message": f"Watch channel active, expires {expiration_dt.isoformat()}"
        })
        logger.info(f"Successfully created/updated watch channel in Firestore for {connection_email}. Expires: {expiration_dt}")
        return True

    except HttpError as error:
        logger.error(f"Google API error creating watch channel for {connection_email}: {error}", exc_info=True)
        await calendar_doc_ref.update({"sync_status": "channel_error", "sync_status_message": f"Google API error creating watch: {error.resp.status} - {str(error.content)[:100]}"})
        return False
    except Exception as e:
        logger.error(f"Unexpected error creating watch channel for {connection_email}: {e}", exc_info=True)
        await calendar_doc_ref.update({"sync_status": "error_other", "sync_status_message": f"Unexpected error creating watch: {str(e)}"})
        return False

async def stop_google_watch(
    user_id: str,
    connection_data: Dict[str, Any], # Pass data from Firestore as a dict
    db_client: AsyncClient,
    settings: Settings
) -> bool:
    """Stops a Google Calendar Push Notification channel."""
    connection_email = connection_data.get('email')
    channel_id = connection_data.get('google_channel_id')
    resource_id = connection_data.get('google_resource_id')

    if not connection_email:
        logger.error(f"Cannot stop watch for user {user_id}: connection_data missing 'email'.")
        return False
    
    if not channel_id or not resource_id:
        logger.warning(f"No active channel_id or resource_id found for {connection_email} (User: {user_id}). Nothing to stop.")
        # Optionally ensure fields are cleared if they are partially set
        calendar_doc_ref_check = db_client.collection("users").document(user_id).collection("connected_calendars").document(connection_email)
        await calendar_doc_ref_check.update({
            "google_channel_id": None,
            "google_resource_id": None,
            "google_channel_expiration": None,
            "google_sync_token": None,
            "sync_status": "inactive", # Or original status if no channel was active
            "sync_status_message": "No active channel to stop, or already stopped."
        })
        return True # Considered success as there's nothing to stop

    logger.info(f"Attempting to stop watch channel {channel_id} for user {user_id}, email {connection_email}")

    creds = await get_valid_google_credentials(user_id, connection_data, db_client, settings)
    if not creds:
        logger.error(f"Failed to get valid credentials for {connection_email} (User: {user_id}). Cannot stop watch channel.")
        # get_valid_google_credentials already updated Firestore status
        return False

    calendar_doc_ref = db_client.collection("users").document(user_id).collection("connected_calendars").document(connection_email)

    try:
        service = build('calendar', 'v3', credentials=creds, static_discovery=False)
        
        stop_request_body = {
            'id': channel_id,
            'resourceId': resource_id
        }
        
        logger.info(f"Calling Google Calendar API channels.stop for {connection_email} with channel ID {channel_id}...")
        service.channels().stop(body=stop_request_body).execute()
        logger.info(f"Google Calendar API channels.stop call successful for {connection_email}.")

        # Clear channel details in Firestore
        await calendar_doc_ref.update({
            "google_channel_id": None,
            "google_resource_id": None,
            "google_channel_expiration": None,
            "google_sync_token": None, # Also clear sync token when channel is stopped
            "sync_status": "inactive", # Or revert to a default status
            "sync_status_message": "Watch channel successfully stopped."
        })
        logger.info(f"Successfully cleared watch channel details in Firestore for {connection_email}.")
        return True

    except HttpError as error:
        # Google might return 404 if channel already expired or was manually deleted, which is fine.
        if error.resp.status == 404:
            logger.warning(f"Google API returned 404 stopping channel for {connection_email} (Channel ID: {channel_id}). Channel likely already inactive. Clearing details.", exc_info=True)
            await calendar_doc_ref.update({
                "google_channel_id": None,
                "google_resource_id": None,
                "google_channel_expiration": None,
                "google_sync_token": None,
                "sync_status": "inactive",
                "sync_status_message": "Channel already inactive or not found by Google (404)."
            })
            return True # Treat as success in this case
        else:
            logger.error(f"Google API error stopping watch channel for {connection_email}: {error}", exc_info=True)
            # Don't change sync_status to error if stopping fails, as it might be a transient issue
            # or the channel might not be valid anymore. The important part is that we tried.
            # However, log it for investigation.
            await calendar_doc_ref.update({"sync_status_message": f"Google API error stopping watch: {error.resp.status} - {str(error.content)[:100]}"})
            return False
    except Exception as e:
        logger.error(f"Unexpected error stopping watch channel for {connection_email}: {e}", exc_info=True)
        await calendar_doc_ref.update({"sync_status_message": f"Unexpected error stopping watch: {str(e)}"})
        return False

# --- Helper: Parse Google Datetime ---
# (Copied from tasks.py - needed for mapping)
def _parse_google_datetime(google_datetime_info: dict, field_name: str = 'dateTime') -> Optional[datetime]:
    """Parses Google's event date/datetime structure into a timezone-aware datetime object."""
    if not google_datetime_info:
        return None
    
    datetime_str = google_datetime_info.get(field_name) # For timed events
    date_str = google_datetime_info.get('date') # For all-day events

    dt = None
    if datetime_str:
        # Support RFC3339 'Z' suffix (UTC) which datetime.fromisoformat does not handle.
        if datetime_str.endswith('Z'):
            datetime_str = datetime_str.replace('Z', '+00:00')
        try:
            dt = datetime.fromisoformat(datetime_str)
        except ValueError:
            logger.error(f"Could not parse datetime string: {datetime_str}")
            return None
    elif date_str:
        # For all-day events, Google provides a date. We interpret this as start of day in UTC.
        # Or, if a timezone is provided with the event, use that. For simplicity, UTC for now.
        try:
            dt = datetime.strptime(date_str, '%Y-%m-%d').replace(tzinfo=timezone.utc)
        except ValueError:
            logger.error(f"Could not parse date string: {date_str}")
            return None
    return dt
# --- END Helper: Parse Google Datetime ---

# --- Helper: Map Google Event to Appointment ---
# (Adapted from _google_event_to_appointment in tasks.py)
async def _map_google_event_to_appointment(
    event_data: dict,
    user_id: str,
    connection: CalendarConnection, # Use the Pydantic model here
    existing_appointment: Optional[Appointment] = None # Add parameter for existing appointment
) -> Optional[Appointment]:
    """Maps a Google Calendar event resource (dict) to our Appointment Pydantic model."""
    try:
        start_time_obj = _parse_google_datetime(event_data.get('start'))
        end_time_obj = _parse_google_datetime(event_data.get('end'))
        is_all_day = 'date' in event_data.get('start', {}) and 'date' in event_data.get('end', {})

        attendees_data = event_data.get('attendees', [])
        mapped_attendees = []
        for att_data in attendees_data:
            mapped_attendees.append(Attendee(
                email=att_data.get('email'),
                name=att_data.get('displayName'),
                response_status=att_data.get('responseStatus'),
                is_optional=att_data.get('optional', False)
            ))
        
        organizer_data = event_data.get('organizer')
        mapped_organizer = None
        if organizer_data:
            mapped_organizer = Attendee(
                email=organizer_data.get('email'), 
                name=organizer_data.get('displayName')
            )

        google_attachments = event_data.get('attachments', [])
        mapped_attachments = []
        for g_att in google_attachments:
            mapped_attachments.append(Attachment(
                file_url=g_att.get('fileUrl'),
                mime_type=g_att.get('mimeType'),
                title=g_att.get('title')
            ))
        
        # Check for reschedule if we have an existing appointment
        is_rescheduled = False
        original_start_time = None
        original_end_time = None
        reschedule_reason = None
        reschedule_count = 0

        if existing_appointment:
            # Check if start time or end time has changed
            if (existing_appointment.start_time and start_time_obj and 
                existing_appointment.start_time != start_time_obj):
                
                # This is a reschedule
                is_rescheduled = True
                
                # Keep original time if this is the first reschedule
                if not existing_appointment.is_rescheduled:
                    original_start_time = existing_appointment.start_time
                    original_end_time = existing_appointment.end_time
                else:
                    # Keep the original times from the first reschedule
                    original_start_time = existing_appointment.original_start_time
                    original_end_time = existing_appointment.original_end_time
                
                # Increment reschedule count
                reschedule_count = existing_appointment.reschedule_count + 1
                
                # Check if there's any description change that might indicate reason
                if (existing_appointment.description != event_data.get('description') and 
                    event_data.get('description')):
                    reschedule_reason = event_data.get('description')
            else:
                # Not a reschedule or already tracked, preserve existing values
                is_rescheduled = existing_appointment.is_rescheduled
                original_start_time = existing_appointment.original_start_time
                original_end_time = existing_appointment.original_end_time
                reschedule_reason = existing_appointment.reschedule_reason
                reschedule_count = existing_appointment.reschedule_count

        appointment = Appointment(
            user_id=user_id,
            external_id=event_data.get('id'),
            calendar_provider=connection.provider, # Should be "google"
            source_account_id=connection.email, # Using email as the identifier for the connected account
            title=event_data.get('summary'),
            description=event_data.get('description'),
            start_time=start_time_obj,
            end_time=end_time_obj,
            timezone=event_data.get('start', {}).get('timeZone'), # Google might provide this
            is_all_day=is_all_day,
            location=event_data.get('location'),
            organizer=mapped_organizer,
            attendees=mapped_attendees,
            attachments=mapped_attachments,
            status=event_data.get('status'), # e.g., confirmed, tentative, cancelled
            source_created_on=_parse_google_datetime({'dateTime': event_data.get('created')}) if event_data.get('created') else None,
            source_updated_on=_parse_google_datetime({'dateTime': event_data.get('updated')}) if event_data.get('updated') else None,
            # Reschedule tracking fields
            is_rescheduled=is_rescheduled,
            original_start_time=original_start_time,
            original_end_time=original_end_time,
            reschedule_reason=reschedule_reason,
            reschedule_count=reschedule_count,
            # assiist_contact_ids will be populated later if needed
            # processed_on will be set when we process it
            # needs_contact_creation_prompt can be determined based on attendees
        )
        return appointment
    except Exception as e:
        logger.error(f"Error mapping Google event to Appointment. Event ID: {event_data.get('id')}, Error: {e}", exc_info=True)
        return None
# --- END Helper: Map Google Event to Appointment ---

# --- Helper: Process Attendees for Pending Contacts ---
# (Adapted from _process_attendees in tasks.py)
async def _process_attendees_for_pending_contacts(
    appointment: Appointment,  # The mapped Appointment model
    user_id: str,
    account_id: str,  # Account scoping
    contact_repo: ContactRepository,
    pending_contact_repo: PendingContactRepository,
    calendar_owner_email: str,
    *,
    allow_auto_note: bool = True,
) -> bool:
    """Processes attendees for an appointment.

    A single helper now drives **both** pending-contact generation and optional auto-note creation.  The new
    ``allow_auto_note`` flag prevents unnecessary Update-Assistant traffic when the appointment hasn't actually
    changed (e.g. during every incremental sync run).  We only set the flag to ``True`` when one of the following
    is true:

    1. The appointment is *new* (no existing record in Firestore)
    2. The appointment is marked ``is_rescheduled`` (time change)

    Anything else means the event is simply an update we've already processed, so we skip auto-note creation to
    avoid the noisy *"skipping auto-note – already exists"* log spam the user observed.
    """
    # Skip cancelled appointments - they should not create pending contacts
    if appointment.status == "cancelled":
        logger.info(f"ATTENDEE CHECK: Skipping cancelled appointment {appointment.external_id} - no pending contacts will be created")
        return False
    
    logger.critical(f"ATTENDEE CHECK: Event {appointment.external_id} has {len(appointment.attendees) if appointment.attendees else 0} total attendees")
    
    new_pending_contacts_created = False
    if not appointment.attendees:
        logger.critical(f"ATTENDEE CHECK: Event {appointment.external_id} - NO ATTENDEES, returning False")
        return False
        
    # Filter: Only consider events with two or fewer invitees (excluding the host)
    # Count attendees excluding the calendar owner
    non_owner_attendees = [att for att in appointment.attendees if att.email != calendar_owner_email]
    logger.critical(f"ATTENDEE CHECK: Event {appointment.external_id} has {len(non_owner_attendees)} non-owner attendees (limit=2)")
    if len(non_owner_attendees) > 2:
        logger.critical(f"ATTENDEE CHECK: Event {appointment.external_id} - TOO MANY ATTENDEES ({len(non_owner_attendees)}), returning False")
        return False

    logger.critical(f"ATTENDEE CHECK: Event {appointment.external_id} - Starting attendee loop with {len(appointment.attendees)} attendees")
    for attendee in appointment.attendees:
        logger.critical(f"ATTENDEE CHECK: Processing attendee {attendee.email} (name: {attendee.name})")
        if not attendee.email:
            logger.critical(f"ATTENDEE CHECK: Attendee {attendee.name or 'N/A'} has no email, skipping")
            continue

        # Skip if the attendee is the calendar owner
        if attendee.email == calendar_owner_email:
            logger.critical(f"ATTENDEE CHECK: Attendee {attendee.email} is the calendar owner, skipping")
            continue
        
        # Also skip if attendee is the organizer and their email matches the calendar owner
        if appointment.organizer and appointment.organizer.email == attendee.email and attendee.email == calendar_owner_email:
            logger.debug(f"Attendee {attendee.email} is the organizer (self), skipping.")
            continue
        
        try:
            # 1. Check if a full Contact already exists
            existing_contact = await contact_repo.get_contact_by_email(account_id=account_id, email=attendee.email)
            if existing_contact:
                logger.debug(
                    "SKIP attendee=%s → already full Contact id=%s", attendee.email, existing_contact.id
                )
                # Auto-notes for existing contacts are optional per caller
                if allow_auto_note:
                    logger.critical(f"ATTENDEE CHECK: Contact already exists for {attendee.email}, scheduling auto-note")
                    try:
                        if appointment.is_rescheduled:
                            await _schedule_reschedule_note_for_contact(
                                appointment=appointment,
                                contact_id=str(existing_contact.id),
                                user_id=user_id,
                                account_id=account_id,
                            )
                        else:
                            await _schedule_auto_note_for_contact(
                                appointment=appointment,
                                contact_id=str(existing_contact.id),
                                user_id=user_id,
                                account_id=account_id,
                            )
                    except Exception as auto_exc:
                        logger.error(
                            f"Failed to schedule auto-note for contact {existing_contact.id}: {auto_exc}",
                            exc_info=True,
                        )
                continue

            # 2. Check if a PendingContact already exists for this email and user.
            existing_pending_contact = await pending_contact_repo.get_by_email(
                user_id=user_id, 
                email=attendee.email
            )
            if existing_pending_contact:
                logger.debug(
                    "SKIP attendee=%s → existing PendingContact id=%s status=%s", attendee.email, existing_pending_contact.id, getattr(existing_pending_contact, "status", "unknown")
                )
                # Only block processing if the pending contact is still in a PENDING state
                if getattr(existing_pending_contact, "status", "pending") == "pending":
                    logger.critical(f"ATTENDEE CHECK: Pending contact still pending for {attendee.email}, skipping auto-note")
                    continue
                else:
                    logger.info(
                        "ATTENDEE CHECK: Pending contact for %s has status '%s' – treating as resolved.",
                        attendee.email,
                        existing_pending_contact.status,
                    )
                    # Fall through and process as normal (existing_contact lookup already failed)

            # 3. Create new PendingContact
            logger.critical(f"ATTENDEE CHECK: Creating new pending contact for email: {attendee.email} from event: {appointment.external_id}")
            logger.info(f"Creating new pending contact for email: {attendee.email} from event: {appointment.external_id} for user: {user_id}")
            
            new_pending_contact = PendingContact(
                user_id=user_id,
                email=attendee.email,
                display_name=(attendee.name or attendee.email),
                source_event_id=appointment.external_id,
                source_event_title=appointment.title,
                phone=None,
                appointment_time=appointment.start_time,
                appointment_notes=appointment.description,
                # Include reschedule information
                is_rescheduled=appointment.is_rescheduled,
                original_appointment_time=appointment.original_start_time,
                reschedule_reason=appointment.reschedule_reason
                # id, status, created_on, updated_on handled by model/repo
            )
            
            created_pc = await pending_contact_repo.add(pending_contact=new_pending_contact)
            if created_pc:
                new_pending_contacts_created = True
                logger.info(f"Successfully created pending contact for {attendee.email} (User: {user_id})")
                logger.debug("CREATED PendingContact id=%s for %s via event %s", created_pc.id, attendee.email, appointment.external_id)
            else:
                logger.error(f"Failed to create pending contact for {attendee.email} (User: {user_id})\")")
        
        except Exception as ex_attendee:
            logger.error(f"Error processing attendee {attendee.email} for appointment {appointment.external_id}: {ex_attendee}", exc_info=True)
            continue # Continue with the next attendee
            
        logger.critical(f"ATTENDEE CHECK: Event {appointment.external_id} - Completed processing, created new contacts: {new_pending_contacts_created}")
    return new_pending_contacts_created
# --- END Helper: Process Attendees ---

# --- Function to perform initial/full sync ---
async def perform_initial_sync(
    user_id: str,
    connection_data: Dict[str, Any], # Pass data from Firestore as a dict
    db_client: AsyncClient,
    settings: Settings
) -> bool:
    """Performs an initial full sync of Google Calendar events and stores the first sync token."""
    logger.info(f"CRITICAL_LOG: perform_initial_sync BACKGROUND TASK STARTED for user {user_id}, email {connection_data.get('email')}") # NEW TOP-LEVEL LOG
    # --- ADDED: Import Container inside function ---
    try:
        logger.critical("CRITICAL_LOG: About to import Container")
        from assiist_back_end.containers import Container
        logger.critical("CRITICAL_LOG: Container import successful")
        
        container = Container()
        logger.critical("CRITICAL_LOG: Container instantiated")
        
        appointment_repo: AppointmentRepository = container.appointment_repository()
        contact_repo: ContactRepository = container.contact_repository()
        pending_contact_repo: PendingContactRepository = container.pending_contact_repository()
        logger.critical("CRITICAL_LOG: Repositories obtained from container")
        
        # Get account_id for proper contact scoping
        account_id = await _get_account_id_from_user_id(db_client, user_id)
        logger.info(f"CRITICAL_LOG: Retrieved account_id: {account_id}")
    except Exception as container_error:
        logger.info(f"CRITICAL_LOG: ERROR during container setup: {container_error}", exc_info=True)
        return False
    # --- END ADDED ---

    connection_email = connection_data.get('email')
    if not connection_email:
        logger.critical(f"CRITICAL_LOG: Missing email in connection_data for user {user_id}")
        logger.error(f"Cannot perform initial sync for user {user_id}: connection_data missing 'email'.")
        return False
        
    logger.critical(f"CRITICAL_LOG: Starting get_valid_google_credentials for {connection_email}")
    creds = await get_valid_google_credentials(user_id, connection_data, db_client, settings)
    if not creds:
        logger.critical(f"CRITICAL_LOG: Failed to get valid credentials for {connection_email}")
        logger.error(f"Failed to get valid credentials for {connection_email} (User: {user_id}). Cannot perform initial sync.")
        return False
    logger.critical(f"CRITICAL_LOG: Successfully got valid credentials for {connection_email}")

    calendar_doc_ref = db_client.collection("users").document(user_id).collection("connected_calendars").document(connection_email)
    
    # Convert dict to Pydantic model for mapping function
    try:
        logger.critical(f"CRITICAL_LOG: Creating CalendarConnection model from data for {connection_email}")
        connection_model = CalendarConnection(**connection_data)
        logger.critical(f"CRITICAL_LOG: Successfully created CalendarConnection model for {connection_email}")
    except Exception as e:
        logger.critical(f"CRITICAL_LOG: ERROR creating CalendarConnection model: {e}")
        logger.error(f"PerformInitialSync: Failed to parse connection_data into CalendarConnection model for {connection_email}: {e}", exc_info=True)
        await calendar_doc_ref.update({"sync_status": "error_other", "sync_status_message": "Failed to parse connection data during sync."})
        return False

    logger.critical(f"CRITICAL_LOG: About to build Google API service for {connection_email}")
    try:
        service = build('calendar', 'v3', credentials=creds, static_discovery=False)
        logger.critical(f"CRITICAL_LOG: Google API service built successfully for {connection_email}")

        # According to Google Calendar API documentation and the sync guide:
        # 1. We need consistent query parameters between initial sync and incremental sync
        # 2. The sync token appears only on the last page of results
        # 3. We can use time constraints during the initial sync
        
        # Set time constraints for the syncing - only next 14 days, no past events
        now = datetime.now(timezone.utc) 
        time_min = now.isoformat()  # Start from now
        time_max = (now + timedelta(days=14)).isoformat()  # Only look 14 days ahead
        logger.critical(f"CRITICAL_LOG: Time range set for syncing: {time_min} to {time_max} (next 14 days only)")

        all_google_events = []
        page_token = None

        logger.critical(f"CRITICAL_LOG: Entering event fetching loop for {connection_email}")
        while True:
            logger.critical(f"CRITICAL_LOG: Making API call to events().list for {connection_email}, page_token={page_token}")
            try:
                # Make a single consistent call that will also be used for incremental sync
                events_result = service.events().list(
                    calendarId='primary',
                    timeMin=time_min,
                    timeMax=time_max,
                    maxResults=250, 
                    singleEvents=True,
                    orderBy='updated',  # This must be 'updated' to get a sync token
                    pageToken=page_token,
                    showDeleted=True    # Required for sync token
                ).execute()
                logger.critical(f"CRITICAL_LOG: API call successful")
                logger.critical(f"CRITICAL_LOG: Events API response keys: {list(events_result.keys())}")
                logger.critical(f"CRITICAL_LOG: Events API response content sample: {str(events_result)[:1000]}...")
            except Exception as api_error:
                logger.critical(f"CRITICAL_LOG: API call error: {api_error}", exc_info=True)
                raise  # Re-raise to be caught by outer try/except
            
            current_page_events = events_result.get('items', [])
            logger.critical(f"CRITICAL_LOG: Fetched {len(current_page_events)} events on this page")
            all_google_events.extend(current_page_events)
            
            # --- MODIFIED LOGGING ---
            current_page_sync_token = events_result.get('nextSyncToken') 
            if current_page_sync_token:
                sync_token = current_page_sync_token # Always update to the latest sync token received
                logger.critical(f"CRITICAL_LOG: Got nextSyncToken: {current_page_sync_token}")
            
            page_token = events_result.get('nextPageToken')
            logger.critical(f"CRITICAL_LOG: nextPageToken: {page_token}")
            
            logger.info(f"Fetched page of {len(current_page_events)} events for {connection_email}. Events on page: {len(current_page_events)}. SyncToken on THIS page: {current_page_sync_token}. Overall latest SyncToken so far: {sync_token}. NextPageToken: {page_token}")
            # --- END MODIFIED LOGGING ---
            
            if not page_token:
                logger.critical(f"CRITICAL_LOG: No more pages (nextPageToken is None). Final sync_token: {sync_token}")
                break # No more pages

        logger.critical(f"CRITICAL_LOG: Fetched total of {len(all_google_events)} events. Final Sync Token: {sync_token}")

        # --- NEW: Sort events chronologically so pending contacts are created for the earliest occurrence first ---
        def _get_event_start_time(evt):
            """Return a timezone-aware datetime for event start; fallback to max so None sorts last."""
            return _parse_google_datetime(evt.get("start", {})) or datetime.max.replace(tzinfo=timezone.utc)

        all_google_events.sort(key=_get_event_start_time)
        logger.debug(
            "Initial sync – events sorted chronologically (first=%s, last=%s)",
            _get_event_start_time(all_google_events[0]).isoformat() if all_google_events else "n/a",
            _get_event_start_time(all_google_events[-1]).isoformat() if all_google_events else "n/a",
        )

        # Process events: Map, Save Appointment, Process Attendees
        processed_count = 0
        pending_contacts_created_count = 0
        
        logger.critical(f"CRITICAL_LOG: Starting to process {len(all_google_events)} events")
        for event_data in all_google_events:
            logger.info(f"CRITICAL_LOG: Processing event ID: {event_data.get('id')}")
            # First get the existing appointment if it exists
            existing_appointment = None
            external_event_id = event_data.get('id')
            if external_event_id:
                existing_appointment = await appointment_repo.get_by_external_id(
                    user_id=user_id,
                    external_event_id=str(external_event_id)
                )
                
            appointment = await _map_google_event_to_appointment(
                event_data, 
                user_id, 
                connection_model,
                existing_appointment  # Pass existing appointment
            )
            logger.critical(f"CRITICAL_LOG: Appointment mapping result for {external_event_id}: {appointment is not None}")
            if appointment:
                logger.critical(f"CRITICAL_LOG: About to save appointment {appointment.external_id}")
                try:
                    # --- MODIFIED: Check if exists then add or update ---
                    if existing_appointment:
                        # Update existing appointment
                        # Ensure appointment.id is set to existing_appointment.id for update
                        appointment.id = existing_appointment.id
                        # Convert Pydantic model to dict for update, excluding fields not to be changed directly
                        # or that are managed by the repository (like id, created_on)
                        update_payload = appointment.model_dump(exclude={'id', 'user_id', 'created_on', 'source_created_on'}, exclude_none=True)
                        await appointment_repo.update(
                            user_id=user_id,
                            appointment_id=str(existing_appointment.id), # Ensure ID is string
                            update_data=update_payload
                        )
                    else:
                        # Add new appointment
                        # Ensure appointment.user_id is set correctly before adding
                        appointment.user_id = user_id
                        await appointment_repo.add(user_id=user_id, appointment=appointment)
                    processed_count += 1
                    logger.critical(f"CRITICAL_LOG: Appointment {appointment.external_id} saved successfully")
                    
                    # Process attendees for pending contacts
                    logger.critical(f"CRITICAL_LOG: About to process attendees for {appointment.external_id}")
                    attendees_processed = await _process_attendees_for_pending_contacts(
                        appointment=appointment, 
                        user_id=user_id, 
                        account_id=account_id,  # Pass the correct account_id
                        contact_repo=contact_repo, 
                        pending_contact_repo=pending_contact_repo, 
                        calendar_owner_email=connection_email
                    )
                    logger.critical(f"CRITICAL_LOG: Attendees processed for {appointment.external_id}: {attendees_processed}")
                    if attendees_processed:
                        pending_contacts_created_count +=1 # Rough count, function returns bool
                except Exception as e_proc:
                    logger.critical(f"CRITICAL_LOG: Error saving appointment: {e_proc}")
                    logger.error(f"Error saving appointment or processing attendees for event {appointment.external_id}: {e_proc}", exc_info=True)
                    # Continue processing other events
            else:
                 logger.warning(f"Failed to map Google Event ID: {event_data.get('id')} during initial sync for user {user_id}")

        # Store the final sync token after processing all events
        logger.critical(f"CRITICAL_LOG: All events processed. Final sync_token to store: {sync_token}")
        if sync_token:
            logger.critical(f"CRITICAL_LOG: Updating Firestore with sync_token: {sync_token}")
            await calendar_doc_ref.update({"google_sync_token": sync_token})
            logger.critical(f"CRITICAL_LOG: Firestore update with sync_token COMPLETED")
        else:
            logger.critical(f"CRITICAL_LOG: No final sync token to store!")
            logger.warning(f"No final sync token to store for {connection_email} after initial sync. Incremental sync may not work.") # MODIFIED LOG

        # Update sync status
        logger.critical(f"CRITICAL_LOG: Updating sync status in Firestore")
        await calendar_doc_ref.update({
            # Keep status as channel_active if watch was successful before sync
            "sync_status": connection_data.get("sync_status", "active"), 
            "sync_status_message": f"Initial sync completed. Processed {processed_count} events. {pending_contacts_created_count} pending contacts potentially created."
        })
        logger.critical(f"CRITICAL_LOG: Sync status update COMPLETED")
        logger.info(f"Initial sync completed for {connection_email}. Processed {processed_count} events.")
        return True

    except HttpError as error:
        logger.critical(f"CRITICAL_LOG: Google API HttpError: {error}")
        logger.error(f"Google API error during initial sync for {connection_email}: {error}", exc_info=True)
        await calendar_doc_ref.update({"sync_status": "error_other", "sync_status_message": f"Google API error during sync: {error.resp.status} - {str(error.content)[:100]}"})
        return False
    except Exception as e:
        logger.critical(f"CRITICAL_LOG: Unexpected error: {e}")
        logger.error(f"Unexpected error during initial sync for {connection_email}: {e}", exc_info=True)
        await calendar_doc_ref.update({"sync_status": "error_other", "sync_status_message": f"Unexpected error during sync: {str(e)}"})
        return False

async def perform_incremental_sync(
    user_id: str,
    connection_data: Dict[str, Any], # Pass data from Firestore as a dict
    db_client: AsyncClient,
    settings: Settings
) -> bool: # Returns True if successful, False if a full resync is needed or other error
    """Performs an incremental sync of Google Calendar events using a sync token."""
    # --- ADDED: Import Container inside function ---
    from assiist_back_end.containers import Container
    container = Container()
    appointment_repo: AppointmentRepository = container.appointment_repository()
    contact_repo: ContactRepository = container.contact_repository()
    pending_contact_repo: PendingContactRepository = container.pending_contact_repository()
    
    # Get account_id for proper contact scoping
    account_id = await _get_account_id_from_user_id(db_client, user_id)
    # --- END ADDED ---

    connection_email = connection_data.get('email')
    sync_token = connection_data.get('google_sync_token')

    if not connection_email:
        logger.error(f"Cannot perform incremental sync for user {user_id}: connection_data missing 'email'.")
        return False
        
    if not sync_token:
        logger.warning(f"No google_sync_token found for {connection_email} (User: {user_id}). A full sync might be required.")
        # Update status to indicate an issue, maybe trigger full sync later
        calendar_doc_ref_no_token = db_client.collection("users").document(user_id).collection("connected_calendars").document(connection_email)
        await calendar_doc_ref_no_token.update({
            "sync_status": "needs_full_resync", # Or a specific error state
            "sync_status_message": "Missing sync token for incremental sync. Full sync required."
        })
        return False # Indicate failure / need for full sync

    logger.info(f"Starting incremental sync for user {user_id}, email {connection_email} using sync token: {sync_token[:15]}...")

    creds = await get_valid_google_credentials(user_id, connection_data, db_client, settings)
    if not creds:
        logger.error(f"Failed to get valid credentials for {connection_email} (User: {user_id}). Cannot perform incremental sync.")
        return False

    calendar_doc_ref = db_client.collection("users").document(user_id).collection("connected_calendars").document(connection_email)
    
    try:
        connection_model = CalendarConnection(**connection_data)
    except Exception as e:
        logger.error(f"Failed to parse connection_data into CalendarConnection model for {connection_email} (Incremental Sync): {e}")
        await calendar_doc_ref.update({"sync_status": "error_other", "sync_status_message": "Failed to parse connection data during incremental sync."})
        return False

    try:
        service = build('calendar', 'v3', credentials=creds, static_discovery=False)
        page_token = None
        new_sync_token = sync_token # Start with the current sync token
        events_processed_count = 0
        events_deleted_count = 0

        # Accumulate events for chronological processing later
        all_incremental_events = []

        while True:
            logger.debug(f"Fetching events page with syncToken: {new_sync_token[:15]}... and pageToken: {page_token}")
            # Must use the same parameters as initial sync, just with syncToken instead of timeMin/timeMax
            events_result = service.events().list(
                calendarId='primary',
                syncToken=new_sync_token,
                maxResults=250,
                singleEvents=True,
                # NOTE: No orderBy parameter - sync tokens require default ordering
                showDeleted=True,   # Same as initial sync
                pageToken=page_token
            ).execute()

            current_page_events = events_result.get('items', [])
            logger.info(f"Fetched {len(current_page_events)} event items in incremental sync for {connection_email}.")

            # Accumulate events for chronological processing later
            all_incremental_events.extend(current_page_events)

            # Disable per-page processing; handle after pagination
            current_page_events = []

            for event_data in current_page_events:
                external_event_id = event_data.get('id')
                event_status = event_data.get('status')

                if event_status == 'cancelled':
                    logger.info(f"Event {external_event_id} cancelled. Generating cancellation note and deleting from local store for {connection_email}.")

                    # Fetch existing appointment (needed for note context)
                    existing_appointment = await appointment_repo.get_by_external_id(
                        user_id=user_id,
                        external_event_id=str(external_event_id)
                    )

                    # Fire cancellation auto-note for each linked contact before deletion
                    if existing_appointment and existing_appointment.assiist_contact_ids:
                        for c_id in existing_appointment.assiist_contact_ids:
                            try:
                                await _schedule_cancellation_note_for_contact(
                                    appointment=existing_appointment,
                                    contact_id=c_id,
                                    user_id=user_id,
                                    account_id=account_id,
                                )
                            except Exception as note_err:
                                logger.error(f"Failed to enqueue cancellation note for contact {c_id}: {note_err}")

                    try:
                        deleted_count = await appointment_repo.delete_by_external_id(user_id, connection_email, external_event_id)
                        if deleted_count > 0:
                            events_deleted_count += deleted_count
                            logger.info(f"Successfully deleted event {external_event_id} from local store.")
                        else:
                            logger.warning(f"Attempted to delete event {external_event_id} but it was not found in local store.")
                    except Exception as e_del:
                        logger.error(f"Error deleting event {external_event_id} from local store: {e_del}", exc_info=True)
                else:
                    # New or updated event
                    # First get the existing appointment if it exists
                    existing_appointment = None
                    if external_event_id:
                        existing_appointment = await appointment_repo.get_by_external_id(
                            user_id=user_id,
                            external_event_id=str(external_event_id)
                        )
                        
                    appointment = await _map_google_event_to_appointment(
                        event_data, 
                        user_id, 
                        connection_model,
                        existing_appointment  # Pass existing appointment
                    )
                    if appointment:
                        try:
                            # --- MODIFIED: Check if exists then add or update ---
                            if existing_appointment:
                                # Update existing appointment
                                appointment.id = existing_appointment.id
                                # ---------------------------------------------------------
                                # Detect *detail* changes (location / description)
                                # ---------------------------------------------------------
                                detail_changed = (
                                    (existing_appointment.location != appointment.location)
                                    or (existing_appointment.description != appointment.description)
                                ) and not appointment.is_rescheduled  # ignore if already rescheduled (handled separately)

                                if detail_changed and existing_appointment.assiist_contact_ids:
                                    for c_id in existing_appointment.assiist_contact_ids:
                                        try:
                                            await _schedule_update_note_for_contact(
                                                appointment=appointment,
                                                old_appointment=existing_appointment,
                                                contact_id=str(c_id),
                                                user_id=user_id,
                                                account_id=account_id,
                                            )
                                        except Exception as upd_exc:
                                            logger.error(
                                                f"Failed to enqueue update-note for contact {c_id}: {upd_exc}",
                                                exc_info=True,
                                            )
                                update_payload = appointment.model_dump(exclude={'id', 'user_id', 'created_on', 'source_created_on'}, exclude_none=True)
                                await appointment_repo.update(
                                    user_id=user_id,
                                    appointment_id=str(existing_appointment.id), # Ensure ID is string
                                    update_data=update_payload
                                )
                            else:
                                # Add new appointment
                                appointment.user_id = user_id
                                await appointment_repo.add(user_id=user_id, appointment=appointment)
                            events_processed_count += 1
                            # --- END MODIFICATION ---

                            # ---- Time-window filter for incremental sync ----
                            lookahead_days = int(settings.GOOGLE_CALENDAR_SYNC_DAYS_FUTURE)
                            now_utc = datetime.now(timezone.utc)
                            if (
                                appointment.start_time is None
                                or appointment.start_time < now_utc
                                or appointment.start_time > now_utc + timedelta(days=lookahead_days)
                            ):
                                # Skip processing attendees & auto-notes for events outside the window
                                continue

                            attendees_processed = await _process_attendees_for_pending_contacts(
                                appointment=appointment, 
                                user_id=user_id, 
                                account_id=account_id,  # Pass the correct account_id
                                contact_repo=contact_repo, 
                                pending_contact_repo=pending_contact_repo, 
                                calendar_owner_email=connection_email,
                                allow_auto_note=(existing_appointment is None or appointment.is_rescheduled),
                            )
                        except Exception as e_proc:
                            logger.error(f"Error saving or processing attendees for event {appointment.external_id} (incremental): {e_proc}", exc_info=True)
                    else:
                        logger.warning(f"Failed to map Google Event ID: {external_event_id} during incremental sync for user {user_id}")
            
            next_page_token = events_result.get('nextPageToken')
            # The new sync token is on the last page if nextPageToken is null
            # or on every page if not. Standard practice: always update if present.
            potential_new_sync_token = events_result.get('nextSyncToken')
            if potential_new_sync_token:
                new_sync_token = potential_new_sync_token 

            if not next_page_token:
                break # No more pages for this sync cycle
            
            page_token = next_page_token
        
        # ---- Sort & process collected events chronologically ----
        def _get_event_start_time(evt):
            return _parse_google_datetime(evt.get('start', {})) or datetime.max.replace(tzinfo=timezone.utc)

        all_incremental_events.sort(key=_get_event_start_time)
        logger.info(f"Processing {len(all_incremental_events)} incremental events in chronological order for {connection_email}.")

        for event_data in all_incremental_events:
            external_event_id = event_data.get('id')
            event_status = event_data.get('status')

            if event_status == 'cancelled':
                # --- Existing cancellation logic moved here ---
                try:
                    existing_appointment = await appointment_repo.get_by_external_id(user_id=user_id, external_event_id=str(external_event_id))
                except Exception:
                    existing_appointment = None

                if existing_appointment and existing_appointment.assiist_contact_ids:
                    for c_id in existing_appointment.assiist_contact_ids:
                        try:
                            await _schedule_cancellation_note_for_contact(appointment=existing_appointment, contact_id=c_id, user_id=user_id, account_id=account_id)
                        except Exception as note_err:
                            logger.error(f"Failed to enqueue cancellation note for contact {c_id}: {note_err}")

                try:
                    deleted_count = await appointment_repo.delete_by_external_id(user_id, connection_email, external_event_id)
                    if deleted_count:
                        events_deleted_count += deleted_count
                except Exception as e_del:
                    logger.error(f"Error deleting event {external_event_id}: {e_del}", exc_info=True)
                continue

            # ---- New or updated event ----
            existing_appointment = None
            if external_event_id:
                try:
                    existing_appointment = await appointment_repo.get_by_external_id(user_id=user_id, external_event_id=str(external_event_id))
                except Exception:
                    existing_appointment = None

            appointment = await _map_google_event_to_appointment(event_data, user_id, connection_model, existing_appointment)
            if not appointment:
                logger.warning(f"Failed to map Google Event ID: {external_event_id} during incremental sync for user {user_id}")
                continue

            try:
                if existing_appointment:
                    appointment.id = existing_appointment.id
                    detail_changed = ((existing_appointment.location != appointment.location) or (existing_appointment.description != appointment.description)) and not appointment.is_rescheduled
                    if detail_changed and existing_appointment.assiist_contact_ids:
                        for c_id in existing_appointment.assiist_contact_ids:
                            try:
                                await _schedule_update_note_for_contact(appointment=appointment, old_appointment=existing_appointment, contact_id=str(c_id), user_id=user_id, account_id=account_id)
                            except Exception as upd_exc:
                                logger.error(f"Failed to enqueue update-note for contact {c_id}: {upd_exc}", exc_info=True)

                    update_payload = appointment.model_dump(exclude={'id','user_id','created_on','source_created_on'}, exclude_none=True)
                    await appointment_repo.update(user_id=user_id, appointment_id=str(existing_appointment.id), update_data=update_payload)
                else:
                    appointment.user_id = user_id
                    await appointment_repo.add(user_id=user_id, appointment=appointment)

                events_processed_count += 1

                # Time-window filter
                lookahead_days = int(settings.GOOGLE_CALENDAR_SYNC_DAYS_FUTURE)
                now_utc = datetime.now(timezone.utc)
                if appointment.start_time is None or appointment.start_time < now_utc or appointment.start_time > now_utc + timedelta(days=lookahead_days):
                    continue

                await _process_attendees_for_pending_contacts(appointment=appointment, user_id=user_id, account_id=account_id, contact_repo=contact_repo, pending_contact_repo=pending_contact_repo, calendar_owner_email=connection_email, allow_auto_note=(existing_appointment is None or appointment.is_rescheduled))
            except Exception as e_proc:
                logger.error(f"Error saving/processing event {appointment.external_id}: {e_proc}", exc_info=True)

        # After loop & processing, store the very last new_sync_token obtained
        if new_sync_token != sync_token: # Only update if it changed
            await calendar_doc_ref.update({"google_sync_token": new_sync_token})
            logger.info(f"Stored new sync token for {connection_email}: {new_sync_token[:15]}...")
        
        await calendar_doc_ref.update({
            "sync_status_message": f"Incremental sync completed. {events_processed_count} events updated/added, {events_deleted_count} events deleted."
        })
        logger.info(f"Incremental sync completed for {connection_email}. {events_processed_count} events processed, {events_deleted_count} deleted.")
        return True

    except HttpError as error:
        if error.resp.status == 410: # Sync token is invalid
            logger.warning(f"Sync token for {connection_email} is invalid (410). Full sync required.", exc_info=True)
            # Per Google docs: "This should trigger a full wipe of the client's store and a new full sync"
            await calendar_doc_ref.update({
                "google_sync_token": None, # Clear invalid token
                "sync_status": "needs_full_resync",
                "sync_status_message": "Sync token invalid (410). Full sync required."
            })
            # Trigger immediate full sync by calling perform_initial_sync here
            logger.info(f"Initiating full sync after 410 error for {connection_email}")
            return False # Indicate failure / need for full sync
        else:
            logger.error(f"Google API error during incremental sync for {connection_email}: {error}", exc_info=True)
            await calendar_doc_ref.update({"sync_status": "error_other", "sync_status_message": f"Google API error during incremental sync: {error.resp.status} - {str(error.content)[:100]}"})
            return False
    except Exception as e:
        logger.error(f"Unexpected error during incremental sync for {connection_email}: {e}", exc_info=True)
        await calendar_doc_ref.update({"sync_status": "error_other", "sync_status_message": f"Unexpected error during incremental sync: {str(e)}"})
        return False

async def handle_webhook_notification(
    db_client: AsyncClient, 
    settings: Settings, 
    channel_id_from_header: str,
    resource_id_from_header: str,
    resource_state_from_header: str,
    # Optional: other X-Goog-* headers
) -> bool:
    logger.critical(f"Received Google webhook notification: Channel ID: {channel_id_from_header}, Resource ID: {resource_id_from_header}, State: {resource_state_from_header}")

    if not channel_id_from_header:
        logger.error("Webhook error: Missing X-Goog-Channel-ID header.")
        return False

    connections_ref = db_client.collection_group("connected_calendars") \
                        .where(filter=FieldFilter("google_channel_id", "==", channel_id_from_header))
    
    matching_connections = []
    async for doc_snapshot in connections_ref.stream():
        if doc_snapshot.exists:
            user_id = doc_snapshot.reference.parent.parent.id
            connection_data = doc_snapshot.to_dict()
            connection_data['user_id'] = user_id
            connection_data['email'] = doc_snapshot.id
            matching_connections.append(connection_data)
    
    if not matching_connections:
        # Orphan channel – try to find any connection that owns the same resourceId so we can stop it.
        orphan_cleaned = False
        try:
            res_q = db_client.collection_group("connected_calendars").where(
                filter=FieldFilter("google_resource_id", "==", resource_id_from_header)
            )
            async for conn_snap in res_q.stream():
                conn_user_id = conn_snap.reference.parent.parent.id
                conn_data = conn_snap.to_dict()
                conn_data.setdefault("email", conn_snap.id)
                # Use the *valid* connection's creds to stop the stray channel.
                creds_ok = await get_valid_google_credentials(conn_user_id, conn_data, db_client, settings)
                if creds_ok:
                    try:
                        svc = build("calendar", "v3", credentials=creds_ok, static_discovery=False)
                        svc.channels().stop(body={"id": channel_id_from_header, "resourceId": resource_id_from_header}).execute()
                        logger.info(
                            "Auto-stopped orphan Google channel %s using credentials of %s (user %s)",
                            channel_id_from_header,
                            conn_data["email"],
                            conn_user_id,
                        )
                        orphan_cleaned = True
                        break
                    except Exception as stop_e:
                        logger.warning("Failed to auto-stop orphan channel %s: %s", channel_id_from_header, stop_e)
        except Exception as search_e:
            logger.warning("Error attempting orphan-cleanup search: %s", search_e)

        if not orphan_cleaned:
            logger.error(
                "Webhook error: No active calendar connection found for channel ID %s. Notification ignored.",
                channel_id_from_header,
            )
        # Either way, we don't process further.
        return False

    if len(matching_connections) > 1:
        logger.error(f"Webhook error: Multiple connections found for channel ID {channel_id_from_header}. Ambiguous. Notification ignored.")
        return False

    connection_info = matching_connections[0]
    user_id = connection_info['user_id']
    connection_email = connection_info['email']

    logger.critical(f"Found matching connection for webhook: User {user_id}, Email {connection_email}")

    if connection_info.get("google_resource_id") != resource_id_from_header:
        logger.warning(f"Webhook warning: Mismatched resource_id for channel {channel_id_from_header}. Header: {resource_id_from_header}, Stored: {connection_info.get('google_resource_id')}. Processing anyway.")

    if resource_state_from_header in ["sync", "exists"]:
        logger.critical(f"Webhook: '{resource_state_from_header}' notification for {connection_email} (User: {user_id}). Enqueuing Google Cloud Task for incremental sync.")
        
        try:
            client = tasks_v2.CloudTasksClient()
            
            project = settings.GOOGLE_CLOUD_TASKS_PROJECT_ID
            location = settings.GOOGLE_CLOUD_TASKS_LOCATION
            queue = settings.GOOGLE_CLOUD_TASKS_QUEUE_ID
            task_handler_sa_email = settings.GOOGLE_CLOUD_TASKS_HANDLER_SA_EMAIL
            # api_base_url = settings.API_URL # OLD WAY - directly using API_URL

            if not all([project, location, queue, task_handler_sa_email, settings.GOOGLE_CALENDAR_WEBHOOK_URL]): # Ensure webhook URL is also checked
                logger.critical("Google Cloud Tasks settings (PROJECT_ID, LOCATION, QUEUE_ID, HANDLER_SA_EMAIL, GOOGLE_CALENDAR_WEBHOOK_URL) are not fully configured. Cannot enqueue task.")
                # Update Firestore status to indicate a system-level problem
                cal_doc_ref = db_client.collection("users").document(user_id).collection("connected_calendars").document(connection_email)
                await cal_doc_ref.update({"sync_status": "error_system", "sync_status_message": "Webhook processor error: Cloud Tasks not configured."})
                return False

            parent_queue = client.queue_path(project, location, queue)
            
            # Construct the full URL for the task handler
            task_handler_path = "/internal/tasks/google-calendar-incremental-sync" 

            # --- NEW WAY to construct handler_url for tasks using GOOGLE_CALENDAR_WEBHOOK_URL base ---
            if not settings.GOOGLE_CALENDAR_WEBHOOK_URL:
                logger.critical("GOOGLE_CALENDAR_WEBHOOK_URL is not set, cannot determine HTTPS base for task handler.")
                # Update Firestore status to indicate a system-level problem
                cal_doc_ref = db_client.collection("users").document(user_id).collection("connected_calendars").document(connection_email)
                await cal_doc_ref.update({"sync_status": "error_system", "sync_status_message": "Webhook processor error: Task handler URL misconfiguration."})
                return False

            webhook_url_parsed = urlparse(settings.GOOGLE_CALENDAR_WEBHOOK_URL)
            task_base_url = urlunparse((webhook_url_parsed.scheme, webhook_url_parsed.netloc, '', '', '', ''))
            handler_url = f"{task_base_url.rstrip('/')}{task_handler_path}"
            logger.info(f"Constructed task handler URL: {handler_url}") # Added log
            # --- END NEW WAY ---

            payload = GoogleCalendarSyncPayload(
                user_id=user_id,
                connection_email=connection_email,
                channel_id=channel_id_from_header, # Pass channel_id as per original Celery task
                user_timezone=connection_data.get('user_timezone', "UTC")
            )
            
            task_to_create = {
                "http_request": {
                    "http_method": tasks_v2.HttpMethod.POST,
                    "url": handler_url,
                    "headers": {"Content-type": "application/json"},
                    "body": json.dumps(payload.model_dump()).encode(), # Encode to bytes
                    "oidc_token": {
                        "service_account_email": task_handler_sa_email,
                        # "audience" can be specified if your handler validates it, often it's the URL itself.
                        # If your Cloud Run service has a custom audience set, specify it here.
                        # By default, for Cloud Run, the audience is the URL of the service being called.
                    },
                }
            }

            # Create the task
            response = client.create_task(request={"parent": parent_queue, "task": task_to_create})
            logger.info(f"Successfully enqueued Google Cloud Task: {response.name} for {connection_email}")
            return True

        except Exception as e_enqueue:
            logger.error(f"Webhook error: Failed to enqueue Google Cloud Task for {connection_email}: {e_enqueue}", exc_info=True)
            cal_doc_ref = db_client.collection("users").document(user_id).collection("connected_calendars").document(connection_email)
            await cal_doc_ref.update({"sync_status": "error_system", "sync_status_message": f"Failed to enqueue sync task: {str(e_enqueue)[:100]}"})
            return False

    elif resource_state_from_header == "exists":
        logger.info(f"Webhook: 'exists' notification for {connection_email} (User: {user_id}). Channel confirmed active.")
        # Optionally update last_verified_time or similar if needed.
        return True 
        
    elif resource_state_from_header == "not_exists":
        logger.warning(f"Webhook: 'not_exists' notification for {connection_email} (User: {user_id}). Channel is no longer valid.")
        # Channel might have expired, been stopped by user, or access revoked.
        # Mark as needing re-watch or full sync. The periodic check_google_channels task should handle renewal.
        cal_doc_ref = db_client.collection("users").document(user_id).collection("connected_calendars").document(connection_email)
        await cal_doc_ref.update({
            "google_channel_id": None,
            "google_resource_id": None,
            # Don't clear expiration here, as it might be useful for the renewal task to know when it *was* supposed to expire.
            "sync_status": "needs_rewatch", # A new status to indicate the channel needs to be re-established
            "sync_status_message": "Webhook reported channel 'not_exists'. Needs rewatch."
        })
        return True
        
    else:
        logger.warning(f"Webhook: Unknown resource_state '{resource_state_from_header}' for {connection_email}. Notification ignored.")
        return True # Acknowledge receipt, but don't process unknown states

# Placeholder: Actual Celery task definition will be in tasks.py
# @celery_app.task
# async def process_google_calendar_update(user_id: str, connection_email: str, channel_id: str):
# logger.info(f"Celery task 'process_google_calendar_update' received for user {user_id}, email {connection_email}")
# container = Container()
# service = container.google_calendar_service() # This assumes service is registered in DI
# db_client = container.firestore_async_client()
# appointment_repo = container.appointment_repository()
# contact_repo = container.contact_repository()
# pending_contact_repo = container.pending_contact_repository()
# 
# # Fetch full connection_data for the service function
# doc_ref = db_client.collection("users").document(user_id).collection("connected_calendars").document(connection_email)
# connection_doc = await doc_ref.get()
# if connection_doc.exists:
# connection_data = connection_doc.to_dict()
# await service.perform_incremental_sync(user_id, connection_data, db_client, container.settings(), appointment_repo, contact_repo, pending_contact_repo)
# else:
# logger.error(f"Celery task: Could not find connection for {user_id}, {connection_email}")

# --- Placeholder for other service functions ---
# async def handle_webhook_notification(...) 

# --- FREE/BUSY API METHODS ---

async def get_freebusy_for_calendars(
    user_id: str,
    db_client: AsyncClient,
    settings: Settings,
    time_min: datetime,
    time_max: datetime,
    calendars: Optional[List[str]] = None
) -> Dict[str, Any]:
    """
    Get free/busy information across connected Google calendars for a user.
    
    Args:
        user_id: User ID
        db_client: Firestore client
        settings: App settings
        time_min: Start time for free/busy query
        time_max: End time for free/busy query
        calendars: Optional list of calendar emails to query (defaults to all connected)
    
    Returns:
        Dict with availability data structure
    """
    print(f"🏁 START: get_freebusy_for_calendars for user {user_id}")
    
    try:
        # Get all connected Google calendars if none specified
        if calendars is None:
            print(f"🔍 STEP 1: Querying connected calendars...")
            # Use the same simple pattern as calendar_connections.py that already works
            # Create a new client with explicit database like calendar_connections.py does
            working_db = None
            calendars = []
            
            try:
                working_db = AsyncClient(database="assiist-app")
                col_ref = working_db.collection("users").document(user_id).collection("connected_calendars")
                
                # Use stream() like the working calendar_connections endpoint
                all_docs = [doc async for doc in col_ref.stream()]
                
                # Filter for Google calendars in Python instead of complex Firestore query
                google_calendars = []
                for doc in all_docs:
                    doc_data = doc.to_dict()
                    if doc_data.get("provider") == "google":
                        google_calendars.append(doc.id)  # doc.id is the email
                
                calendars = google_calendars
                print(f"📅 STEP 1 RESULT: Found {len(google_calendars)} Google calendars out of {len(all_docs)} total calendars")
                
            except Exception as e:
                print(f"❌ FIRESTORE ERROR: {e}")
                logger.error(f"Firestore connected calendars query failed for user {user_id}: {e}")
                calendars = []
            finally:
                # Clean up the database client
                if working_db and hasattr(working_db, 'close'):
                    try:
                        # Some versions of the Firestore AsyncClient expose an async close()
                        # while others expose a synchronous close() that returns None. Handle
                        # both cases gracefully to avoid "object NoneType can't be used in
                        # 'await' expression" errors seen in production logs.
                        maybe_coroutine = working_db.close()
                        if asyncio.iscoroutine(maybe_coroutine):
                            await maybe_coroutine
                    except Exception as cleanup_error:
                        print(f"⚠️ Error closing database client: {cleanup_error}")
                
            if not calendars:
                return {"calendars": {}, "timeMin": time_min.isoformat(), "timeMax": time_max.isoformat()}
        
        print(f"🔍 STEP 2: Getting connection doc for calendar {calendars[0]}...")
        # Get credentials for first available calendar (they should all be the same user)
        connection_doc = await (db_client.collection("users")
                               .document(user_id)
                               .collection("connected_calendars")
                               .document(calendars[0])
                               .get())
        
        if not connection_doc.exists:
            print(f"❌ Calendar connection not found for {calendars[0]}")
            logger.error(f"Calendar connection not found for {calendars[0]}")
            return {"calendars": {}, "timeMin": time_min.isoformat(), "timeMax": time_max.isoformat()}
        
        print(f"🔍 STEP 3: Getting valid Google credentials...")
        connection_data = connection_doc.to_dict()
        creds = await get_valid_google_credentials(user_id, connection_data, db_client, settings)
        
        if not creds:
            print(f"❌ Failed to get valid credentials for free/busy query")
            logger.error(f"Failed to get valid credentials for free/busy query")
            return {"calendars": {}, "timeMin": time_min.isoformat(), "timeMax": time_max.isoformat()}
        
        print(f"🔍 STEP 4: Building Google Calendar service...")
        # Build Google Calendar service
        service = build('calendar', 'v3', credentials=creds, static_discovery=False)
        
        print(f"🔍 STEP 5a: Using connected calendars for availability...")
        # Only use the calendars that are explicitly connected in our system
        all_calendar_ids = calendars if calendars else ["primary"]
        print(f"📅 Using calendars ({len(all_calendar_ids)}):")
        for cal_id in all_calendar_ids:
            print(f"  - ID: {cal_id}")
            print(f"    ✅ Including in availability check")
        
        # Prepare free/busy request according to Google Calendar API documentation
        # https://developers.google.com/calendar/api/v3/reference/freebusy/query
        
        # Ensure we don't exceed calendarExpansionMax (50 calendars max per API docs)
        if len(all_calendar_ids) > 50:
            print(f"⚠️ Too many calendars ({len(all_calendar_ids)}), limiting to first 50 as per API limits")
            all_calendar_ids = all_calendar_ids[:50]
        
        # Format times as RFC3339 with timezone
        time_min_rfc3339 = time_min.isoformat() + 'Z' if time_min.tzinfo is None else time_min.isoformat()
        time_max_rfc3339 = time_max.isoformat() + 'Z' if time_max.tzinfo is None else time_max.isoformat()
        
        # Get device timezone using Python's built-in functionality
        device_timezone = str(datetime.now().astimezone().tzinfo)
        print(f"📅 Using device timezone: {device_timezone}")
        
        # Construct request body according to API documentation
        freebusy_request = {
            "timeMin": time_min_rfc3339,
            "timeMax": time_max_rfc3339,
            "timeZone": device_timezone,  # Use device timezone
            "items": [{"id": cal_id} for cal_id in all_calendar_ids],
            "calendarExpansionMax": 50  # Maximum allowed by API
        }
        
        print(f"🔍 STEP 5b: About to call Google Calendar FreeBusy API...")
        print(f"  📅 Checking {len(all_calendar_ids)} calendars: {all_calendar_ids}")
        print(f"  🕐 Time range: {time_min.isoformat()} to {time_max.isoformat()}")
        print(f"  📋 Request body: {freebusy_request}")
        logger.info(f"📅 DEBUG → Calling Google Calendar FreeBusy API for {len(all_calendar_ids)} calendars: {all_calendar_ids}")
        logger.info(f"📅 DEBUG → Time range: {time_min.isoformat()} to {time_max.isoformat()}")
        
        # Run the synchronous Google API call in a thread pool with timeout to avoid blocking
        def execute_freebusy_request():
            print(f"🔥 EXECUTING: Google FreeBusy API call...")
            result = service.freebusy().query(body=freebusy_request).execute()
            print(f"✅ API CALL COMPLETE: Got response")
            return result
        
        print(f"🚀 CALLING: asyncio.wait_for with 30 second timeout...")
        # Use asyncio.wait_for with timeout to prevent hanging
        freebusy_response = await asyncio.wait_for(
            asyncio.to_thread(execute_freebusy_request),
            timeout=30.0  # 30 second timeout
        )
        
        print(f"✅ SUCCESS: FreeBusy API response received!")
        
        # Process response according to API documentation structure
        calendars_data = freebusy_response.get("calendars", {})
        groups_data = freebusy_response.get("groups", {})
        
        # Track successful and failed calendars
        successful_calendars = []
        failed_calendars = []
        total_busy_periods = 0
        
        # Process individual calendar results
        for cal_id, cal_data in calendars_data.items():
            # Check for errors
            if cal_data.get("errors"):
                error_info = cal_data["errors"][0]  # Get first error
                error_reason = error_info.get("reason", "unknown")
                print(f"  ❌ Calendar {cal_id} error: {error_reason}")
                failed_calendars.append({"id": cal_id, "error": error_reason})
                continue
            
            # Process busy periods
            busy_periods = cal_data.get("busy", [])
            total_busy_periods += len(busy_periods)
            successful_calendars.append(cal_id)
            print(f"  📅 {cal_id}: {len(busy_periods)} busy periods")
        
        # Process any group expansions
        for group_id, group_data in groups_data.items():
            if group_data.get("errors"):
                error_info = group_data["errors"][0]
                print(f"  ❌ Group {group_id} error: {error_info.get('reason', 'unknown')}")
            else:
                print(f"  👥 Group {group_id}: {len(group_data.get('calendars', []))} calendars")
        
        print(f"📊 Results Summary:")
        print(f"   • Successful calendars: {len(successful_calendars)}")
        print(f"   • Failed calendars: {len(failed_calendars)}")
        print(f"   • Total busy periods: {total_busy_periods}")
        
        logger.info(f"📅 DEBUG → FreeBusy API response processed: {len(successful_calendars)} successful, {len(failed_calendars)} failed, {total_busy_periods} busy periods")
        
        # Return complete response for proper error handling upstream
        return {
            "kind": freebusy_response.get("kind"),
            "timeMin": freebusy_response.get("timeMin"),
            "timeMax": freebusy_response.get("timeMax"),
            "calendars": calendars_data,
            "groups": groups_data,
            # Add our processed summary for convenience
            "summary": {
                "successful_calendars": successful_calendars,
                "failed_calendars": failed_calendars,
                "total_busy_periods": total_busy_periods
            }
        }
        
    except asyncio.TimeoutError:
        print(f"⏰ TIMEOUT: Google Calendar API took longer than 30 seconds for user {user_id}")
        logger.error(f"Timeout getting free/busy data for user {user_id} - Google Calendar API took too long")
        # Return error response matching API format
        return {
            "kind": "calendar#freeBusy",
            "timeMin": time_min_rfc3339,
            "timeMax": time_max_rfc3339,
            "calendars": {
                cal_id: {
                    "errors": [{
                        "domain": "global",
                        "reason": "timeoutError",
                        "message": "API request timed out after 30 seconds"
                    }]
                } for cal_id in all_calendar_ids
            },
            "summary": {
                "successful_calendars": [],
                "failed_calendars": [{"id": cal_id, "error": "timeoutError"} for cal_id in all_calendar_ids],
                "total_busy_periods": 0
            }
        }
    except HttpError as e:
        print(f"❌ Google Calendar API Error: {e.resp.status} - {e.content}")
        logger.error(f"Google Calendar API error: {e}", exc_info=True)
        # Return error response matching API format
        return {
            "kind": "calendar#freeBusy",
            "timeMin": time_min_rfc3339,
            "timeMax": time_max_rfc3339,
            "calendars": {
                cal_id: {
                    "errors": [{
                        "domain": "global",
                        "reason": f"httpError{e.resp.status}",
                        "message": str(e.content)[:100]
                    }]
                } for cal_id in all_calendar_ids
            },
            "summary": {
                "successful_calendars": [],
                "failed_calendars": [{"id": cal_id, "error": f"httpError{e.resp.status}"} for cal_id in all_calendar_ids],
                "total_busy_periods": 0
            }
        }
    except Exception as e:
        print(f"❌ ERROR: Unexpected exception in get_freebusy_for_calendars: {e}")
        logger.error(f"Unexpected error getting free/busy data: {e}", exc_info=True)
        import traceback
        traceback.print_exc()
        # Return error response matching API format
        return {
            "kind": "calendar#freeBusy",
            "timeMin": time_min_rfc3339,
            "timeMax": time_max_rfc3339,
            "calendars": {
                cal_id: {
                    "errors": [{
                        "domain": "global",
                        "reason": "internalError",
                        "message": str(e)[:100]
                    }]
                } for cal_id in all_calendar_ids
            },
            "summary": {
                "successful_calendars": [],
                "failed_calendars": [{"id": cal_id, "error": "internalError"} for cal_id in all_calendar_ids],
                "total_busy_periods": 0
            }
        }

async def format_availability_for_ai(freebusy_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Format Google Free/Busy response for AI context.
    
    Args:
        freebusy_data: Raw Google Free/Busy API response
    
    Returns:
        Formatted availability data for AI
    """
    try:
        calendars = freebusy_data.get("calendars", {})
        time_min = freebusy_data.get("timeMin", "")
        time_max = freebusy_data.get("timeMax", "")
        
        logger.info(f"📅 DEBUG → Formatting availability: {len(calendars)} calendars, time range {time_min} to {time_max}")
        
        # Combine all busy periods from all calendars
        all_busy_periods = []
        
        for calendar_email, calendar_data in calendars.items():
            busy_periods = calendar_data.get("busy", [])
            logger.info(f"📅 DEBUG → Calendar {calendar_email}: {len(busy_periods)} busy periods")
            for period in busy_periods:
                all_busy_periods.append({
                    "start": period.get("start"),
                    "end": period.get("end"),
                    "calendar": calendar_email
                })
        
        # Sort by start time
        all_busy_periods.sort(key=lambda x: x["start"])
        logger.info(f"📅 DEBUG → Total combined busy periods: {len(all_busy_periods)}")
        
        return {
            "time_range": {
                "start": time_min,
                "end": time_max
            },
            "busy_periods": all_busy_periods,
            "calendars_checked": list(calendars.keys()),
            "total_busy_periods": len(all_busy_periods)
        }
        
    except Exception as e:
        logger.error(f"Error formatting availability data: {e}")
        return {
            "time_range": {"start": "", "end": ""},
            "busy_periods": [],
            "calendars_checked": [],
            "total_busy_periods": 0
        } 

# ---------------------------------------------------------------------------
# Helper: Schedule Auto-Note via Internal API
# ---------------------------------------------------------------------------
async def _schedule_auto_note_for_contact(
    appointment: Appointment,
    contact_id: str,
    user_id: str,
    account_id: str,
):
    """Post a system note to the internal Update-Assistant endpoint.

    Guards:  
    • appointment.start_time must be in the future  
    • 1 ≤ non-owner attendees ≤ 2 (already satisfied by caller)
    """

    from datetime import datetime, timezone
    import aiohttp
    import os
    from urllib.parse import urljoin
    from assiist_back_end.config import Settings as _S
    api_base = getattr(_S(), "API_URL", None) or f"https://{os.environ.get('GCP_PROJECT', 'assiist-app')}.cloudfunctions.net"

    now = datetime.now(timezone.utc)
    if not appointment.start_time or appointment.start_time <= now:
        return  # Past event – ignore

    # Build note template
    from assiist_back_end.services.appointment_note_templates import build_new_appointment_note
    note_body = build_new_appointment_note(appointment, [contact_id])

    api_url = urljoin(api_base, "/api/v1/assistant/update-assistant")

    headers = {
        "Content-Type": "application/json",
        "X-Internal-API-Key": os.environ.get("ASSIIST_API_KEY", ""),
    }

    # ------------------------------------------------------------------
    # Idempotency guard – skip if a genai_request already exists for this
    # contact / appointment pair (any of the three Update-Assistant requests).
    # ------------------------------------------------------------------
    try:
        db = Container().firestore_async_client()
        coll = db.collection("genai_requests")

        query = (
            coll.where(filter=FieldFilter("contact_id", "==", contact_id))
                .where(filter=FieldFilter("appointment_id", "==", str(appointment.id)))
                .limit(1)
        )

        async for _ in query.stream():
            # Found at least one existing request → skip
            return
    except Exception as idem_exc:
        # If guard fails for any reason, log and proceed (better to duplicate than miss)
        logging.warning("Idempotency check failed: %s", idem_exc)

    payload = {
        "contact_id": contact_id,
        "appointment_id": str(appointment.id),
        "source_event_id": appointment.external_id,
        "event_type": "new",
        "note_content": note_body,
        "note_type": "system",
        "user_id": user_id,
        "account_id": account_id,
        "user_timezone": "UTC",
    }

    # TODO: Add idempotency check if duplicate requests become an issue

    async with aiohttp.ClientSession() as session:
        async with session.post(api_url, json=payload, headers=headers, timeout=30) as resp:
            if resp.status != 202:
                text = await resp.text()
                raise Exception(f"Internal API returned {resp.status}: {text}")

    # Optionally store processed_on on appointment? Caller manages. 

# ---------------------------------------------------------------------------
# Helper: Schedule Cancellation Auto-Note via Internal API
# ---------------------------------------------------------------------------
async def _schedule_cancellation_note_for_contact(
    appointment: Appointment,
    contact_id: str,
    user_id: str,
    account_id: str,
):
    """Post a system note for a cancelled appointment via Update-Assistant."""

    import aiohttp, os
    from urllib.parse import urljoin
    from assiist_back_end.config import Settings as _S
    from assiist_back_end.services.appointment_note_templates import build_cancellation_note

    api_base = getattr(_S(), "API_URL", None) or f"https://{os.environ.get('GCP_PROJECT', 'assiist-app')}.cloudfunctions.net"

    note_body = build_cancellation_note(appointment, [contact_id])

    api_url = urljoin(api_base, "/api/v1/assistant/update-assistant")
    headers = {
        "Content-Type": "application/json",
        "X-Internal-API-Key": os.environ.get("ASSIIST_API_KEY", ""),
    }

    # Idempotency: prevent duplicate cancellation notes.
    try:
        db = Container().firestore_async_client()
        coll = db.collection("genai_requests")
        query = (
            coll.where(filter=FieldFilter("contact_id", "==", contact_id))
                .where(filter=FieldFilter("appointment_id", "==", str(appointment.id)))
                .where(filter=FieldFilter("event_type", "==", "cancel"))
                .limit(1)
        )
        async for _ in query.stream():
            return  # already exists
    except Exception as idem_exc:
        logging.warning("Cancellation idempotency check failed: %s", idem_exc)

    payload = {
        "contact_id": contact_id,
        "appointment_id": str(appointment.id),
        "source_event_id": appointment.external_id,
        "event_type": "cancel",
        "note_content": note_body,
        "note_type": "system",
        "user_id": user_id,
        "account_id": account_id,
        "user_timezone": "UTC",
    }

    async with aiohttp.ClientSession() as session:
        async with session.post(api_url, json=payload, headers=headers, timeout=30) as resp:
            if resp.status != 202:
                text = await resp.text()
                raise Exception(f"Internal API returned {resp.status}: {text}")

    # Optionally store processed_on on appointment? Caller manages. 

# ---------------------------------------------------------------------------
# Helper: Schedule Update Auto-Note via Internal API
# ---------------------------------------------------------------------------
async def _schedule_update_note_for_contact(
    appointment: Appointment,
    old_appointment: Appointment,
    contact_id: str,
    user_id: str,
    account_id: str,
):
    """Send auto-note for updated details (location/description)."""

    import aiohttp, os
    from urllib.parse import urljoin
    from assiist_back_end.config import Settings as _S
    from assiist_back_end.services.appointment_note_templates import build_update_note

    api_base = getattr(_S(), "API_URL", None) or f"https://{os.environ.get('GCP_PROJECT', 'assiist-app')}.cloudfunctions.net"

    note_body = build_update_note(appointment, old_appointment, [contact_id])

    api_url = urljoin(api_base, "/api/v1/assistant/update-assistant")
    headers = {
        "Content-Type": "application/json",
        "X-Internal-API-Key": os.environ.get("ASSIIST_API_KEY", ""),
    }

    # Idempotency check based on appointment_id + event_type=update
    try:
        db = Container().firestore_async_client()
        coll = db.collection("genai_requests")
        query = (
            coll.where(filter=FieldFilter("contact_id", "==", contact_id))
                .where(filter=FieldFilter("appointment_id", "==", str(appointment.id)))
                .where(filter=FieldFilter("event_type", "==", "update"))
                .limit(1)
        )
        async for _ in query.stream():
            return
    except Exception as idem_exc:
        logging.warning("Update-note idempotency check failed: %s", idem_exc)

    payload = {
        "contact_id": contact_id,
        "appointment_id": str(appointment.id),
        "source_event_id": appointment.external_id,
        "event_type": "update",
        "note_content": note_body,
        "note_type": "system",
        "user_id": user_id,
        "account_id": account_id,
        "user_timezone": "UTC",
    }

    async with aiohttp.ClientSession() as session:
        async with session.post(api_url, json=payload, headers=headers, timeout=30) as resp:
            if resp.status != 202:
                text = await resp.text()
                raise Exception(f"Internal API returned {resp.status}: {text}")

    # Optionally store processed_on on appointment? Caller manages. 

# ---------------------------------------------------------------------------
# Helper: Schedule Reschedule Auto-Note via Internal API
# ---------------------------------------------------------------------------
async def _schedule_reschedule_note_for_contact(
    appointment: Appointment,
    contact_id: str,
    user_id: str,
    account_id: str,
):
    """Post a system note for a rescheduled appointment via Update-Assistant."""

    import aiohttp, os
    from urllib.parse import urljoin
    from assiist_back_end.config import Settings as _S
    from assiist_back_end.services.appointment_note_templates import build_reschedule_note
    from assiist_back_end.containers import Container  # Local import to access Firestore client

    api_base = getattr(_S(), "API_URL", None) or f"https://{os.environ.get('GCP_PROJECT', 'assiist-app')}.cloudfunctions.net"

    note_body = build_reschedule_note(appointment, [contact_id])

    api_url = urljoin(api_base, "/api/v1/assistant/update-assistant")
    headers = {
        "Content-Type": "application/json",
        "X-Internal-API-Key": os.environ.get("ASSIIST_API_KEY", ""),
    }

    # Idempotency: only *one* reschedule note per (appointment × new_start_time)
    start_iso: str | None = None
    if appointment.start_time:
        try:
            # Normalise to ISO w/ seconds-precision to avoid millisecond drift false-positives
            start_iso = appointment.start_time.replace(microsecond=0).isoformat()
        except Exception:
            start_iso = str(appointment.start_time)

    try:
        db = Container().firestore_async_client()
        coll = db.collection("genai_requests")

        q = (
            coll.where(filter=FieldFilter("contact_id", "==", contact_id))
               .where(filter=FieldFilter("appointment_id", "==", str(appointment.id)))
               .where(filter=FieldFilter("event_type", "==", "reschedule"))
        )

        if start_iso:
            q = q.where(filter=FieldFilter("appointment_start_time", "==", start_iso))

        q = q.limit(1)

        async for _ in q.stream():
            return  # identical reschedule already queued
    except Exception as idem_exc:
        logging.warning("Reschedule idempotency check failed: %s", idem_exc)

    payload = {
        "contact_id": contact_id,
        "appointment_id": str(appointment.id),
        "source_event_id": appointment.external_id,
        "event_type": "reschedule",
        "note_content": note_body,
        "note_type": "system",
        "user_id": user_id,
        "account_id": account_id,
        "user_timezone": "UTC",
        "appointment_start_time": start_iso,
    }

    async with aiohttp.ClientSession() as session:
        async with session.post(api_url, json=payload, headers=headers, timeout=30) as resp:
            if resp.status != 202:
                text = await resp.text()
                raise Exception(f"Internal API returned {resp.status}: {text}")

    # Optionally store processed_on on appointment? Caller manages.