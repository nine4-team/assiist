from fastapi import APIRouter, Depends, HTTPException, status, Path, Response, Body
from dependency_injector.wiring import inject, Provide
import os
import httpx
import logging
import json
from datetime import datetime
import asyncio
from typing import Dict, Any, Optional, List

# Create logger instance
logger = logging.getLogger(__name__)

# Container
from assiist_back_end.containers import Container

# Schemas
from assiist_back_end.api.schemas.generation import GenerationAcceptedResponseSchema
from assiist_back_end.api.schemas.update_assistant import (
    UpdateTasksRequestSchema,
    UpdateContextRequestSchema,
    ProcessNoteRequestSchema,
    UpdateAssistantAcceptedResponseSchema,
    UpdateTasksCloudFunctionResponseSchema,
    UpdateContextCloudFunctionResponseSchema,
    ProcessNoteCloudFunctionResponseSchema
)
from assiist_back_end.models.generation import QuickDraftRequest, ReviseDraftRequest, GenerationRequest, GenerationRequestType

from assiist_back_end.api.endpoints.v1.dependencies import verify_internal_secret
from assiist_back_end.models.task import Task, TaskType, TaskStatus

# Repository interfaces (using standard dependency injection)
# Note: Repository dependencies should be injected via Depends(Provide[Container.repository])
# instead of using factory functions
from assiist_back_end.db.repositories.interfaces.revision_repository import RevisionHistoryRepository
from assiist_back_end.db.repositories.interfaces.generation_request_repository import GenAIRequestRepository

# NOTE: Context retrieval now handled by AssistantService using genai_service.py
# GenAI endpoints only handle API routing and cloud function calls

# Import assistant service for callback handling
from assiist_back_end.services.assistant_service import AssistantService

# Standard Public API Pattern: All endpoints require callback_url parameter from caller

# Router for GenAI endpoints

# Single clean GenAI router following implementation guide
router = APIRouter(
    prefix="/genai",
    tags=["GenAI"]
)


# === STANDARD PUBLIC API PATTERN FOR ALL ENDPOINTS ===

@router.post(
    "/update-tasks",
    response_model=GenerationAcceptedResponseSchema,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Request AI analysis for task updates (Asynchronous)",
    dependencies=[Depends(verify_internal_secret)]
)
@inject
async def request_update_tasks(
    request_body: dict,  # Accept raw dict to handle callback_url parameter
    response: Response,
):
    """Standard public API pattern: requires callback_url parameter from caller."""
    
    # Validate required callback_url parameter (public API standard)
    callback_url = request_body.get("callback_url")
    if not callback_url:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="callback_url parameter required for async operations"
        )
    
    # Use provided ID from AssistantService (internal orchestration pattern)
    id = request_body.get("id")
    if not id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing required field 'id' in request"
        )
    
    timestamp = datetime.utcnow().isoformat()
    print(f"[{timestamp}] 🤖 GENAI: Starting update-tasks request {id}")
    print(f"[{timestamp}] 🔗 Callback URL: {callback_url}")
    
    try:
        # Call cloud function with provided callback URL
        from assiist_back_end.services.cloud_functions import call_function
        
        cloud_response = await call_function(
            function_name="update_tasks",
            data=request_body,
            region="us-central1"
        )
        
        print(f"[{timestamp}] 📡 Cloud function response: {cloud_response.get('success', 'NOT_SPECIFIED')}")
        
        if cloud_response.get("success") is False:
            error_message = cloud_response.get('error', 'Cloud function call failed')
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Cloud function failed: {error_message}"
            )
        
        print(f"[{timestamp}] ✅ Update-tasks request {id} submitted to cloud function")
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[{timestamp}] ❌ Error calling cloud function: {e}")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to call cloud function: {str(e)}"
        )

    return GenerationAcceptedResponseSchema(
        id=id,
        status="pending",
        message="Update tasks request submitted successfully for AI processing",
        contact_id=str(request_body.get("contact_id", "")),
        instructions=request_body.get("raw_note", "")[:100],
        language=request_body.get("message_language", "english"),
        estimated_completion_time="30-60 seconds",
        next_steps=[
            "AI is analyzing the note content with comprehensive historical context",
            "Identifying task creation and update opportunities using past notes and tasks",
            "Generating task recommendations informed by relationship history",
            "Updates will be applied automatically"
        ]
    )

