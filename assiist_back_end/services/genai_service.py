import logging
from typing import List, Dict, Any, Optional
from google.cloud.firestore_v1.async_client import AsyncClient
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from datetime import datetime, timedelta, timezone
import asyncio
from assiist_back_end.utils.time import utc_now

logger = logging.getLogger(__name__)

# Essential fields for AI operations (token optimization)
NOTE_ESSENTIAL_FIELDS = ["id", "raw_note", "created_on"]
TASK_ESSENTIAL_FIELDS = ["id", "title", "body", "status", "type", "actionable_date", "due_date", "completed_on"]
APPOINTMENT_ESSENTIAL_FIELDS = [
    "id", "title", "description", "start_time", "end_time", "location", 
    "status", "is_rescheduled", "original_start_time", "original_end_time", "reschedule_reason"
]

class GenAIUtilities:
    """Utility class for GenAI functions to retrieve and format user data consistently with basic and full context levels."""
    
    def __init__(self, db: AsyncClient):
        self.db = db
    
    async def get_basic_context(self, user_id: str, contact_id: str, account_id: str) -> Dict[str, Any]:
        """
        Get basic context for simple AI operations (quick draft, basic revision).
        
        Args:
            user_id (str): The user ID
            contact_id (str): The contact ID
            account_id (str): Account ID
            
        Returns:
            Dict containing basic context data
        """
        # Get the current datetime in the user's local timezone
        current_datetime = datetime.now().strftime('%A, %B %d, %Y at %I:%M %p')
        
        context = {
            "user_id": user_id,
            "contact_id": str(contact_id),
            "account_id": account_id,
            "current_datetime": current_datetime,  # User's current local datetime
            "user_first_name": "",
            "user_last_name": "",
            "business_name": "",
            "business_type": "",
            "business_description": "",
            "language_examples": "",
            "contact_name": "Contact",
            "contact_phone": "",
            "addressed_as": ""
        }
        
        try:
            logger.info(f"⚙️ DEBUG → Getting basic context for user {user_id}, contact {contact_id}, account {account_id}")
            
            # Get user data
            user_ref = self.db.collection("users").document(user_id)
            user_doc = await user_ref.get()
            
            if user_doc.exists:
                user_data = user_doc.to_dict()
                context["user_first_name"] = user_data.get("first_name", "").strip()
                context["user_last_name"] = user_data.get("last_name", "").strip()
            
            # Get account data
            account_ref = self.db.collection("accounts").document(account_id)
            account_doc = await account_ref.get()
            
            if account_doc.exists:
                account_data = account_doc.to_dict()
                context["business_name"] = account_data.get("account_name", "").strip()
                context["business_type"] = account_data.get("business_type", "").strip()
                context["business_description"] = account_data.get("business_description", "").strip()
            
            # Get contact data
            contact_ref = self.db.collection("contacts").document(str(contact_id))
            contact_doc = await contact_ref.get()
            
            if contact_doc.exists:
                contact_data = contact_doc.to_dict()
                
                # Extract contact phone number
                phone_numbers = contact_data.get("phone_numbers", [])
                if phone_numbers and len(phone_numbers) > 0:
                    context["contact_phone"] = phone_numbers[0].get("number", "")
                
                # Extract addressed_as field (how they prefer to be addressed)
                addressed_as = contact_data.get("addressed_as", "")
                context["addressed_as"] = addressed_as
                
                # Extract contact_name from actual name fields
                first_name = contact_data.get("first_name", "")
                last_name = contact_data.get("last_name", "")
                
                if first_name and last_name:
                    context["contact_name"] = f"{first_name} {last_name}"
                elif first_name:
                    context["contact_name"] = first_name
                # If no personal name available, keep default "Contact"
            
            # Get language examples
            context["language_examples"] = await self.get_user_language_examples(user_id)
            
            # Provide minimal fallbacks for required fields
            if not context.get("contact_phone"):
                context["contact_phone"] = "No phone number available"
            if not context.get("user_first_name"):
                context["user_first_name"] = "User"
            if not context.get("business_name"):
                context["business_name"] = "Business"
            if not context.get("business_type"):
                context["business_type"] = "Service Provider"
            
            return context
            
        except Exception as e:
            logger.error(f"Error getting basic context: {e}")
            return context
    
    async def get_full_context(
        self, 
        user_id: str, 
        contact_id: str, 
        account_id: str,
        past_limit_days: int = 30,
        future_limit_days: int = 30
    ) -> Dict[str, Any]:
        """
        Get comprehensive context for a user and contact.
        Optimized for task creation and complex AI operations.
        Includes filtered appointments and availability data.
        """
        try:
            logger.info(f"🌍 DEBUG → Starting full context gathering for user {user_id}, contact {contact_id}")
            
            # Get contact details first, as we need the email for appointments
            contact_details = await self._get_contact_details(contact_id, account_id)
            logger.info(f"🌍 DEBUG → Contact details keys: {list(contact_details.keys()) if contact_details else 'None'}")
            
            contact_emails = self._extract_emails_from_contact_data(contact_details)
            primary_email = contact_details.get("email") if contact_details else None
            
            # If no top-level email but we have emails in the array, use the first one as primary
            if not primary_email and contact_emails:
                primary_email = contact_emails[0]
                logger.info(f"🌍 DEBUG → No top-level email, using first extracted email as primary: {primary_email}")

            logger.info(f"🌍 DEBUG → Contact details: emails={contact_emails}, primary_email={primary_email}")

            # Run all other queries in parallel
            data = await asyncio.gather(
                self.get_basic_context(user_id, contact_id, account_id),
                self._get_notes(contact_id, account_id, past_limit_days),
                self._get_tasks(contact_id, account_id, past_limit_days),
                self._get_appointments(user_id, contact_emails, past_limit_days, future_limit_days, contact_id),
                self._get_availability(user_id, future_limit_days),
                return_exceptions=True
            )
            
            # Handle parallel operation results with better error handling
            if isinstance(data[0], Exception):
                logger.error(f"🌍 ERROR → Basic context failed: {data[0]}")
                basic_context = {}
            else:
                basic_context = data[0] or {}
                
            if isinstance(data[1], Exception):
                logger.error(f"🌍 ERROR → Notes query failed: {data[1]}")
                notes = []
            else:
                notes = data[1] or []
                
            if isinstance(data[2], Exception):
                logger.error(f"🌍 ERROR → Tasks query failed: {data[2]}")
                tasks = []
            else:
                tasks = data[2] or []
                
            if isinstance(data[3], Exception):
                logger.error(f"🌍 ERROR → Appointments query failed: {data[3]}")
                appointments = []
            else:
                appointments = data[3] or []
                
            if isinstance(data[4], Exception):
                logger.error(f"🌍 ERROR → Availability query failed: {data[4]}")
                availability = {}
            else:
                availability = data[4] or {}
            
            # Debug log results of parallel operations
            logger.info(f"🌍 DEBUG → Parallel results:")
            logger.info(f"  basic_context: {'✅' if isinstance(basic_context, dict) and basic_context else '❌'} {len(basic_context) if isinstance(basic_context, dict) else type(basic_context)}")
            logger.info(f"  notes: {'✅' if isinstance(notes, list) else '❌'} {len(notes) if isinstance(notes, list) else type(notes)}")
            logger.info(f"  tasks: {'✅' if isinstance(tasks, list) else '❌'} {len(tasks) if isinstance(tasks, list) else type(tasks)}")
            logger.info(f"  appointments: {'✅' if isinstance(appointments, list) else '❌'} {len(appointments) if isinstance(appointments, list) else type(appointments)}")
            logger.info(f"  availability: {'✅' if isinstance(availability, dict) else '❌'} {len(availability) if isinstance(availability, dict) else type(availability)}")
            
            # Check for exceptions in parallel results
            for i, result in enumerate(data):
                if isinstance(result, Exception):
                    logger.error(f"🌍 ERROR → Parallel operation {i} failed: {result}")
                    
            # Check language examples specifically
            lang_examples = basic_context.get('language_examples', '') if isinstance(basic_context, dict) else ''
            logger.info(f"🌍 DEBUG → Language examples from basic_context: {len(lang_examples)} chars")
            
            # Extract contact details from the full contact document (same as get_intermediate_context)
            personal_details = contact_details.get("personal_details", {}) if contact_details else {}
            relationship_details = contact_details.get("relationship_details", {}) if contact_details else {}
            business_details = contact_details.get("business_details", {}) if contact_details else {}
            
            # Also extract individual contact fields for compatibility
            first_name = contact_details.get("first_name", "") if contact_details else ""
            last_name = contact_details.get("last_name", "") if contact_details else ""
            
            # Combine all context data
            full_context = {
                **basic_context,  # Spread all basic context fields
                # Add contact details (like get_intermediate_context)
                "personal_details": personal_details,
                "relationship_details": relationship_details,
                "business_details": business_details,
                # Add individual contact fields for payload compatibility
                "first_name": first_name,
                "last_name": last_name,
                "email": primary_email,
                # Historical interaction context
                "subset_notes": notes,
                "subset_tasks": tasks,
                "subset_appointments": appointments,  # Appointments now filtered by contact emails
                "availability": availability  # NEW: Explicit availability data
            }
            
            return full_context
            
        except Exception as e:
            logger.error(f"🌍 ERROR → Error getting full context: {e}")
            return {}

    async def get_intermediate_context(
        self, 
        user_id: str, 
        contact_id: str, 
        account_id: str
    ) -> Dict[str, Any]:
        """
        Get intermediate context for context update operations.
        Includes contact details and user info but NO historical data (notes/tasks/appointments).
        Optimized for contact information updates and relationship analysis.
        """
        try:
            # Get basic context and contact details in parallel - same pattern as get_full_context
            data = await asyncio.gather(
                self.get_basic_context(user_id, contact_id, account_id),
                self._get_contact_details(contact_id, account_id),
                return_exceptions=True
            )
            
            basic_context = data[0] if not isinstance(data[0], Exception) else {}
            contact_details = data[1] if not isinstance(data[1], Exception) else {}
            
            # Extract contact details from the full contact document
            personal_details = contact_details.get("personal_details", {}) if contact_details else {}
            relationship_details = contact_details.get("relationship_details", {}) if contact_details else {}
            business_details = contact_details.get("business_details", {}) if contact_details else {}
            
            # Follow the same pattern as get_full_context: spread basic_context and add specific data
            intermediate_context = {
                **basic_context,  # Spread all basic context fields
                # Override/add contact details from full contact document
                "personal_details": personal_details,
                "relationship_details": relationship_details,
                "business_details": business_details,
                # Explicitly exclude historical data for intermediate context
                "subset_notes": [],  # Empty - no historical notes
                "subset_tasks": [],  # Empty - no historical tasks  
                "subset_appointments": []  # Empty - no historical appointments
            }
            
            return intermediate_context
            
        except Exception as e:
            logger.error(f"Error getting intermediate context: {e}")
            return {}
    
    # === HELPER METHODS ===
    
    def _document_to_dict(self, doc) -> Dict[str, Any]:
        """Converts a Firestore document to a dictionary and adds the document ID."""
        if not doc.exists:
            return {}
        data = doc.to_dict()
        data['id'] = doc.id
        return data

    async def get_user_language_examples(
        self, 
        user_id: str, 
        limit: int = 10,
        fallback_text: Optional[str] = None
    ) -> str:
        """
        Retrieve text message examples for a user and format them for AI generation.
        
        Uses the correct subcollection structure: users/{user_id}/text_message_examples
        
        Args:
            user_id (str): The user ID to fetch examples for
            limit (int): Maximum number of examples to retrieve (default: 10)
            fallback_text (str, optional): Default text if no examples found
            
        Returns:
            str: Formatted string of text message examples, one per line
        """
        if fallback_text is None:
            fallback_text = ""
        
        logger.info(f"📝 Fetching language examples for user {user_id}")
        
        try:
            examples_query = (self.db.collection("users")
                            .document(user_id)
                            .collection("text_message_examples")
                            .limit(limit))
            examples_docs = await examples_query.get()
            
            logger.info(f"📝 DEBUG → Language examples query returned {len(examples_docs)} documents")
            
            if examples_docs:
                examples_list = []
                for doc in examples_docs:
                    example_data = doc.to_dict()
                    
                    example_text = example_data.get("example_text", "")
                    
                    if example_text:
                        examples_list.append(example_text)
                        logger.info(f"📝 DEBUG → Found example: '{example_text[:50]}...'")
                    else:
                        logger.warning(f"📝 DEBUG → Doc {doc.id} has no text in any expected field: {list(example_data.keys())}")
                
                if examples_list:
                    result = "\n".join(examples_list)
                    logger.info(f"📝 DEBUG → Returning {len(examples_list)} examples, {len(result)} total chars")
                    return result
            
            logger.info(f"📝 DEBUG → No text message examples found for user {user_id}, returning fallback")
            return fallback_text
            
        except Exception as e:
            logger.error(f"📝 ERROR → Error fetching language examples: {e}")
            return fallback_text
    
    def _extract_emails_from_contact_data(self, contact_data: Optional[Dict[str, Any]]) -> List[str]:
        """Extracts all emails from a contact data dictionary."""
        if not contact_data:
            logger.info("📧 DEBUG → No contact data provided for email extraction")
            return []
        
        emails = []
        # Add primary email
        if contact_data.get("email"):
            emails.append(contact_data["email"])
            logger.info(f"📧 DEBUG → Found primary email: {contact_data['email']}")
        
        # Add additional emails from emails array
        additional_emails = contact_data.get("emails", [])
        logger.info(f"📧 DEBUG → Processing {len(additional_emails)} additional emails")
        logger.info(f"📧 DEBUG → Additional emails raw data: {additional_emails}")
        
        for i, email_obj in enumerate(additional_emails):
            if isinstance(email_obj, dict):
                logger.info(f"📧 DEBUG → Email object {i+1} keys: {list(email_obj.keys())}")
                email_address = email_obj.get("address")
                if email_address:
                    emails.append(email_address)
                    logger.info(f"📧 DEBUG → Found email {i+1}: {email_address} ({email_obj.get('label', 'no label')})")
                else:
                    logger.warning(f"📧 DEBUG → Email object {i+1} has no 'address' field: {email_obj}")
            elif isinstance(email_obj, str):
                emails.append(email_obj)
                logger.info(f"📧 DEBUG → Found string email {i+1}: {email_obj}")
        
        # Remove duplicates and return
        unique_emails = list(set(emails))
        logger.info(f"📧 DEBUG → Extracted {len(unique_emails)} unique emails: {unique_emails}")
        return unique_emails

    async def _get_contact_details(self, contact_id: str, account_id: str) -> Optional[Dict[str, Any]]:
        """Get full contact details."""
        try:
            contact_ref = self.db.collection("contacts").document(str(contact_id))
            contact_doc = await contact_ref.get()
            
            if contact_doc.exists:
                contact_data = contact_doc.to_dict()
                # Verify account ownership
                if contact_data.get("account_id") == account_id and not contact_data.get("is_deleted", False):
                    return contact_data
            
            return None
        except Exception as e:
            logger.error(f"Error getting contact details: {e}")
            return None

    async def _get_notes(self, contact_id: str, account_id: str, past_limit_days: Optional[int] = None) -> List[Dict[str, Any]]:
        """
        Get notes for the contact with configurable time window.
        
        Args:
            contact_id (str): Contact ID
            account_id (str): Account ID  
            past_limit_days (int, optional): How far back to look. None for all notes.
            
        Returns:
            List of note documents
        """
        try:
            logger.info(f"📋 DEBUG → Getting notes for contact {contact_id}, past_limit_days={past_limit_days}")
            
            # Query the correct subcollection structure: contacts/{contact_id}/notes
            # FIXED: Don't filter by is_deleted if the field doesn't exist - get all notes first
            query = self.db.collection("contacts").document(str(contact_id)).collection("notes")
            
            # Apply time filter if specified
            if past_limit_days is not None:
                cutoff_date = utc_now() - timedelta(days=past_limit_days)
                query = query.where(filter=FieldFilter("created_on", ">=", cutoff_date))
                logger.info(f"📋 DEBUG → Applied time filter: notes after {cutoff_date}")
            
            query = query.order_by("created_on", direction=firestore.Query.DESCENDING).limit(100)
            
            notes_docs = await query.get()
            logger.info(f"📋 DEBUG → Raw query returned {len(notes_docs)} note documents")
            
            # Filter to essential fields only for AI operations
            essential_notes = []
            for doc in notes_docs:
                note_data = self._document_to_dict(doc)
                
                # FIXED: Skip deleted notes (handles missing is_deleted field)
                is_deleted = note_data.get("is_deleted", False)
                
                if is_deleted:
                    logger.info(f"📋 DEBUG → Skipping deleted note {doc.id}")
                    continue
                
                essential_note = {}
                for field in NOTE_ESSENTIAL_FIELDS:
                    if field in note_data:
                        essential_note[field] = note_data[field]
                essential_notes.append(essential_note)
                
                logger.info(f"📋 DEBUG → Processed note {doc.id}: {note_data.get('raw_note', '')[:50]}...")
            
            logger.info(f"📋 DEBUG → Processed {len(essential_notes)} essential notes for contact {contact_id}")
            return essential_notes
            
        except Exception as e:
            logger.error(f"📋 ERROR → Error getting notes: {e}")
            return []
    
    async def _get_tasks(self, contact_id: str, account_id: str, past_limit_days: Optional[int] = None) -> List[Dict[str, Any]]:
        """
        Get tasks for the contact.
        
        This function retrieves all pending tasks.
        
        Args:
            contact_id (str): Contact ID
            account_id (str): Account ID
            past_limit_days (int, optional): This parameter is no longer used.
            
        Returns:
            List of task documents
        """
        try:
            all_tasks = []
            
            # Get the tasks subcollection for this contact
            tasks_collection = self.db.collection("contacts").document(str(contact_id)).collection("tasks")
            
            # Get all pending tasks (regardless of date)
            pending_query = (tasks_collection
                           .where(filter=FieldFilter("status", "in", ["pending", "actionable"]))
                           .order_by("created_on", direction=firestore.Query.DESCENDING)
                           .limit(50))
            
            pending_docs = await pending_query.get()
            all_tasks.extend([self._document_to_dict(doc) for doc in pending_docs])
            
            # Filter to essential fields only for AI operations
            essential_tasks = []
            for task_data in all_tasks:
                essential_task = {}
                for field in TASK_ESSENTIAL_FIELDS:
                    if field in task_data:
                        essential_task[field] = task_data[field]
                essential_tasks.append(essential_task)
            
            logger.info(f"Retrieved {len(essential_tasks)} tasks for contact {contact_id}")
            return essential_tasks
            
        except Exception as e:
            logger.error(f"Error getting tasks: {e}")
            return []
    
    async def _get_appointments(
        self,
        user_id: str,
        contact_emails: List[str],
        past_limit_days: int = 30,
        future_limit_days: int = 30,
        contact_id: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """
        Get appointments filtered by contact's email presence in attendees.
        
        Per new plan: Only appointments where one of the contact's emails is in the attendee list.
        
        Args:
            user_id (str): The user ID for appointment lookups
            contact_emails (List[str]): A list of the contact's emails to filter by.
            past_limit_days (int): How far back to look for past appointments
            future_limit_days (int): How far forward to look for future appointments
            contact_id (str, optional): Contact ID for additional filtering
            
        Returns:
            List of appointment documents filtered by attendee email presence
        """
        try:
            logger.info(f"📅 DEBUG → Getting appointments for user {user_id}, contact_emails={contact_emails}")
            logger.info(f"📅 DEBUG → Parameters: past_limit_days={past_limit_days}, future_limit_days={future_limit_days}")
            
            # Normalise parameters
            contact_emails = contact_emails or []
            contact_emails_lower = [email.lower() for email in contact_emails]

            if not contact_emails and not contact_id:
                logger.warning(
                    "📅 DEBUG → No contact emails or contact_id provided – cannot filter appointments reliably. "
                    "Returning empty appointment list to avoid leaking unrelated events."
                )
                return []

            now_utc = utc_now()
            past_cutoff = now_utc - timedelta(days=past_limit_days)
            future_cutoff = None if future_limit_days in (None, 0) else now_utc + timedelta(days=future_limit_days)
            
            logger.info(
                f"📅 DEBUG → Time window (UTC aware): {past_cutoff.isoformat()} to {future_cutoff.isoformat() if future_cutoff else 'None'}"
            )
            
            # Get user's appointments (from users/{user_id}/appointments collection)
            if not user_id:
                logger.error(f"📅 ERROR → User ID is required to fetch appointments.")
                return []
            
            # Get past appointments (do not filter by is_deleted at query level – we'll skip deleted ones in code)
            past_query = (
                self.db.collection("users")
                .document(user_id)
                .collection("appointments")
                .where(filter=FieldFilter("start_time", ">=", past_cutoff))
                .where(filter=FieldFilter("start_time", "<=", now_utc))
                .order_by("start_time", direction=firestore.Query.DESCENDING)
                .limit(50)
            )
            
            # Get future appointments – apply upper bound only if future_cutoff is set
            future_query_base = (
                self.db.collection("users")
                .document(user_id)
                .collection("appointments")
                .where(filter=FieldFilter("start_time", ">=", now_utc))
            )

            if future_cutoff:
                future_query_base = future_query_base.where(
                    filter=FieldFilter("start_time", "<=", future_cutoff)
                )

            future_query = (
                future_query_base.order_by("start_time", direction=firestore.Query.ASCENDING).limit(50)
            )
            
            past_docs = await past_query.get()
            future_docs = await future_query.get()
            
            logger.info(
                f"📅 DEBUG → Raw queries returned {len(past_docs)} past + {len(future_docs)} future appointments"
            )
            
            all_appointments = []
            all_appointments.extend([self._document_to_dict(doc) for doc in past_docs])
            all_appointments.extend([self._document_to_dict(doc) for doc in future_docs])
            
            # Filter appointments by attendee emails OR assiist_contact_ids match
            logger.info(
                f"📅 DEBUG → Filtering {len(all_appointments)} appointments using emails={contact_emails} and contact_id={contact_id}"
            )
            
            filtered_appointments = []
            for appointment_data in all_appointments:
                # Skip deleted or cancelled appointments
                if appointment_data.get("is_deleted", False):
                    logger.debug(f"📅 DEBUG → Skipping deleted appointment: {appointment_data.get('title', 'No title')}")
                    continue
                    
                if appointment_data.get("status") == "cancelled":
                    logger.debug(f"📅 DEBUG → Skipping cancelled appointment: {appointment_data.get('title', 'No title')}")
                    continue

                attendees = appointment_data.get("attendees", [])
                
                appointment_has_contact = False

                # a) Check attendee emails first (preferred)
                for attendee in attendees:
                    attendee_email = None
                    if isinstance(attendee, dict):
                        attendee_email = attendee.get("email") or attendee.get("address")
                    elif isinstance(attendee, str):
                        attendee_email = attendee

                    if attendee_email and attendee_email.lower() in contact_emails_lower:
                        appointment_has_contact = True
                        logger.info(
                            f"📅 DEBUG → Matched appointment via attendee email: {appointment_data.get('title', 'No title')} (attendee: {attendee_email})"
                        )
                        break

                # b) Fallback – match via assiist_contact_ids linkage if not matched yet
                if not appointment_has_contact and contact_id:
                    contact_ids_in_appt = appointment_data.get("assiist_contact_ids", [])
                    contact_ids_as_str = [str(cid) for cid in contact_ids_in_appt]

                    if contact_id in contact_ids_as_str:
                        appointment_has_contact = True
                        logger.info(
                            f"📅 DEBUG → Matched appointment via assiist_contact_ids: {appointment_data.get('title', 'No title')} (contact_id link)"
                        )

                if appointment_has_contact:
                    # Filter to essential fields only for AI operations
                    essential_appointment = {}
                    for field in APPOINTMENT_ESSENTIAL_FIELDS:
                        if field in appointment_data:
                            essential_appointment[field] = appointment_data[field]
                    filtered_appointments.append(essential_appointment)
            
            logger.info(f"📅 DEBUG → Filtered {len(filtered_appointments)} appointments for contact emails {contact_emails}")
            return filtered_appointments
            
        except Exception as e:
            logger.error(f"📅 ERROR → Error getting filtered appointments: {e}")
            return []

    async def _get_availability(self, user_id: str, future_limit_days: int = 30) -> Dict[str, Any]:
        """
        Get availability data using Google Calendar Free/Busy API.
        
        Args:
            user_id: User ID
            future_limit_days: How far forward to look
        
        Returns:
            Formatted availability data for AI context
        """
        logger.info(f"🗓️ DEBUG → _get_availability called for user {user_id}, future_limit_days={future_limit_days}")
        
        async def _get_availability_impl():
            try:
                from assiist_back_end.services.google_calendar_service import get_freebusy_for_calendars, format_availability_for_ai
                from assiist_back_end.config import Settings
                
                settings = Settings()
                time_min = utc_now()
                time_max = utc_now() + timedelta(days=future_limit_days)
                
                logger.info(f"🗓️ DEBUG → Time range: {time_min.isoformat()} to {time_max.isoformat()}")
                
                # Get free/busy data from Google Calendar service
                logger.info(f"🗓️ DEBUG → Calling get_freebusy_for_calendars...")
                freebusy_data = await get_freebusy_for_calendars(
                    user_id=user_id,
                    db_client=self.db,
                    settings=settings,
                    time_min=time_min,
                    time_max=time_max
                )
                
                logger.info(f"🗓️ DEBUG → get_freebusy_for_calendars returned: {freebusy_data}")
                
                # Format for AI consumption
                logger.info(f"🗓️ DEBUG → Calling format_availability_for_ai...")
                availability = await format_availability_for_ai(freebusy_data)
                
                logger.info(f"🗓️ DEBUG → Final availability result: {availability}")
                return availability
                
            except Exception as e:
                logger.error(f"🗓️ ERROR → Error getting availability data: {e}", exc_info=True)
                return {
                    "time_range": {"start": "", "end": ""},
                    "busy_periods": [],
                    "calendars_checked": [],
                    "total_busy_periods": 0
                }
        
        try:
            # WRAP THE ENTIRE FUNCTION IN A 10 SECOND TIMEOUT - BE AGGRESSIVE
            print(f"⏰ APPLYING 10 SECOND TIMEOUT...")
            return await asyncio.wait_for(_get_availability_impl(), timeout=10.0)
        except asyncio.TimeoutError:
            print(f"⏰ TIMED OUT after 10 seconds for user {user_id}")
            logger.error(f"⏰ Entire availability function timed out after 10 seconds for user {user_id}")
            return {
                "time_range": {"start": "", "end": ""},
                "busy_periods": [],
                "calendars_checked": [],
                "total_busy_periods": 0
            }

# Convenience function for creating GenAI utilities instance
def create_genai_utilities(db: AsyncClient) -> GenAIUtilities:
    """Create a GenAI utilities instance with the provided database client."""
    return GenAIUtilities(db) 