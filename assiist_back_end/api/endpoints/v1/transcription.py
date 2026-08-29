import uuid
import logging
from typing import Dict, Any, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from dependency_injector.wiring import inject, Provide

from assiist_back_end.containers import Container
from assiist_back_end.api.endpoints.v1.dependencies import verify_firebase_token, UserContext
from assiist_back_end.db.repositories.interfaces.attachment_repository import AttachmentRepository
from assiist_back_end.db.repositories.interfaces.generation_request_repository import GenAIRequestRepository
from assiist_back_end.services.cloud_functions import call_function

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Pydantic Schemas
# ---------------------------------------------------------------------------

class TranscriptionRequestSchema(BaseModel):
    contact_id: str = Field(..., description="Contact the note belongs to")
    attachment_id: str = Field(..., description="Attachment ID pointing to the uploaded audio file")
    language: Optional[str] = Field(None, description="Optional hint language code, e.g. 'en' or 'es'")


class TranscriptionAcceptedResponseSchema(BaseModel):
    id: str
    status: str = "pending"
    message: str
    contact_id: str
    attachment_id: str
    estimated_completion_time: str


# ---------------------------------------------------------------------------
# Router
# ---------------------------------------------------------------------------

router = APIRouter(prefix="/transcription", tags=["Transcription"], dependencies=[Depends(verify_firebase_token)])


@router.post(
    "/transcribe-audio",
    response_model=TranscriptionAcceptedResponseSchema,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Request transcription of an uploaded audio attachment (async)",
)
@inject
async def request_transcription(
    transcription_request: TranscriptionRequestSchema,
    user_ctx: UserContext = Depends(verify_firebase_token),
    attachment_repo: AttachmentRepository = Depends(Provide[Container.attachment_repository]),
    genai_request_repo: GenAIRequestRepository = Depends(Provide[Container.genai_request_repository]),
):
    """Initiate transcription by calling the `transcribe_audio` Cloud Function."""

    # Fetch attachment metadata to get public URL
    attachment = await attachment_repo.get_by_id(user_ctx.user_id, transcription_request.attachment_id)
    if not attachment:
        raise HTTPException(status_code=404, detail="Attachment not found")

    # Basic MIME check to ensure it's audio
    if not attachment.file_type.startswith("audio/"):
        raise HTTPException(status_code=400, detail="Attachment is not an audio file")

    transcription_id = str(uuid.uuid4())

    payload: Dict[str, Any] = {
        "id": transcription_id,
        "audio_url": attachment.public_url,
        "user_id": user_ctx.user_id,
        "contact_id": transcription_request.contact_id,
        "account_id": user_ctx.account_id,
        "language": transcription_request.language or "auto",
        "request_type": "transcription",
        # Callback URL for function to POST back results (re-use existing handler)
        "callback_url": f"{Container().config().API_URL.rstrip('/')}/genai/handle-results",
    }

    try:
        # Record generation request in Firestore for tracking
        await genai_request_repo.create_request(
            id=transcription_id,
            request_type="transcription",
            user_id=user_ctx.user_id,
            contact_id=transcription_request.contact_id,
            account_id=user_ctx.account_id,
            request_data={
                "attachment_id": transcription_request.attachment_id,
                "audio_url": attachment.public_url,
                "language": transcription_request.language or "auto",
            },
        )

        cloud_response = await call_function("transcribe_audio", payload, region="us-central1")
        if cloud_response.get("success") is False:
            logger.error("Cloud function error: %s", cloud_response.get("error"))
            raise HTTPException(status_code=502, detail="Cloud function failed to start transcription")
    except Exception as exc:
        logger.exception("Failed to call Cloud Function: %s", exc)
        raise HTTPException(status_code=502, detail="Unable to call Cloud Function")

    return TranscriptionAcceptedResponseSchema(
        id=transcription_id,
        contact_id=transcription_request.contact_id,
        attachment_id=transcription_request.attachment_id,
        message="Transcription request submitted successfully",
        estimated_completion_time="1-3 minutes",
    ) 