@router.post(
    "/update-context",
    response_model=GenerationAcceptedResponseSchema,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Request AI analysis for context updates (Asynchronous)",
    dependencies=[Depends(verify_internal_secret)]
)
@inject
async def request_update_context(
    request_body: dict,  # Accept raw dict to handle callback_url parameter
    response: Response,
):
    """Standard public API pattern: requires callback_url parameter from caller."""
    
    # Validate required callback_url parameter (public API standard)
    callback_url = request_body.get("callback_url")
    if not callback_url:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="callback_url parameter required for async operations"
        )
    
    # Use provided ID from AssistantService (internal orchestration pattern)
    id = request_body.get("id")
    if not id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing required field 'id' in request"
        )
    
    timestamp = datetime.utcnow().isoformat()
    print(f"[{timestamp}] 🤖 GENAI: Starting update-context request {id}")
    print(f"[{timestamp}] 🔗 Callback URL: {callback_url}")
    
    try:
        # Call cloud function with provided callback URL
        from assiist_back_end.services.cloud_functions import call_function
        
        cloud_response = await call_function(
            function_name="update_context",
            data=request_body,
            region="us-central1"
        )
        
        print(f"[{timestamp}] 📡 Cloud function response: {cloud_response.get('success', 'NOT_SPECIFIED')}")
        
        if cloud_response.get("success") is False:
            error_message = cloud_response.get('error', 'Cloud function call failed')
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Cloud function failed: {error_message}"
            )
        
        print(f"[{timestamp}] ✅ Update-context request {id} submitted to cloud function")
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[{timestamp}] ❌ Error calling cloud function: {e}")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to call cloud function: {str(e)}"
        )

    return GenerationAcceptedResponseSchema(
        id=id,
        status="pending",
        message="Update context request submitted successfully for AI processing",
        contact_id=str(request_body.get("contact_id", "")),
        instructions=request_body.get("raw_note", "")[:100],
        language=request_body.get("message_language", "english"),
        estimated_completion_time="30-60 seconds",
        next_steps=[
            "AI is analyzing the note content with comprehensive relationship history",
            "Extracting personal and business details using past interaction patterns",
            "Identifying relationship updates informed by appointment and note history",
            "Updates will be applied automatically"
        ]
    )

@router.post(
    "/process-note",
    response_model=GenerationAcceptedResponseSchema,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Request AI processing of note content (Asynchronous)",
    dependencies=[Depends(verify_internal_secret)]
)
@inject
async def request_process_note(
    request_body: dict,  # Accept raw dict to handle callback_url parameter
    response: Response,
):
    """Standard public API pattern: requires callback_url parameter from caller."""
    
    # Validate required callback_url parameter (public API standard)
    callback_url = request_body.get("callback_url")
    if not callback_url:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="callback_url parameter required for async operations"
        )
    
    # Use provided ID from AssistantService (internal orchestration pattern)
    id = request_body.get("id")
    if not id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing required field 'id' in request"
        )
    
    timestamp = datetime.utcnow().isoformat()
    print(f"[{timestamp}] 🤖 GENAI: Starting process-note request {id}")
    print(f"[{timestamp}] 🔗 Callback URL: {callback_url}")
    
    try:
        # Call cloud function with provided callback URL
        from assiist_back_end.services.cloud_functions import call_function
        
        cloud_response = await call_function(
            function_name="get_processed_note",
            data=request_body,
            region="us-central1"
        )
        
        print(f"[{timestamp}] 📡 Cloud function response: {cloud_response.get('success', 'NOT_SPECIFIED')}")
        
        if cloud_response.get("success") is False:
            error_message = cloud_response.get('error', 'Cloud function call failed')
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Cloud function failed: {error_message}"
            )
        
        print(f"[{timestamp}] ✅ Process-note request {id} submitted to cloud function")
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[{timestamp}] ❌ Error calling cloud function: {e}")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to call cloud function: {str(e)}"
        )

    return GenerationAcceptedResponseSchema(
        id=id,
        status="pending",
        message="Process note request submitted successfully for AI processing",
        contact_id=str(request_body.get("contact_id", "")),
        instructions=request_body.get("raw_note", "")[:100],
        language=request_body.get("message_language", "english"),
        estimated_completion_time="10-30 seconds",
        next_steps=[
            "AI is analyzing the note content with full contact knowledge",
            "Cleaning and structuring the text using relationship context",
            "Extracting key points informed by interaction history",
            "Processed note will be available shortly"
        ]
    )

