import uuid
from fastapi import APIRouter, Depends, HTTPException, status, Response, Body, Request
from dependency_injector.wiring import inject, Provide
from firebase_admin import firestore
from datetime import datetime
from typing import Dict, Any, Optional, List
import logging
import secrets

# Container
from assiist_back_end.containers import Container

# Schemas  
from assiist_back_end.api.schemas.generation import GenerationAcceptedResponseSchema
from assiist_back_end.api.schemas.revision_unified import (
    RevisionRequestSchema, 
    QuickDraftRequestSchema, 
    AssistantResponseSchema
)
from assiist_back_end.models.generation import GenerationRequest, QuickDraftRequest, ReviseDraftRequest

from assiist_back_end.db.repositories.interfaces.task_repository import TaskRepository
from assiist_back_end.api.endpoints.v1.dependencies import verify_firebase_token, UserContext
from assiist_back_end.services.assistant_service import AssistantService
from assiist_back_end.services.genai_service import GenAIUtilities

# Assistant schemas
from assiist_back_end.api.schemas.assistant import (
    QuickActionsRequestSchema,
    ProcessNoteRequest,
    ProcessNoteResponse
)

logger = logging.getLogger(__name__)

# Create the assistant router
router = APIRouter(
    prefix="/assistant",
    tags=["AI Assistant"]  # Per-endpoint dependencies are defined individually below
)

@router.post(
    "/quick-actions",
    response_model=GenerationAcceptedResponseSchema,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Unified endpoint for quick drafts and revisions with canonical data models"
)
@inject
async def quick_actions(
    request_body: QuickActionsRequestSchema,
    response: Response,
    user_ctx: UserContext = Depends(verify_firebase_token),
    assistant_service: AssistantService = Depends(Provide[Container.assistant_service])
):
    """
    REFACTORED: Simplified approach - frontend only shows user's own tasks, so no validation needed.
    AssistantService handles all business logic including task fetching and validation.
    """
    timestamp = datetime.utcnow().isoformat()
    print(f"[{timestamp}] 🚀 FRONTEND → Quick Actions: {request_body.request_type} for contact {request_body.contact_id}")
    
    # Validate request type and required fields
    if request_body.request_type == "quick_draft":
        if not request_body.message_instructions:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="message_instructions is required for quick_draft requests"
            )
    elif request_body.request_type == "revise_draft":
        if not all([request_body.task_id, request_body.revision_instructions]):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="task_id and revision_instructions are required for revise_draft requests"
            )
        # REMOVED: Task validation - frontend only shows user's own tasks
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid request_type: {request_body.request_type}. Must be 'quick_draft' or 'revise_draft'"
        )

    try:
        # Route to AssistantService following documented flow
        if request_body.request_type == "quick_draft":
            # Generate request ID
            id = str(uuid.uuid4())
            
            # Create request data for service layer - NO Firestore document creation here
            request_data = {
                "id": id,  # Pass the ID to service layer
                "request_type": "quick_draft",
                "contact_id": request_body.contact_id,
                "message_instructions": request_body.message_instructions,
                "message_language": request_body.message_language,
                "account_id": user_ctx.account_id,
                "user_id": user_ctx.user_id  # Pass user_id for service layer
            }
            
            # AssistantService creates Firestore document (pending status) + calls GenAI endpoints
            result = await assistant_service.handle_generation_request(id, request_data)
            
            response_obj = GenerationAcceptedResponseSchema(
                id=id,
                status="pending",
                message="Quick draft request submitted successfully",
                contact_id=str(request_body.contact_id),
                instructions=request_body.message_instructions,
                language=request_body.message_language,
                estimated_completion_time="10-30 seconds",
                next_steps=[
                    "AI is analyzing your request",
                    "Generating message content", 
                    "Creating task with results",
                    "You'll be notified when ready"
                ]
            )
            
            # DEBUG: Log the exact response being sent to frontend
            timestamp = datetime.utcnow().isoformat()
            print(f"[{timestamp}] 🔍 DEBUG → Response object dict: {response_obj.dict()}")
            print(f"[{timestamp}] 🔍 DEBUG → Response object JSON: {response_obj.json()}")
            
            return response_obj
            
        else:  # revise_draft
            # Generate request ID
            id = str(uuid.uuid4())
            
            # Create request data for service layer - NO Firestore document creation here
            request_data = {
                "id": id,  # Pass the ID to service layer
                "request_type": "revise_draft",
                "contact_id": request_body.contact_id,
                "task_id": request_body.task_id,
                "revision_instructions": request_body.revision_instructions,
                "message_language": request_body.message_language,
                "account_id": user_ctx.account_id,
                "user_id": user_ctx.user_id  # Pass user_id for service layer
            }
            
            # AssistantService creates Firestore document (pending status) + calls GenAI endpoints
            result = await assistant_service.handle_generation_request(id, request_data)
            
            response_obj = GenerationAcceptedResponseSchema(
                id=id,
                status="pending",
                message="Revision request submitted successfully",
                contact_id=str(request_body.contact_id),
                instructions=request_body.revision_instructions,
                language=request_body.message_language,
                estimated_completion_time="10-30 seconds",
                next_steps=[
                    "AI is analyzing your revision instructions",
                    "Generating revised message content", 
                    "Updating task with results",
                    "You'll be notified when ready"
                ]
            )
            
            # DEBUG: Log the exact response being sent to frontend
            timestamp = datetime.utcnow().isoformat()
            print(f"[{timestamp}] 🔍 DEBUG → Response object dict: {response_obj.dict()}")
            print(f"[{timestamp}] 🔍 DEBUG → Response object JSON: {response_obj.json()}")
            
            return response_obj

    except Exception as e:
        print(f"❌ Error creating {request_body.request_type} request: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create {request_body.request_type} request: {e}"
        )

