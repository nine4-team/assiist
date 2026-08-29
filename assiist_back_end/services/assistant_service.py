import asyncio
import logging
import uuid
from typing import Dict, Any, List, Optional
from datetime import datetime, timezone
from google.cloud.firestore_v1.async_client import AsyncClient
import os
import requests

# Import repositories
from assiist_back_end.db.repositories.interfaces.task_repository import TaskRepository
from assiist_back_end.db.repositories.interfaces.contact_repository import ContactRepository
from assiist_back_end.db.repositories.interfaces.note_repository import NoteRepository
from assiist_back_end.db.repositories.interfaces.generation_request_repository import (
    GenAIRequestRepository
)
from assiist_back_end.db.repositories.interfaces.revision_repository import RevisionHistoryRepository
from assiist_back_end.db.repositories.interfaces.audio_transcription_repository import AudioTranscriptionRepository

# Import models
from assiist_back_end.models.task import Task, TaskType, TaskStatus
from assiist_back_end.models.contact import PersonalDetails, RelationshipDetail, BusinessDetails, BusinessOpportunity
from assiist_back_end.models.generation import GenerationRequest
from assiist_back_end.models.note import Note, ProcessedNote

# Import canonical models (no more transformers)
from assiist_back_end.models.revision_request import RevisionRequest, QuickDraftRequest

# Import GenAI utilities for context retrieval
from assiist_back_end.services.genai_service import GenAIUtilities
from assiist_back_end.utils.time import utc_now

logger = logging.getLogger(__name__)