@router.post(
    "/quick-draft",
    response_model=GenerationAcceptedResponseSchema,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Request AI generation of a quick message draft (Asynchronous)",
    dependencies=[Depends(verify_internal_secret)]
)
@inject
async def request_quick_draft(
    request_body: dict,  # Accept raw dict to handle callback_url parameter
    response: Response,
):
    """Standard public API pattern: requires callback_url parameter from caller."""
    
    # Validate required callback_url parameter (public API standard)
    callback_url = request_body.get("callback_url")
    if not callback_url:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="callback_url parameter required for async operations"
        )
    
    # Validate required fields
    id = request_body.get("id")
    instructions = request_body.get("message_instructions")
    
    if not id:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Missing required field 'id' in quick draft request"
        )
    
    if not instructions:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Missing required field 'message_instructions' in quick draft request"
        )

    timestamp = datetime.utcnow().isoformat()
    print(f"[{timestamp}] 🤖 GENAI: Starting quick-draft request {id}")
    print(f"[{timestamp}] 🔗 Callback URL: {callback_url}")
    
    try:
        # Call cloud function with provided callback URL
        from assiist_back_end.services.cloud_functions import call_function
        
        cloud_response = await call_function(
            function_name="get_quick_draft",
            data=request_body,
            region="us-central1"
        )
        
        print(f"[{timestamp}] 📡 Cloud function response: {cloud_response.get('success', 'NOT_SPECIFIED')}")
        
        if cloud_response.get("success") is False:
            error_message = cloud_response.get('error', 'Cloud function call failed')
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Cloud function failed: {error_message}"
            )
        
        print(f"[{timestamp}] ✅ Quick-draft request {id} submitted to cloud function")
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[{timestamp}] ❌ Error calling cloud function: {e}")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to call cloud function: {str(e)}"
        )

    return GenerationAcceptedResponseSchema(
        id=id,
        status="pending",
        message="Quick draft request submitted successfully for AI processing",
        contact_id=str(request_body.get("contact_id", "")),
        instructions=instructions,
        language=request_body.get("message_language", "english"),
        estimated_completion_time="10-30 seconds",
        next_steps=[
            "AI is analyzing your instructions with canonical data model",
            "Generating personalized message content",
            "Creating task with draft content",
            "You'll be notified when ready"
        ]
    )

@router.post(
    "/revise-draft",
    response_model=GenerationAcceptedResponseSchema,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Request AI revision of a message draft (Asynchronous)",
    dependencies=[Depends(verify_internal_secret)]
)
@inject
async def request_revision(
    request_body: dict,  # Accept raw dict to handle callback_url parameter
    response: Response,
):
    """Standard public API pattern: requires callback_url parameter from caller."""
    
    # Validate required callback_url parameter (public API standard)
    callback_url = request_body.get("callback_url")
    if not callback_url:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="callback_url parameter required for async operations"
        )
    
    # Use provided ID from AssistantService (internal orchestration pattern)
    id = request_body.get("id")
    if not id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing required field 'id' in request"
        )
    
    timestamp = datetime.utcnow().isoformat()
    print(f"[{timestamp}] 🤖 GENAI: Starting revise-draft request {id}")
    print(f"[{timestamp}] 🔗 Callback URL: {callback_url}")
    
    try:
        # Call cloud function with provided callback URL
        from assiist_back_end.services.cloud_functions import call_function
        
        cloud_response = await call_function(
            function_name="revise_message_draft",
            data=request_body,
            region="us-central1"
        )
        
        print(f"[{timestamp}] 📡 Cloud function response: {cloud_response.get('success', 'NOT_SPECIFIED')}")
        
        if cloud_response.get("success") is False:
            error_message = cloud_response.get('error', 'Cloud function call failed')
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Cloud function failed: {error_message}"
            )
        
        print(f"[{timestamp}] ✅ Revise-draft request {id} submitted to cloud function")
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[{timestamp}] ❌ Error calling cloud function: {e}")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to call cloud function: {str(e)}"
        )

    return GenerationAcceptedResponseSchema(
        id=id,
        status="pending",
        message="Revision request submitted successfully for AI processing",
        contact_id=str(request_body.get("contact_id", "")),
        instructions=request_body.get("revision_instructions", ""),
        language=request_body.get("message_language", "english"),
        estimated_completion_time="10-30 seconds",
        next_steps=[
            "AI is analyzing your revision instructions with canonical data model",
            "Revising message content based on feedback",
            "Updating task with revised draft content",
            "You'll be notified when ready"
        ]
    )