@router.post(
    "/update-assistant",
    response_model=ProcessNoteResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
@inject
async def update_assistant(
    request_body: ProcessNoteRequest,
    raw_request: Request,
    assistant_service: AssistantService = Depends(Provide[Container.assistant_service]),
):
    """
    Frontend interface for Update Assistant.
    Delegates all processing to AssistantService orchestrator.
    
    Creates 3 parallel AI operations:
    1. update_tasks - AI analysis for task updates  
    2. update_context - AI analysis for context updates
    3. process_note - AI processing of note content
    """
    try:
        from assiist_back_end.config import Settings

        settings = Settings()

        # ------------------------------------------------------------------
        # AUTHENTICATION   (support two modes)
        # 1. Front-end → Bearer <Firebase ID Token>
        # 2. Internal service → X-Internal-API-Key header + user/account IDs in body
        # ------------------------------------------------------------------

        internal_key = raw_request.headers.get("X-Internal-API-Key")

        if internal_key and secrets.compare_digest(
            internal_key, settings.ASSIIST_API_KEY.get_secret_value()
        ):
            # INTERNAL CALL – expect user/account IDs in the payload
            user_id = request_body.user_id
            account_id = request_body.account_id

            if not (user_id and account_id):
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="user_id and account_id are required for internal Update-Assistant calls.",
                )

        else:
            # EXTERNAL CALL – must include valid Firebase token
            from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
            bearer_scheme = HTTPBearer(auto_error=False)

            credentials: HTTPAuthorizationCredentials | None = await bearer_scheme(raw_request)

            if not credentials or credentials.scheme.lower() != "bearer":
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Missing or invalid authentication credentials.",
                )

            # Re-use existing dependency for verification
            from assiist_back_end.containers import Container as _Container
            db_client = _Container().firestore_async_client()
            settings_dep = _Container().config()
            user_ctx = await verify_firebase_token(
                credentials=credentials, db=db_client, settings=settings_dep
            )

            user_id = user_ctx.user_id
            account_id = user_ctx.account_id

        # Determine timezone from payload or user context (default UTC)
        user_timezone = request_body.user_timezone or (
            getattr(user_ctx, "timezone", None) if "user_ctx" in locals() else None
        ) or "UTC"

        logger.info(
            f"🤖 Update Assistant request received (contact {request_body.contact_id}) – auth_mode={'internal' if internal_key else 'firebase'} tz={user_timezone}"
        )
        
        # Determine requested note type (user vs system) so we can optionally bypass note processing
        note_type = request_body.note_type or "user"

        # Always create IDs for task/context operations
        task_request_id = str(uuid.uuid4())
        context_request_id = str(uuid.uuid4())

        # Only generate a note_request_id if we intend to run note processing
        note_request_id: str | None = None
        if note_type != "system":
            note_request_id = str(uuid.uuid4())

        # Prepare request data for service layer
        request_data = {
            "user_id": user_id,
            "contact_id": request_body.contact_id,
            "account_id": account_id,
            "note_content": request_body.note_content,
            "context": request_body.context or {},
            "user_timezone": user_timezone,
            "task_request_id": task_request_id,
            "context_request_id": context_request_id,
            # note_request_id is optional when skipping note processing
            **({"note_request_id": note_request_id} if note_request_id else {}),
            "note_type": note_type,
            "skip_note_processing": note_type == "system",
        }
        
        # Delegate to service orchestrator
        result = await assistant_service.process_update_assistant_request(request_data)
        
        # Return standardized response
        return ProcessNoteResponse(
            success=result["success"],
            request_ids=result["request_ids"],
            message=result["message"],
            estimated_completion_time=result["estimated_completion_time"],
            next_steps=[
                "AI is analyzing note content with full historical context for task opportunities",
                "AI is extracting personal and business context updates with relationship history", 
                "AI is cleaning and structuring the note content with contact knowledge",
                "Each operation has access to comprehensive notes, tasks, and appointments history",
                "You'll receive real-time updates as each completes"
            ]
        )
        
    except Exception as e:
        logger.error(f"❌ Error in update assistant endpoint: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to process Update Assistant request: {str(e)}"
        ) 