class AssistantService:
    """
    Central service for ALL AI operations including quick drafts, revisions, and update assistant.
    Handles ALL data persistence for AI operations, ensuring consistent data handling across features.
    REFACTORED: Now uses canonical RevisionRequest/QuickDraftRequest models to eliminate data transformation hell.
    """
    
    def __init__(
        self, 
        db: AsyncClient, 
        task_repo: TaskRepository, 
        contact_repo: ContactRepository,
        note_repo: NoteRepository,
        genai_request_repo: GenAIRequestRepository,
        revision_repo: RevisionHistoryRepository,
        genai_utils: GenAIUtilities,
        audio_transcription_repo: AudioTranscriptionRepository | None = None,
        base_url: str = "http://localhost:8000/api/v1"
    ):
        self.db = db
        self.task_repo = task_repo
        self.contact_repo = contact_repo
        self.note_repo = note_repo
        self.genai_request_repo = genai_request_repo
        self.revision_repo = revision_repo
        self.audio_transcription_repo = audio_transcription_repo
        self.genai_utils = genai_utils
        self.base_url = base_url
        
        # Get internal API key from environment for authentication
        from assiist_back_end.config import settings
        self.internal_api_key = settings.ASSIIST_API_KEY.get_secret_value() if settings.ASSIIST_API_KEY else None
        if not self.internal_api_key:
            logger.warning("ASSIIST_API_KEY not found in environment - internal API calls may fail")
        
    


    # === SHARED UTILITIES ===
    
    async def _get_account_id_for_request(self, id: str, user_id: str, request_type: str) -> str:
        """Helper to get account_id from user document for new request creation."""
        try:
            # Get account_id from user document (primary source)
            user_ref = self.db.collection("users").document(user_id)
            user_doc = await user_ref.get()
            if user_doc.exists:
                account_id = user_doc.to_dict().get("account_id")
                if account_id:
                    return account_id
            
            raise ValueError(f"Account ID not found for user {user_id}")
            
        except Exception as e:
            logger.error(f"Error getting account_id for user {user_id}: {e}")
            raise

    async def _call_genai_endpoint(self, endpoint: str, data: dict) -> Dict[str, Any]:
        """
        Call GenAI endpoint with callback URL for async operations.
        Updated to provide internal callback URL as required by public API standard.
        """
        endpoint_url = f"{self.base_url}/genai/{endpoint}"
        
        # Add internal callback URL to all requests (public API standard)
        if not self.base_url:
            raise ValueError("API_URL is required for cloud function callbacks")
        internal_callback_url = f"{self.base_url.rstrip('/')}/genai/handle-results"
        
        # Include callback URL in payload
        payload = {
            **data,
            "callback_url": internal_callback_url  # ✅ Provide callback URL
        }
        
        # Convert any datetime objects to UTC ISO-8601 strings recursively
        def _convert_datetimes(obj):
            if isinstance(obj, datetime):
                return obj.astimezone(timezone.utc).isoformat()
            elif isinstance(obj, dict):
                return {k: _convert_datetimes(v) for k, v in obj.items()}
            elif isinstance(obj, list):
                return [_convert_datetimes(v) for v in obj]
            else:
                return obj

        payload = _convert_datetimes(payload)
        
        try:
            # Validate required fields using natural field names
            if endpoint == "revise-draft":
                if not payload.get('id'):
                    raise ValueError("Missing required field 'id' in revision request")
                if not payload.get('revision_instructions'):
                    raise ValueError("Missing required field 'revision_instructions' in revision request")
            elif endpoint == "quick-draft":
                if not payload.get('id'):
                    raise ValueError("Missing required field 'id' in quick draft request")
                if not payload.get('message_instructions'):
                    raise ValueError("Missing required field 'message_instructions' in quick draft request")
            
            # Prepare headers with internal API key authentication
            headers = {
                "Content-Type": "application/json"
            }
            
            if self.internal_api_key:
                headers["X-Internal-API-Key"] = self.internal_api_key
            
            # Use asyncio to make the request non-blocking
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                None,
                lambda: requests.post(
                    endpoint_url,
                    json=payload,
                    timeout=3600,
                    headers=headers
                )
            )
            
            response.raise_for_status()
            result = response.json()
            
            return result
            
        except Exception as e:
            logger.error(f"❌ {endpoint} cloud function failed → {e}")
            raise

    async def handle_generation_request(self, id: str, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Main entry point for ALL generation requests from Firestore triggers.
        Handles the complete flow: data gathering → AI processing → result storage.
        """
        try:
            request_type = request_data["request_type"]
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] 🔄 ASSISTANT → Handling {request_type} request {id}")
            
            # Route to specific handlers
            if request_type == "quick_draft":
                return await self.process_quick_draft_request(id, request_data)
            elif request_type == "revise_draft":
                return await self.process_revision_request(id, request_data)
            elif request_type == "update_tasks":
                return await self.process_update_tasks_request(id, request_data)
            elif request_type == "update_context":
                return await self.process_update_context_request(id, request_data)
            elif request_type == "process_note":
                return await self.process_note_processing_request(id, request_data)
            elif request_type == "transcription":
                return await self.process_transcription_response(id, request_data)
            elif request_type == "enhance_transcript":
                return await self.process_enhancement_response(id, request_data)
            else:
                raise ValueError(f"Unknown request type: {request_type}")
                
        except Exception as e:
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] ❌ ASSISTANT → Error handling generation request: {e}")
            # Update request status to failed using unified repository
            try:
                await self.genai_request_repo.update_status_with_error(id, "failed", str(e))
            except Exception as update_error:
                logger.error(f"Failed to update error status for request {id}: {update_error}")
            raise


    # === REQUEST PROCESSING (Create requests, call cloud functions) ===

    async def process_quick_draft_request(self, id: str, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Service layer creates full Firestore document using centralized transformers.
        Updated to follow documented centralized transformation approach.
        """
        try:
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] 📝 ASSISTANT → Processing quick draft request {id}")
            
            # Gather context using GenAI utilities
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] 📊 ASSISTANT → Gathering context for quick draft request")
            
            # Get account_id from request or fetch from user data
            account_id = request_data.get("account_id")
            if not account_id:
                user_ref = self.db.collection("users").document(request_data["user_id"])
                user_doc = await user_ref.get()
                if user_doc.exists:
                    user_data = user_doc.to_dict()
                    account_id = user_data.get("account_id")
                if not account_id:
                    raise ValueError("Account ID not found for user")
            
            # Use GenAI utilities for context retrieval - basic context for quick drafts
            context = await self.genai_utils.get_basic_context(
                user_id=request_data["user_id"],
                contact_id=str(request_data["contact_id"]),
                account_id=account_id
            )
            
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] 🔧 ASSISTANT → Creating canonical QuickDraftRequest")
            
            # Convert language examples from string to list if needed
            language_examples_str = context.get("language_examples", "")
            language_examples = language_examples_str.split("\n") if language_examples_str else []
            
            # Create GenAI payload with REQUIRED fields - this becomes request_data
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] 🔗 ASSISTANT → Building GenAI payload for quick-draft")
            
            # DEBUG: Log what we got from context gathering
            print(f"[{timestamp}] 🔍 DEBUG → Quick Draft Context:")
            print(f"  language_examples: {len(context.get('language_examples', ''))} chars")
            if not context.get('language_examples'):
                print(f"  ❌ No language examples found in context")
                print(f"  Context keys: {list(context.keys())}")
            
            genai_payload = {
                "id": id,  # ← Standardize identifier field
                "account_id": account_id,
                "user_id": request_data["user_id"],
                "contact_id": request_data["contact_id"],
                "message_instructions": request_data["message_instructions"],  # ← Keep natural field name
                "message_language": request_data.get("message_language", "english"),
                "user_first_name": context.get("user_first_name", ""),
                "business_name": context.get("business_name", ""),
                "business_type": context.get("business_type", ""),
                "recipient_name": context.get("addressed_as", ""),  # ← Use addressed_as
                "recipient_phone": context.get("contact_phone", ""),
                "language_examples": language_examples_str
            }
            
            # Create unified Firestore document with dynamic request_data
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] 💾 ASSISTANT → Creating unified Firestore document")
            await self.genai_request_repo.create_request(
                id=id,
                request_type="quick_draft",
                user_id=request_data["user_id"],
                contact_id=request_data["contact_id"],
                account_id=account_id,
                request_data=genai_payload  # Store the same payload sent to cloud function
            )
            
            # Call existing endpoint method (validates canonical format)
            await self._call_genai_endpoint("quick-draft", genai_payload)
            
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] ✅ ASSISTANT → Quick draft request {id} submitted to GenAI endpoint")
            return {"status": "submitted", "message": "Quick draft request submitted to genai endpoint"}
            
        except Exception as e:
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] ❌ ASSISTANT → Error in quick draft request: {e}")
            # Update request status to failed if document was created
            try:
                await self.genai_request_repo.update_status_with_error(id, "failed", str(e))
            except Exception as update_error:
                logger.error(f"Failed to update error status for request {id}: {update_error}")
            raise

    async def process_revision_request(self, id: str, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        UPDATED: Backend fetches all task data - frontend only sends task_id and instructions.
        Service layer creates full Firestore document using centralized transformers.
        """
        try:
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] ✏️ ASSISTANT → Processing revision request {id}")
            
            # STEP 1: FETCH TASK DATA FROM TASK_ID
            task_id = request_data["task_id"]
            task = await self.task_repo.get_by_id(
                user_id=request_data["user_id"],
                contact_id=str(request_data["contact_id"]),
                task_id=task_id
            )
            
            if not task:
                raise ValueError(f"Task {task_id} not found or you don't have access to it")
            
            # STEP 2: EXTRACT MESSAGE DRAFT FROM TASK
            message_draft = task.body
            if not message_draft or message_draft.strip() == "":
                raise ValueError(f"Task {task_id} has no message content to revise")
            
            print(f"[{timestamp}] 📋 ASSISTANT → Found task with body: '{message_draft[:50]}...'")
            
            # STEP 3: FETCH REVISION HISTORY
            revision_history = None
            if hasattr(task, 'revision_history_id') and task.revision_history_id:
                revision_history = await self.revision_repo.get_by_id(task.revision_history_id)
                print(f"[{timestamp}] 📋 ASSISTANT → Retrieved revision history by ID: {task.revision_history_id}")
            else:
                # Fallback: try to get by task_id for older tasks
                revision_history = await self.revision_repo.get_for_task(task_id)
                print(f"[{timestamp}] 📋 ASSISTANT → Retrieved revision history by task_id (fallback)")
            
            # Format revision history as string for cloud function
            if revision_history:
                # Build formatted revision history string
                formatted_history = f"Original message: {revision_history.original_message}\n\n"
                
                if revision_history.revisions:
                    formatted_history += "Previous revisions:\n"
                    for i, revision in enumerate(revision_history.revisions, 1):
                        formatted_history += f"{i}. Instructions: {revision.revision_instructions or 'No specific instructions'}\n"
                        formatted_history += f"   Result: {revision.revised_message}\n"
                        formatted_history += f"   Date: {revision.timestamp.strftime('%Y-%m-%d %H:%M:%S')}\n\n"
                else:
                    formatted_history += "No previous revisions.\n"
                    
                print(f"[{timestamp}] 📋 ASSISTANT → Found revision history with {len(revision_history.revisions)} previous revisions")
            else:
                # Use task body as original message if no revision history found
                print(f"[{timestamp}] ⚠️ ASSISTANT → No revision history found for task {task_id}")
                formatted_history = f"Original message: {message_draft}\nNo previous revisions."
            
            print(f"[{timestamp}] 📋 ASSISTANT → Revision history: {len(formatted_history)} chars")
            
            # STEP 4: GATHER CONTEXT using GenAI utilities
            print(f"[{timestamp}] 📊 ASSISTANT → Gathering context for revision request")
            
            # Get account_id from request or fetch from user data
            account_id = request_data.get("account_id")
            if not account_id:
                user_ref = self.db.collection("users").document(request_data["user_id"])
                user_doc = await user_ref.get()
                if user_doc.exists:
                    user_data = user_doc.to_dict()
                    account_id = user_data.get("account_id")
                if not account_id:
                    raise ValueError("Account ID not found for user")
            
            # Use GenAI utilities for context retrieval - basic context for revisions
            context = await self.genai_utils.get_basic_context(
                user_id=request_data["user_id"],
                contact_id=str(request_data["contact_id"]),
                account_id=account_id
            )
            
            # STEP 5: BUILD COMPLETE REQUEST DATA WITH FETCHED VALUES
            complete_request_data = {
                **request_data,
                "message_draft": message_draft,  # ← FETCHED from task
                "revision_history": formatted_history,  # ← FETCHED from revision_repo
            }
            
            # STEP 6: CREATE FIRESTORE DOCUMENT AND GENAI PAYLOAD
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] 🔧 ASSISTANT → Creating revision request")
            
            # Convert language examples from string to list if needed
            language_examples_str = context.get("language_examples", "")
            language_examples = language_examples_str.split("\n") if language_examples_str else []
            
            # Create GenAI payload with REQUIRED fields - this becomes request_data
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] 🔗 ASSISTANT → Building GenAI payload for revise-draft")
            
            # DEBUG: Log what we got from context gathering
            print(f"[{timestamp}] 🔍 DEBUG → Revision Context:")
            print(f"  language_examples: {len(context.get('language_examples', ''))} chars")
            if not context.get('language_examples'):
                print(f"  ❌ No language examples found in context")
                print(f"  Context keys: {list(context.keys())}")
            
            genai_payload = {
                "id": id,  # ← Standardize identifier field
                "account_id": account_id,
                "user_id": request_data["user_id"],
                "contact_id": request_data["contact_id"],
                "task_id": request_data["task_id"],
                "message_draft": message_draft,
                "revision_instructions": request_data["revision_instructions"],  # ← Keep natural field name
                "revision_history": formatted_history,
                "message_language": request_data.get("message_language", "english"),
                "user_first_name": context.get("user_first_name", ""),
                "business_name": context.get("business_name", ""),
                "business_type": context.get("business_type", ""),
                "recipient_name": context.get("addressed_as", ""),  # ← Use addressed_as
                "recipient_phone": context.get("contact_phone", ""),
                "language_examples": language_examples_str
            }
            
            # Create unified Firestore document with dynamic request_data
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] 💾 ASSISTANT → Creating unified Firestore document")
            await self.genai_request_repo.create_request(
                id=id,
                request_type="revise_draft",
                user_id=request_data["user_id"],
                contact_id=request_data["contact_id"],
                account_id=account_id,
                request_data=genai_payload  # Store the same payload sent to cloud function
            )
            
            # Call existing endpoint method (validates canonical format)
            await self._call_genai_endpoint("revise-draft", genai_payload)
            
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] ✅ ASSISTANT → Revision request {id} submitted to GenAI endpoint")
            return {"status": "submitted", "message": "Revision request submitted to genai endpoint"}
            
        except Exception as e:
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] ❌ ASSISTANT → Error in revision request: {e}")
            # Update request status to failed if document was created
            try:
                await self.genai_request_repo.update_status_with_error(id, "failed", str(e))
            except Exception as update_error:
                logger.error(f"Failed to update error status for request {id}: {update_error}")
            raise

    async def process_update_tasks_request(self, id: str, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create update tasks request and call cloud function."""
        try:
            # Get account_id
            account_id = await self._get_account_id_for_request(id, request_data["user_id"], "update_tasks")
            
            # Gather full context using GenAI utilities for update assistant operations
            context = await self.genai_utils.get_full_context(
                user_id=request_data["user_id"],
                contact_id=str(request_data["contact_id"]),
                account_id=account_id,
                past_limit_days=30,    # Configurable time windows
                future_limit_days=30   # For appointments
            )
            
            # Extract follow_up_immediately from request data
            follow_up_immediately = request_data.get("follow_up_immediately", False)
            
            # Create payload for GenAI endpoint with business context only (NO database IDs)
            # Database IDs are stored in Firestore and retrieved by cloud functions when needed
            payload = {
                "id": id,  # ← Request identifier only
                "raw_note": request_data.get("note_content", ""),
                # Business context for AI processing (no database routing IDs)
                "user_first_name": context.get("user_first_name", ""),
                "business_type": context.get("business_type", ""),
                "business_name": context.get("business_name", ""),
                "business_description": context.get("business_description", ""),
                "addressed_as": context.get("addressed_as", ""),  # ← Changed from recipient_name for consistency
                "first_name": context.get("first_name", ""),
                "last_name": context.get("last_name", ""),
                "recipient_phone": context.get("contact_phone", ""),
                "relationship_details": context.get("relationship_details", ""),
                "personal_details": context.get("personal_details", ""),
                "business_details": context.get("business_details", {}),
                "current_datetime": context.get("current_datetime", ""),  # User's current local datetime
                "follow_up_immediately": follow_up_immediately,  # ← Use actual value from frontend
                "language_examples": context.get("language_examples", ""),
                # Dynamic context based on available historical data
                "subset_notes": context.get("subset_notes", []),
                "subset_tasks": context.get("subset_tasks", []),
                "subset_appointments": context.get("subset_appointments", []),  # Now filtered by contact emails
                "availability": context.get("availability", {}),  # NEW: Availability data
                "user_timezone": request_data.get("user_timezone", "UTC"),
            }
            
            # DEBUG: Log what we're actually sending to the cloud function
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] 🔍 DEBUG → Update Tasks Payload:")
            print(f"  language_examples: {len(context.get('language_examples', ''))} chars")
            print(f"  subset_notes: {len(context.get('subset_notes', []))} items")
            print(f"  subset_tasks: {len(context.get('subset_tasks', []))} items") 
            print(f"  subset_appointments: {len(context.get('subset_appointments', []))} items")
            print(f"  availability: {len(context.get('availability', {}))} fields")
            
            # If any are empty, log the full context keys for debugging
            if not context.get('language_examples') or not context.get('subset_notes') or not context.get('subset_appointments'):
                print(f"[{timestamp}] 🔍 DEBUG → Full context keys: {list(context.keys())}")
                print(f"[{timestamp}] 🔍 DEBUG → Context values preview:")
                for key, value in context.items():
                    if isinstance(value, str):
                        print(f"    {key}: '{value[:100]}{'...' if len(value) > 100 else ''}'")
                    elif isinstance(value, list):
                        print(f"    {key}: list with {len(value)} items")
                    elif isinstance(value, dict):
                        print(f"    {key}: dict with {len(value)} keys")
                    else:
                        print(f"    {key}: {type(value)} - {str(value)[:50]}")
            
            
            # Create unified Firestore document with dynamic request_data
            await self.genai_request_repo.create_request(
                id=id,
                request_type="update_tasks",
                user_id=request_data["user_id"],
                contact_id=request_data["contact_id"],
                account_id=account_id,
                request_data=payload  # Store the same payload sent to cloud function
            )
            
            # Serialize datetime objects in payload to ISO strings for JSON compatibility
            def _serialize(o):
                if isinstance(o, datetime):
                    return o.isoformat()
                if isinstance(o, dict):
                    return {k: _serialize(v) for k, v in o.items()}
                if isinstance(o, list):
                    return [_serialize(v) for v in o]
                return o
            
            serialized_payload = _serialize(payload)
            
            # Call cloud function with serialized payload
            endpoint_response = await self._call_genai_endpoint("update-tasks", serialized_payload)
            
            return {"status": "submitted", "message": "Update tasks request submitted to cloud function"}
            
        except Exception as e:
            logger.error(f"❌ Task creation failed → {e}")
            await self.genai_request_repo.update_status_with_error(id, "failed", str(e))
            raise

    async def process_update_context_request(self, id: str, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create update context request and call cloud function."""
        try:
            # Get account_id
            account_id = await self._get_account_id_for_request(id, request_data["user_id"], "update_context")
            
            # Gather intermediate context (contact details only, no historical data)
            context = await self.genai_utils.get_intermediate_context(
                user_id=request_data["user_id"],
                contact_id=str(request_data["contact_id"]),
                account_id=account_id
            )
            
            # Create payload for GenAI endpoint with business context only (NO database IDs)
            # Database IDs are stored in Firestore and retrieved by cloud functions when needed
            payload = {
                "id": id,  # ← Request identifier only
                "raw_note": request_data.get("note_content", ""),
                # Business context for AI processing (no database routing IDs)
                "user_id": request_data["user_id"],  # ← Required for relationship_details key
                "user_first_name": context.get("user_first_name", ""),
                "user_last_name": context.get("user_last_name", ""),
                "business_name": context.get("business_name", ""),
                "business_type": context.get("business_type", ""),
                "contact_name": context.get("contact_name", "Contact"),
                "addressed_as": context.get("addressed_as", ""),
                "personal_details": context.get("personal_details", {}),
                "relationship_details": context.get("relationship_details", {}),
                "business_details": context.get("business_details", {}),
                "user_timezone": request_data.get("user_timezone", "UTC"),
            }
            
            # Create unified Firestore document with dynamic request_data
            await self.genai_request_repo.create_request(
                id=id,
                request_type="update_context",
                user_id=request_data["user_id"],
                contact_id=request_data["contact_id"],
                account_id=account_id,
                request_data=payload  # Store the same payload sent to cloud function
            )
            
            # Call cloud function
            endpoint_response = await self._call_genai_endpoint("update-context", payload)
            
            return {"status": "submitted", "message": "Update context request submitted to cloud function"}
            
        except Exception as e:
            logger.error(f"❌ Context update failed → {e}")
            await self.genai_request_repo.update_status_with_error(id, "failed", str(e))
            raise

    async def process_note_processing_request(self, id: str, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create note processing request and call cloud function."""
        try:
            # Get account_id
            account_id = await self._get_account_id_for_request(id, request_data["user_id"], "process_note")
            
            # Gather basic context to get actual contact name
            context = await self.genai_utils.get_basic_context(
                user_id=request_data["user_id"],
                contact_id=str(request_data["contact_id"]),
                account_id=account_id
            )
            
            # Create payload with actual contact name
            payload = {
                "id": id,  # ← Standardize identifier field
                "raw_note": request_data.get("note_content", ""),
                "contact_name": context.get("contact_name", "Contact"),  # Use actual contact name from context
                "user_timezone": request_data.get("user_timezone", "UTC"),
            }
            
            # Create unified Firestore document with dynamic request_data
            await self.genai_request_repo.create_request(
                id=id,
                request_type="process_note",
                user_id=request_data["user_id"],
                contact_id=request_data["contact_id"],
                account_id=account_id,
                request_data=payload  # Store the same payload sent to cloud function
            )
            
            # Call cloud function
            endpoint_response = await self._call_genai_endpoint("process-note", payload)
            
            return {"status": "submitted", "message": "Note processing request submitted to cloud function"}
            
        except Exception as e:
            logger.error(f"❌ Note processing failed → {e}")
            await self.genai_request_repo.update_status_with_error(id, "failed", str(e))
            raise

    async def process_update_assistant_request(self, request_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Main orchestrator for Update Assistant operations.
        Creates 3 parallel requests: update_tasks, update_context, process_note
        
        Args:
            request_data: Contains user_id, contact_id, account_id, note_content, context
            
        Returns:
            Dict with success status, request_ids, and processing info
        """
        try:
            # Use provided IDs from API endpoint (consistent pattern)
            task_request_id = request_data["task_request_id"]
            context_request_id = request_data["context_request_id"]
            # note_request_id may be omitted when the caller intends to skip note processing
            note_request_id = request_data.get("note_request_id")

            # Determine whether we should launch the note-processing flow
            note_type = request_data.get("note_type", "user")
            skip_process_note = request_data.get("skip_note_processing", False) or note_type == "system"
            
            # Get contact name for logging
            contact_name = "Unknown Contact"
            try:
                contact = await self.contact_repo.get_by_id(
                    user_id=request_data["user_id"],
                    contact_id=request_data["contact_id"]
                )
                if contact:
                    contact_name = f"{contact.first_name or ''} {contact.last_name or ''}".strip()
            except:
                pass
            
            # Safe display for note_request_id if absent
            note_id_display = note_request_id[:8] if note_request_id else "--------"
            logger.info(
                f"🤖 Message sent → Processing (req: {task_request_id[:8]}-{context_request_id[:8]}-{note_id_display}, contact: {contact_name})"
            )
            
            # Prepare base data for all operations
            base_data = {
                "user_id": request_data["user_id"],
                "contact_id": request_data["contact_id"],
                "account_id": request_data["account_id"],
                "note_content": request_data["note_content"],
                "context": request_data.get("context", {}),
                "user_timezone": request_data.get("user_timezone", "UTC"),
                "note_type": note_type,
            }
            
            # Launch required operations in parallel
            asyncio.create_task(
                self.process_update_tasks_request(task_request_id, {**base_data, "request_type": "update_tasks"})
            )
            asyncio.create_task(
                self.process_update_context_request(context_request_id, {**base_data, "request_type": "update_context"})
            )
            if not skip_process_note and note_request_id:
                asyncio.create_task(
                    self.process_note_processing_request(
                        note_request_id, {**base_data, "request_type": "process_note"}
                    )
                )
            
            # Return consolidated response with all request IDs
            request_ids = {
                "update_tasks": task_request_id,
                "update_context": context_request_id,
            }
            if not skip_process_note and note_request_id:
                request_ids["process_note"] = note_request_id

            msg_suffix = "task/context AI operations running in parallel" if skip_process_note else "3 AI operations running in parallel"

            final_response = {
                "success": True,
                "request_ids": request_ids,
                "message": f"Update Assistant processing started - {msg_suffix}",
                "estimated_completion_time": "30-90 seconds"
            }
            
            return final_response
            
        except Exception as e:
            logger.error(f"❌ Assistant processing failed: {e}")
            raise


    # === RESPONSE PROCESSING (Handle cloud function results) ===
    
    async def process_quick_draft_response(self, id: str, ai_results: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process quick draft results from cloud function and create task with revision history.
        Called by internal endpoint when get_quick_draft cloud function completes.
        """
        try:
            logger.info(f"📝 Processing quick draft results for request {id}")
            
            # Get the generation request document using repository (no security check for callbacks)
            request_doc = await self.genai_request_repo.get_generation_request(id, account_id=None)
            if not request_doc:
                raise ValueError(f"GenAI request {id} not found")
            
            user_id = request_doc.get("user_id")
            contact_id = request_doc.get("contact_id")
            account_id = request_doc.get("account_id")
            
            if not user_id or not contact_id or not account_id:
                raise ValueError(f"Missing user_id, contact_id, or account_id in request {id}")
            
            # Check for cloud function success first
            if ai_results.get("success") is False:
                error_message = ai_results.get("error", "Cloud function returned error")
                logger.error(f"Cloud function error for request {id}: {error_message}")
                raise ValueError(f"Cloud function failed: {error_message}")
            
            # Extract task data from AI results (only if success was true)
            task_data = ai_results.get("task_data", {})
            revision_context = ai_results.get("revision_context", {})
            
            # Validate that task_data contains required fields
            if not task_data or not isinstance(task_data, dict):
                logger.error(f"Invalid task_data in AI results: {task_data}")
                raise ValueError("Invalid or missing task_data in AI results")
            
            required_fields = ["title", "body", "type", "status"]
            missing_fields = [field for field in required_fields if not task_data.get(field)]
            if missing_fields:
                logger.error(f"Missing required fields in task_data: {missing_fields}")
                raise ValueError(f"Missing required fields in task_data: {missing_fields}")
            
            # Create task with revision history
            current_date = datetime.now()
            task = Task(
                account_id=account_id,
                user_id=user_id,
                contact_id=contact_id,
                title=task_data["title"],
                body=task_data["body"],
                type=task_data["type"],
                status=task_data["status"],
                llm_provider=task_data.get("llm_provider"),
                sms_url=task_data.get("sms_url"),
                assistant_intro=task_data.get("assistant_intro"),
                created_by=user_id,
                updated_by=user_id,
                actionable_date=current_date,
                due_date=current_date
            )
            
            # Create task with revision history
            created_task, revision_history = await self.task_repo.add_with_revision_history(
                task=task,
                original_message=task.body,
                context=revision_context,
                revision_repo=self.revision_repo
            )
            
            # Update generation request with clean data separation
            # result_data contains ONLY the pure GenAI output
            result_data = ai_results.get("task_data", {})
            
            processing_metadata = {
                "llm_provider": ai_results.get("llm_provider", "unknown"),
                "llm_model": ai_results.get("llm_model", "unknown"),
                "processing_time_ms": ai_results.get("processing_time_ms", 0),
                "callback_url": ai_results.get("callback_url"),  # ✅ Extract from AI results
                "error_message": None,
                "generated_task_id": str(created_task.id)  # ✅ Convert UUID to string for Firestore
            }
            
            success = await self.genai_request_repo.update_status(
                id=id,
                status="completed",
                result_data=result_data,
                processing_metadata=processing_metadata
            )
            
            if not success:
                logger.warning(f"Failed to update status for request {id} - possible duplicate")
                return {"status": "duplicate"}
            
            logger.info(f"✅ Quick draft processed successfully: task {created_task.id}, revision history {revision_history.id}")
            
            return {"status": "success"}
            
        except Exception as e:
            logger.error(f"❌ Error processing quick draft: {e}")
            # Update request status to failed
            try:
                await self.genai_request_repo.update_status_with_error(id, "failed", str(e))
            except Exception as update_error:
                logger.error(f"Failed to update error status for request {id}: {update_error}")
            raise

    async def process_revision_response(self, id: str, ai_results: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process draft revision results from cloud function and update task with revision history.
        Called by internal endpoint when revise_message_draft cloud function completes.
        """
        try:
            logger.info(f"✏️ Processing draft revision results for request {id}")
            
            # Get the generation request document using repository (no security check for callbacks)
            request_doc = await self.genai_request_repo.get_generation_request(id, account_id=None)
            if not request_doc:
                raise ValueError(f"GenAI request {id} not found")
            
            user_id = request_doc.get("user_id")
            contact_id = request_doc.get("contact_id")
            
            if not user_id or not contact_id:
                raise ValueError(f"Missing user_id or contact_id in request {id}")
            
            # Check for cloud function success first
            if ai_results.get("success") is False:
                error_message = ai_results.get("error", "Cloud function returned error")
                logger.error(f"Cloud function error for request {id}: {error_message}")
                raise ValueError(f"Cloud function failed: {error_message}")
            
            # Extract task_id from the request_data
            request_data = request_doc.get("request_data", {})
            task_id = request_data.get("task_id")
            revision_instructions = request_data.get("revision_instructions", "")
            
            if not task_id:
                raise ValueError(f"Missing task_id in revise draft request {id}")
            
            # Update task with revised content
            revised_message = ai_results.get("text_message", "")
            if not revised_message:
                # Fallback to check other possible field names
                revised_message = ai_results.get("message", "")
            
            if not revised_message:
                raise ValueError(f"No revised message found in AI results. Available keys: {list(ai_results.keys())}")
            
            update_data = {
                'body': revised_message,
                'updated_by': user_id,
                'updated_on': datetime.utcnow()
            }
            
            updated_task = await self.task_repo.update(
                user_id=user_id,
                contact_id=str(contact_id),
                task_id=task_id,
                update_data=update_data
            )
            
            if not updated_task:
                raise ValueError(f"Failed to update task {task_id}")
            
            # Add revision to history
            revision_history = await self.revision_repo.get_for_task(str(task_id))
            if not revision_history:
                raise ValueError(f"No revision history found for task {task_id}")
            
            # Create revision entry
            from assiist_back_end.models.revision import RevisionEntry
            revision_entry = RevisionEntry(
                revision_instructions=revision_instructions,
                revised_message=revised_message,
                timestamp=datetime.utcnow()
            )
            
            # Append revision to history
            updated_history = await self.revision_repo.append_revision(
                revision_history_id=str(revision_history.id),
                revision_entry=revision_entry
            )
            
            if not updated_history:
                logger.warning(f"Failed to add revision to history {revision_history.id}")
            
            # Update generation request with clean data separation  
            # result_data contains ONLY the pure GenAI output for testing/debugging
            result_data = {
                "revised_message": revised_message
            }
            
            processing_metadata = {
                "llm_provider": ai_results.get("llm_provider", "unknown"),
                "llm_model": ai_results.get("llm_model", "unknown"),
                "processing_time_ms": ai_results.get("processing_time_ms", 0),
                "callback_url": ai_results.get("callback_url"),  # ✅ Extract from AI results
                "error_message": None
            }
            
            success = await self.genai_request_repo.update_status(
                id=id,
                status="completed",
                result_data=result_data,
                processing_metadata=processing_metadata
            )
            
            if not success:
                logger.warning(f"Failed to update status for request {id} - possible duplicate")
                return {"status": "duplicate"}
            
            logger.info(f"✅ Draft revision processed successfully: task {updated_task.id}")
            
            return {"status": "success"}
            
        except Exception as e:
            logger.error(f"❌ Error processing draft revision: {e}")
            # Update request status to failed
            try:
                await self.genai_request_repo.update_status_with_error(id, "failed", str(e))
            except Exception as update_error:
                logger.error(f"Failed to update error status for request {id}: {update_error}")
            raise

    async def process_note_processing_response(self, id: str, ai_results: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process note content results from cloud function and save processed note.
        Called by internal endpoint when get_processed_note cloud function completes.
        
        FIXED: Now gets original note content directly from Firestore since GenerationRequest 
        domain model doesn't support process_note type yet.
        """
        try:
            logger.info(f"📋 Processing note content results for request {id}")
            
            # Get the generation request document using repository (no security check for callbacks)
            timestamp = utc_now().isoformat()
            print(f"[{timestamp}] 🔍 CALLBACK → Looking for GenAI request document {id}")
            
            request_doc = await self.genai_request_repo.get_generation_request(id, account_id=None)
            if not request_doc:
                print(f"[{timestamp}] ❌ CALLBACK → GenAI request {id} NOT FOUND in Firestore")
                raise ValueError(f"GenAI request {id} not found")
            else:
                print(f"[{timestamp}] ✅ CALLBACK → GenAI request {id} found successfully")
            
            user_id = request_doc.get("user_id")
            contact_id = request_doc.get("contact_id")
            
            if not user_id or not contact_id:
                raise ValueError(f"Missing user_id or contact_id in request {id}")
            
            # Check for cloud function success first
            if ai_results.get("success") is False:
                error_message = ai_results.get("error", "Cloud function returned error")
                logger.error(f"Cloud function error for request {id}: {error_message}")
                raise ValueError(f"Cloud function failed: {error_message}")
            
            # Extract processed note data from AI results
            processed_note = ai_results.get("processed_note", {})
            
            if not processed_note:
                raise ValueError("No processed note data found in AI results")
            
            # Extract the AI-processed content
            cleaned_content = processed_note.get("cleaned_content", "")
            key_points = processed_note.get("key_points", [])
            
            # ✅ FIX: Extract original note content from correct location
            request_data = request_doc.get("request_data", {})
            original_note_content = request_data.get("raw_note", "")  # From payload stored in Firestore
            
            if not original_note_content:
                raise ValueError("Original note content not found in request data")
            
            # ✅ FIX: Create structured processed note object
            processed_note = ProcessedNote(
                body=cleaned_content,
                key_points=key_points if isinstance(key_points, list) else []
            )
            
            # ✅ FIX: Create note with proper field names and structure
            note = Note(
                created_by=user_id,
                raw_note=original_note_content,  # ← FIXED: Original content preserved
                processed_note=processed_note,   # ← FIXED: Structured object, not concatenated string
                contact_id=uuid.UUID(contact_id),
                user_id=user_id
            )
            
            # Save note using the repository
            saved_note = await self.note_repo.add(
                user_id=user_id,
                contact_id=str(contact_id),
                note=note
            )
            
            # Update generation request with clean data separation
            # result_data contains ONLY the pure GenAI output for testing/debugging
            result_data = {
                "cleaned_content": cleaned_content,
                "key_points": key_points
            }
            
            processing_metadata = {
                "llm_provider": ai_results.get("llm_provider", "unknown"),
                "llm_model": ai_results.get("llm_model", "unknown"),
                "processing_time_ms": ai_results.get("processing_time_ms", 0),
                "callback_url": ai_results.get("callback_url"),  # ✅ Extract from AI results
                "error_message": None
            }
            
            success = await self.genai_request_repo.update_status(
                id=id,
                status="completed",
                result_data=result_data,
                processing_metadata=processing_metadata
            )
            
            if not success:
                logger.warning(f"Failed to update status for request {id} - possible duplicate")
                return {"status": "duplicate"}
            
            logger.info(f"✅ Note content processed and saved successfully: note {saved_note.id}")
            logger.info(f"📊 Combined {len(cleaned_content)} chars cleaned content with {len(key_points)} key points")
            
            return {"status": "success"}
            
        except Exception as e:
            logger.error(f"❌ Error processing note content: {e}")
            # Update request status to failed
            try:
                await self.genai_request_repo.update_status_with_error(id, "failed", str(e))
            except Exception as update_error:
                logger.error(f"Failed to update error status for request {id}: {update_error}")
            raise

    async def process_update_tasks_response(self, id: str, ai_results: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process task updates from cloud function and save results directly.
        No helper methods - all logic inline for clarity.
        UPDATED: Store only tasks and analysis_tables from ai_results directly in result_data to preserve the GenAI output as-is.
        """
        try:
            logger.info(f"📋 Processing task update results for request {id}")
            
            # Get the generation request document using repository (no security check for callbacks)
            request_doc = await self.genai_request_repo.get_generation_request(id, account_id=None)
            if not request_doc:
                raise ValueError(f"GenAI request {id} not found")
            
            user_id = request_doc.get("user_id")
            contact_id = request_doc.get("contact_id")
            
            if not user_id or not contact_id:
                raise ValueError(f"Missing user_id or contact_id in request {id}")
            
            # Check for cloud function success first
            if ai_results.get("success") is False:
                error_message = ai_results.get("error", "Cloud function returned error")
                logger.error(f"Cloud function error for request {id}: {error_message}")
                raise ValueError(f"Cloud function failed: {error_message}")
            
            # Get account_id
            account_id = await self._get_account_id_for_request(id, user_id, "update_tasks")
            
            # Extract tasks from AI results
            tasks = ai_results.get("tasks", [])
            
            results = {
                "created": [],
                "updated": [],
                "deleted": [],
                "kept": [],
                "errors": [],
                "task_metadata": []  # NEW: Store all task metadata for debugging
            }
            
            # Process each task directly
            for task_data in tasks:
                try:
                    operation = task_data.get("operation", "").lower()
                    
                    # NEW: Extract and store task metadata
                    task_metadata = task_data.get("task_metadata", {})
                    if task_metadata:
                        results["task_metadata"].append({
                            "task_id": task_data.get("id"),
                            "operation": operation,
                            "metadata": task_metadata
                        })
                    
                    if operation == "create":
                        # Create new task
                        # Parse actionable_date and due_date if provided
                        actionable_date = None
                        due_date = None
                        
                        if task_data.get("actionable_date"):
                            try:
                                actionable_date = datetime.fromisoformat(task_data["actionable_date"].replace('Z', '+00:00'))
                            except Exception as e:
                                logger.warning(f"Failed to parse actionable_date: {e}")
                                actionable_date = datetime.now()
                        else:
                            actionable_date = datetime.now()
                            
                        if task_data.get("due_date"):
                            try:
                                due_date = datetime.fromisoformat(task_data["due_date"].replace('Z', '+00:00'))
                            except Exception as e:
                                logger.warning(f"Failed to parse due_date: {e}")
                                due_date = actionable_date
                        else:
                            due_date = actionable_date
                        
                        task = Task(
                            account_id=account_id,
                            user_id=user_id,
                            contact_id=contact_id,
                            title=task_data.get("title", ""),
                            body=task_data.get("body", ""),
                            type=task_data.get("type", "message"),
                            status="pending",
                            assistant_message=task_data.get("assistant_message", ""),
                            created_by=user_id,
                            updated_by=user_id,
                            actionable_date=actionable_date,
                            due_date=due_date
                        )
                        
                        created_task, _ = await self.task_repo.add_with_revision_history(
                            task=task,
                            original_message=task.body or "",
                            context=task_data.get("revision_context", {}),
                            revision_repo=self.revision_repo
                        )
                        
                        results["created"].append({
                            "id": str(created_task.id),
                            "title": created_task.title,
                            "type": created_task.type
                        })
                        
                    elif operation == "edit":
                        # Update existing task
                        task_id = task_data.get("id")
                        if not task_id:
                            results["errors"].append("Edit task missing ID")
                            continue
                        
                        update_data = {}
                        changes_log = {}

                        if "title" in task_data:
                            update_data["title"] = task_data["title"]
                            changes_log["title"] = task_data["title"]
                        if "body" in task_data:
                            update_data["body"] = task_data["body"]
                            changes_log["body"] = task_data["body"]
                        if "assistant_message" in task_data:
                            update_data["assistant_message"] = task_data["assistant_message"]
                            changes_log["assistant_message"] = task_data["assistant_message"]
                        if "actionable_date" in task_data:
                            try:
                                dt = datetime.fromisoformat(task_data["actionable_date"].replace('Z', '+00:00'))
                                update_data["actionable_date"] = dt
                                changes_log["actionable_date"] = dt.isoformat()
                            except Exception as e:
                                logger.warning(f"Failed to parse actionable_date for update: {e}")
                        if "due_date" in task_data:
                            try:
                                dt = datetime.fromisoformat(task_data["due_date"].replace('Z', '+00:00'))
                                update_data["due_date"] = dt
                                changes_log["due_date"] = dt.isoformat()
                                # If due_date is updated but actionable_date isn't, keep them in sync for message tasks
                                if "actionable_date" not in task_data and task_data.get("type") == "message":
                                    update_data["actionable_date"] = update_data["due_date"]
                            except Exception as e:
                                logger.warning(f"Failed to parse due_date for update: {e}")
                        if "type" in task_data:
                            update_data["type"] = task_data["type"]
                            changes_log["type"] = task_data["type"]
                        
                        if not changes_log:
                            # If no actual fields were changed by the AI, treat as "keep"
                            if "title" in task_data:
                                results["kept"].append({"id": task_id, "title": task_data["title"]})
                            else:
                                results["kept"].append({"id": task_id})
                            continue

                        update_data["updated_by"] = user_id
                        update_data["updated_on"] = datetime.utcnow()
                        
                        updated_task = await self.task_repo.update(
                            user_id=user_id,
                            contact_id=str(contact_id),
                            task_id=task_id,
                            update_data=update_data
                        )
                        
                        if updated_task:
                            results["updated"].append({
                                "id": str(updated_task.id),
                                "title": updated_task.title,
                                "changes": changes_log
                            })
                        else:
                            results["errors"].append(f"Failed to update task {task_id}")
                            
                    elif operation == "delete":
                        # Delete task
                        task_id = task_data.get("id")
                        if not task_id:
                            results["errors"].append("Delete task missing ID")
                            continue
                        
                        deleted = await self.task_repo.delete(
                            user_id=user_id,
                            contact_id=str(contact_id),
                            task_id=task_id
                        )
                        
                        if deleted:
                            results["deleted"].append({"id": task_id})
                        else:
                            results["errors"].append(f"Failed to delete task {task_id}")
                    
                    elif operation == "keep":
                        # Keep task as-is (no changes needed)
                        task_id = task_data.get("id")
                        if task_id:
                            results["kept"].append({"id": task_id})
                        else:
                            results["errors"].append("Keep task missing ID")
                            
                    else:
                        results["errors"].append(f"Unknown operation: {operation}")
                        
                except Exception as e:
                    results["errors"].append(f"Error processing task {task_data.get('id', 'unknown')}: {str(e)}")
            
            # Clean up analysis tables to store only essential data
            analysis_tables = ai_results.get("analysis_tables", {})
            essential_analysis_tables = {
                "relationship_table": analysis_tables.get("relationship_table", []),
                "topics_table": analysis_tables.get("topics_table", [])
            }

            # Clean up tasks by removing empty validation fields
            cleaned_tasks = []
            for task in ai_results.get("tasks", []):
                if "task_metadata" in task:
                    if "task_validation" in task["task_metadata"] and not task["task_metadata"]["task_validation"]:
                        del task["task_metadata"]["task_validation"]
                    if "claim_validation" in task["task_metadata"] and not task["task_metadata"]["claim_validation"]:
                        del task["task_metadata"]["claim_validation"]
                cleaned_tasks.append(task)
            
            # Update generation request with clean data separation
            # result_data contains only tasks and analysis_tables from the GenAI output for testing/debugging
            result_data = {
                "tasks": cleaned_tasks,
                "analysis_tables": ai_results.get("analysis_tables", {})
            }
            
            processing_metadata = {
                "llm_provider": ai_results.get("llm_provider", "unknown"),
                "llm_model": ai_results.get("llm_model", "unknown"),
                "processing_time_ms": ai_results.get("processing_time_ms", 0),
                "callback_url": ai_results.get("callback_url"),
                "genai_errors": ai_results.get("error"),
                "task_operations": {
                    "created": results["created"],
                    "updated": results["updated"],
                    "deleted": results["deleted"],
                    "kept": results["kept"]
                },
                "processing_errors": results["errors"]
            }
            
            success = await self.genai_request_repo.update_status(
                id=id,
                status="completed",
                result_data=result_data,
                processing_metadata=processing_metadata
            )
            
            if not success:
                logger.warning(f"Failed to update status for request {id} - possible duplicate")
                return {"status": "duplicate"}
            
            logger.info(f"✅ Task updates processed: {len(results['created'])} created, {len(results['updated'])} updated, {len(results['deleted'])} deleted, {len(results['kept'])} kept, {len(results['errors'])} errors")
            
            return {"status": "success"}
            
        except Exception as e:
            logger.error(f"❌ Error processing task updates: {e}")
            try:
                await self.genai_request_repo.update_status_with_error(id, "failed", str(e))
            except Exception as update_error:
                logger.error(f"Failed to update error status for request {id}: {update_error}")
            raise

    async def process_update_context_response(self, id: str, ai_results: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process context updates from cloud function and update contact directly.
        No helper methods - all logic inline for clarity.
        """
        try:
            logger.info(f"👤 Processing context update results for request {id}")
            
            # DEBUG: Check if ai_results is None
            if ai_results is None:
                logger.error(f"❌ ai_results is None for request {id}")
                raise ValueError(f"AI results are None for request {id}")
            
            logger.info(f"👤 AI results keys: {list(ai_results.keys())}")
            
            # Get the generation request document using repository (no security check for callbacks)
            request_doc = await self.genai_request_repo.get_generation_request(id, account_id=None)
            if not request_doc:
                raise ValueError(f"GenAI request {id} not found")
            
            user_id = request_doc.get("user_id")
            contact_id = request_doc.get("contact_id")
            
            if not user_id or not contact_id:
                raise ValueError(f"Missing user_id or contact_id in request {id}")
            
            # Check for cloud function success first
            if ai_results.get("success") is False:
                error_message = ai_results.get("error", "Cloud function returned error")
                logger.error(f"Cloud function error for request {id}: {error_message}")
                raise ValueError(f"Cloud function failed: {error_message}")
            
            # Extract context updates from AI results (handle None properly)
            context_updates = ai_results.get("context_updates") or {}
            
            # Get account_id and current contact outside of conditional (for result_data)
            account_id = await self._get_account_id_for_request(id, user_id, "update_context")
            current_contact = await self.contact_repo.get_contact_by_id(
                account_id=account_id,
                contact_id=str(contact_id)
            )
            
            if not context_updates:
                results = {
                    "message": "No context updates needed", 
                    "updated_fields": [],
                    "changes": []
                }
            else:
                
                updated_fields = []
                changes = []  # Track specific field changes
                
                # Build update dictionary for the contact repository
                update_data = {}
                
                # Update personal details
                if "personal_details_updates" in context_updates:
                    personal_data = context_updates["personal_details_updates"]
                    update_data["personal_details"] = personal_data
                    # Track changes with full field paths
                    for field_name in personal_data.keys():
                        field_path = f"personal_details.{field_name}"
                        updated_fields.append(field_path)
                        changes.append(field_path)
                
                # Update business details  
                if "business_details_updates" in context_updates:
                    business_data = context_updates["business_details_updates"]
                    update_data["business_details"] = business_data
                    # Track changes with full field paths
                    for field_name in business_data.keys():
                        field_path = f"business_details.{field_name}"
                        updated_fields.append(field_path)
                        changes.append(field_path)
                
                # Update relationship details
                if "relationship_details_updates" in context_updates:
                    raw_relationship_data = context_updates["relationship_details_updates"] or {}
                    # Transform {uid: "string"} -> {uid: {"user_id": uid, "details": string}}
                    relationship_data = {
                        uid: {"user_id": uid, "details": details_str}
                        for uid, details_str in raw_relationship_data.items()
                        if isinstance(details_str, str)
                    }
                    update_data["relationship_details"] = relationship_data
                    # Track changes with full field paths (user-specific)
                    for user_id in relationship_data.keys():
                        field_path = f"relationship_details.{user_id}"
                        updated_fields.append(field_path)
                        changes.append(field_path)
                
                # Actually update the contact using the generic update method
                if update_data:
                    updated_contact = await self.contact_repo.update_contact(
                        account_id=account_id,
                        contact_id=str(contact_id), 
                        updates=update_data,
                        updater_user_id=user_id
                    )
                
                results = {
                    "message": f"Updated {len(updated_fields)} fields",
                    "updated_fields": updated_fields,
                    "changes": changes  # Easy to implement, very useful for debugging/monitoring
                }
            
            # Update generation request with clean data separation
            # result_data contains only the 3 context fields for testing/debugging  
            # Re-extract context_updates to handle None case (cloud function can return null)
            context_updates_for_result = ai_results.get("context_updates") or {}
            request_data = request_doc.get("request_data", {})
            result_data = {
                "personal_details": context_updates_for_result.get("personal_details_updates", {}),
                "business_details": context_updates_for_result.get("business_details_updates", {}),
                "relationship_details": context_updates_for_result.get("relationship_details_updates", {}),
                # Safely include the timezone that was part of the original payload (if any)
                "user_timezone": request_data.get("user_timezone", "UTC"),
            }
            
            processing_metadata = {
                "llm_provider": ai_results.get("llm_provider"),
                "llm_model": ai_results.get("llm_model"),
                "processing_time_ms": ai_results.get("processing_time_ms", 0),
                "callback_url": ai_results.get("callback_url"),  # ✅ Extract from AI results
                "error_message": None
            }
            
            success = await self.genai_request_repo.update_status(
                id=id,
                status="completed",
                result_data=result_data,
                processing_metadata=processing_metadata
            )
            
            if not success:
                logger.warning(f"Failed to update status for request {id} - possible duplicate")
                return {"status": "duplicate"}
            
            logger.info(f"✅ Context updates processed: {results['message']}")
            
            return {"status": "success"}
            
        except Exception as e:
            logger.error(f"❌ Error processing context updates: {e}")
            try:
                await self.genai_request_repo.update_status_with_error(id, "failed", str(e))
            except Exception as update_error:
                logger.error(f"Failed to update error status for request {id}: {update_error}")
            raise

    async def process_transcription_response(self, id: str, ai_results: Dict[str, Any]) -> Dict[str, Any]:
        """Process transcription results and update generation request status."""
        try:
            logger.info(f"🗒️ Processing transcription results for request {id}")

            # Get original request document for metadata
            request_doc = await self.genai_request_repo.get_generation_request(id, account_id=None)

            # Extract transcription text
            transcription_text: str | None = ai_results.get("transcription_text")

            # Validate success
            if ai_results.get("success") is False:
                error_message = ai_results.get("error", "Cloud function returned error")
                raise ValueError(error_message)

            if not transcription_text:
                raise ValueError("transcription_text missing in results")

            # Persist transcription document
            if self.audio_transcription_repo:
                await self.audio_transcription_repo.add(
                    {
                        "id": id,
                        "attachment_id": request_doc.get("request_data", {}).get("attachment_id"),
                        "contact_id": request_doc.get("contact_id"),
                        "user_id": request_doc.get("user_id"),
                        "account_id": request_doc.get("account_id"),
                        "transcription_text": transcription_text,
                        "status": "completed",
                    }
                )

            # Update GenAI request status
            await self.genai_request_repo.update_status(
                id=id,
                status="completed",
                result_data={"transcription_text": transcription_text},
            )

            # --- Trigger enhancement request ---
            insights_id = f"insights_{id}"
            insights_payload = {
                "id": insights_id,
                "transcription_text": transcription_text,
                "contact_id": request_doc.get("contact_id"),
                "user_id": request_doc.get("user_id"),
                "account_id": request_doc.get("account_id"),
                "request_type": "extract_call_insights",
                "callback_url": f"{self.base_url.rstrip('/')}/genai/handle-results",
            }

            # Create Firestore GenAI request doc
            await self.genai_request_repo.create_request(
                id=insights_id,
                request_type="extract_call_insights",
                user_id=insights_payload["user_id"],
                contact_id=str(insights_payload["contact_id"]),
                account_id=insights_payload["account_id"],
                request_data=insights_payload,
            )

            # Call cloud function (to be implemented) for enhancement
            try:
                await self._call_genai_endpoint("extract-call-insights", insights_payload)
            except Exception as e:
                logger.error("Enhancement cloud function failed: %s", e)
             
            return {"status": "success"}

        except Exception as exc:
            logger.error(f"❌ Error processing transcription results: {exc}")
            try:
                await self.genai_request_repo.update_status_with_error(id, "failed", str(exc))
            except Exception as update_error:
                logger.error(f"Failed to mark transcription request {id} as failed: {update_error}")
            raise

    async def process_extract_call_insights_response(self, id: str, ai_results: Dict[str, Any]):
        """Handle insight extraction results, create note with insights and mark request completed."""
        try:
            logger.info(f"📋 Processing call insights for request {id}")

            # Get original request document for metadata
            request_doc = await self.genai_request_repo.get_generation_request(id, account_id=None)
            if not request_doc:
                raise ValueError(f"GenAI request {id} not found")

            user_id = request_doc.get("user_id")
            contact_id = request_doc.get("contact_id")
            
            if not user_id or not contact_id:
                raise ValueError(f"Missing user_id or contact_id in request {id}")

            if ai_results.get("success") is False:
                raise ValueError(ai_results.get("error", "Cloud function error"))

            # Extract insights from AI results
            summary = ai_results.get("summary", "")
            
            if not summary:
                raise ValueError("No summary in AI results")

            # Get the original transcription text from request data
            request_data = request_doc.get("request_data", {})
            transcription_text = request_data.get("transcription_text", "")

            # Create formatted note content with just the summary (no key points bullets)
            note_content_parts = []
            
            # Add call recording header
            note_content_parts.append("--- Call Recording Notes ---")
            
            # Add summary if available
            if summary:
                note_content_parts.append(f"\nSummary:\n{summary}")
            
            # Add original transcription
            if transcription_text:
                note_content_parts.append(f"\nOriginal Transcription:\n{transcription_text}")
            
            formatted_note_content = "\n".join(note_content_parts)

            # Create processed note object with the insights (empty key_points for backward compatibility)
            processed_note = ProcessedNote(
                body=formatted_note_content,
                key_points=[]  # Empty array for backward compatibility
            )

            # Create note with call insights
            note = Note(
                created_by=user_id,
                raw_note=transcription_text,  # Original transcription as raw content
                processed_note=processed_note,  # Formatted insights as processed content
                contact_id=uuid.UUID(contact_id),
                user_id=user_id
            )

            # Save note using the repository
            saved_note = await self.note_repo.add(
                user_id=user_id,
                contact_id=str(contact_id),
                note=note
            )

            # Update genai request status with insights
            await self.genai_request_repo.update_status(
                id=id,
                status="completed",
                result_data={
                    "summary": summary,
                    "note_id": str(saved_note.id)
                },
            )

            # Update corresponding audio_transcription doc so the mobile UI can display insights
            try:
                if self.audio_transcription_repo:
                    # Extract original transcription request ID (strip "insights_" prefix)
                    original_request_id = id.replace("insights_", "", 1)
                    await self.audio_transcription_repo.update_status(
                        id=original_request_id,
                        status="enhanced",
                        update_fields={
                            "summary": summary,
                        },
                    )
            except Exception as upd_exc:
                logger.warning(f"Failed to update audio_transcription {id}: {upd_exc}")

            logger.info(f"✅ Call insights processed and note created: {saved_note.id}")
            logger.info(f"📊 Created note with summary")
            
            return {"status": "success", "note_id": str(saved_note.id)}

        except Exception as exc:
            logger.error(f"Failed to process call insights: {exc}")
            try:
                await self.genai_request_repo.update_status_with_error(id, "failed", str(exc))
            except Exception:
                pass
            raise
  