@router.post(
    "/extract-call-insights",
    response_model=GenerationAcceptedResponseSchema,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Request AI extraction of call insights from transcription (Asynchronous)",
    dependencies=[Depends(verify_internal_secret)]
)
@inject
async def request_extract_call_insights(
    request_body: dict,  # Accept raw dict to handle callback_url parameter
    response: Response,
):
    """Standard public API pattern: requires callback_url parameter from caller."""
    
    # Validate required callback_url parameter (public API standard)
    callback_url = request_body.get("callback_url")
    if not callback_url:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="callback_url parameter required for async operations"
        )
    
    # Use provided ID from AssistantService (internal orchestration pattern)
    id = request_body.get("id")
    if not id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing required field 'id' in request"
        )
    
    timestamp = datetime.utcnow().isoformat()
    print(f"[{timestamp}] 🤖 GENAI: Starting extract-call-insights request {id}")
    print(f"[{timestamp}] 🔗 Callback URL: {callback_url}")
    
    try:
        # Call cloud function with provided callback URL
        from assiist_back_end.services.cloud_functions import call_function
        
        cloud_response = await call_function(
            function_name="extract_call_insights",
            data=request_body,
            region="us-central1"
        )
        
        print(f"[{timestamp}] 📡 Cloud function response: {cloud_response.get('success', 'NOT_SPECIFIED')}")
        
        if cloud_response.get("success") is False:
            error_message = cloud_response.get('error', 'Cloud function call failed')
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Cloud function failed: {error_message}"
            )
        
        print(f"[{timestamp}] ✅ Extract-call-insights request {id} submitted to cloud function")
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[{timestamp}] ❌ Error calling cloud function: {e}")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to call cloud function: {str(e)}"
        )

    return GenerationAcceptedResponseSchema(
        id=id,
        status="pending",
        message="Extract call insights request submitted successfully for AI processing",
        contact_id=str(request_body.get("contact_id", "")),
        instructions=request_body.get("transcription_text", "")[:100],
        language=request_body.get("message_language", "english"),
        estimated_completion_time="10-30 seconds",
        next_steps=[
            "AI is analyzing the transcription text",
            "Extracting key insights and action items",
            "Summarizing call content",
            "Results will be available shortly"
        ]
    )

# --- CALLBACK ENDPOINT ---
@router.post("/handle-results")
@inject
async def handle_ai_results(
    request_data: dict,
    assistant_service: AssistantService = Depends(Provide[Container.assistant_service]),
    genai_repo: GenAIRequestRepository = Depends(Provide[Container.genai_request_repository]),
):
    """
    Handle AI results from cloud functions.
    Called by cloud functions when AI processing completes.
    This is the callback endpoint that receives AI results and processes them.
    """
    try:
        # DEBUG: Log incoming callback data
        timestamp = datetime.utcnow().isoformat()
        print(f"[{timestamp}] 🔄 CALLBACK → Received data keys: {list(request_data.keys()) if request_data else 'None'}")
        
        if not request_data:
            print(f"[{timestamp}] ❌ CALLBACK → request_data is None or empty!")
            raise HTTPException(status_code=400, detail="Request data is None or empty")
        
        id = request_data.get("id")
        if not id:
            print(f"[{timestamp}] ❌ CALLBACK → Missing 'id' field in request_data")
            raise HTTPException(status_code=400, detail="Missing id")
        
        print(f"[{timestamp}] 🔄 CALLBACK → Processing request {id}")
        
        # DETECT FORMAT: Cloud function callback vs old Firestore trigger
        if "request_data" in request_data:
            # OLD FORMAT: From Firestore trigger (now disabled)
            firestore_data = request_data["request_data"]
            request_type = firestore_data.get("request_type", "quick_draft")
            print(f"[{timestamp}] 🔄 CALLBACK → OLD FORMAT detected: {request_type}")
            
            # Route to assistant service to handle the generation request from Firestore data
            return await assistant_service.handle_generation_request(id, firestore_data)
            
        else:
            # NEW FORMAT: From cloud function callback
            request_type = request_data.get("request_type") or request_data.get("type")

            # If cloud function didn't include type, fall back to Firestore doc
            if not request_type:
                try:
                    req_doc = await genai_repo.get_generation_request(id)
                    request_type = req_doc.get("request_type") if req_doc else None
                except Exception as fetch_exc:
                    print(f"[{timestamp}] ⚠️  CALLBACK → Failed to fetch request doc for {id}: {fetch_exc}")

            # Still default if we couldn't determine
            if not request_type:
                request_type = "quick_draft"

            print(f"[{timestamp}] 🔄 CALLBACK → NEW FORMAT detected: {request_type}")
            print(f"[{timestamp}] 🔄 CALLBACK → Full request data: {request_data}")
            
            # Extract AI results (everything except metadata)
            ai_results = {k: v for k, v in request_data.items() 
                         if k not in ["id", "request_type", "type", "callback_url"]}
            
            print(f"[{timestamp}] 🔄 CALLBACK → AI results keys: {list(ai_results.keys())}")
            
            # Route to appropriate processing method
            if request_type == "quick_draft":
                result = await assistant_service.process_quick_draft_response(id, ai_results)
            elif request_type == "revise_draft":
                result = await assistant_service.process_revision_response(id, ai_results)
            elif request_type == "update_tasks":
                result = await assistant_service.process_update_tasks_response(id, ai_results)
            elif request_type == "update_context":
                result = await assistant_service.process_update_context_response(id, ai_results)
            elif request_type == "process_note":
                result = await assistant_service.process_note_processing_response(id, ai_results)
            elif request_type == "transcription":
                result = await assistant_service.process_transcription_response(id, ai_results)
            elif request_type == "extract_call_insights":
                result = await assistant_service.process_extract_call_insights_response(id, ai_results)
            else:
                raise ValueError(f"Unknown request type: {request_type}")
        return {"success": True, "message": f"Successfully processed {request_type} results"}
            
    except Exception as e:
        logger.error(f"❌ AI callback processing failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/requests")
@inject
async def get_genai_requests(
    request_type: Optional[str] = None,
    request_status: Optional[str] = None,
    search: Optional[str] = None,
    repo: GenAIRequestRepository = Depends(Provide[Container.genai_request_repository])
) -> List[Dict[str, Any]]:
    """Get all GenAI requests with optional filters"""
    try:
        logger.info(f"Fetching GenAI requests with filters: type={request_type}, status={request_status}, search={search}")
        requests = await repo.get_by_account(
            account_id=None,
            request_type=request_type,
            status=request_status
        )
        logger.info(f"Retrieved {len(requests)} GenAI requests")
        return requests
    except Exception as e:
        logger.error(f"Failed to fetch GenAI requests: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch GenAI requests: {str(e)}"
        )

@router.get("/requests/{request_id}")
@inject
async def get_genai_request_by_id(
    request_id: str,
    repo: GenAIRequestRepository = Depends(Provide[Container.genai_request_repository])
) -> Dict[str, Any]:
    """Get single GenAI request by ID"""
    try:
        request = await repo.get_generation_request(request_id)
        if not request:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="GenAI request not found"
            )
        return request
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch GenAI request: {str(e)}"
        )

# Clean single router following implementation guide
# All endpoints now under /api/v1/genai/ as per guide