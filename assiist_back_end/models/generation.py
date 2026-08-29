import uuid
from datetime import datetime
from typing import Optional, Literal, Dict, Any, Union, List

from pydantic import BaseModel, Field

# Define possible request statuses
GenerationRequestStatus = Literal["pending", "processing", "completed", "failed"]
GenerationRequestType = Literal["quick_draft", "revise_draft"]

class BaseGenerationRequest(BaseModel):
    id: str = Field(..., description="Unique request ID, likely a UUID string.")
    user_id: str = Field(..., description="The ID of the user who made the request.")
    contact_id: uuid.UUID = Field(..., description="The ID of the contact the request pertains to.")
    status: GenerationRequestStatus = Field(default="pending", description="The current processing status.")
    language: str = Field(..., description="The language requested for the message.")
    
    # Timestamps
    requested_on: datetime = Field(default_factory=datetime.utcnow, description="Timestamp when the request was received.")
    processed_on: Optional[datetime] = Field(None, description="Timestamp when processing finished (successfully or not).")
    
    # Result linking/Error info
    result_task_id: Optional[str] = Field(None, description="The ID of the generated Task document if successful.")
    result_task_data: Optional[Dict[str, Any]] = Field(None, description="The complete Task data including generated message if successful.")
    error_message: Optional[str] = Field(None, description="Details if processing failed.")

    class Config:
        from_attributes = True

class QuickDraftRequest(BaseGenerationRequest):
    request_type: Literal["quick_draft"] = "quick_draft"
    instructions: str = Field(..., description="The core instructions provided by the user for generating a new draft.")

class ReviseDraftRequest(BaseGenerationRequest):
    request_type: Literal["revise_draft"] = "revise_draft"
    task_id: str = Field(..., description="The ID of the task being revised.")
    message_draft: str = Field(..., description="The current message draft to revise.")
    instructions: str = Field(..., description="Instructions for revising the existing draft.")
    message_language: Optional[str] = Field("English", description="Language for the message")
    language_examples: Optional[List[str]] = Field(default_factory=list, description="Examples of the user's writing style")
    revision_history: Optional[str] = Field("", description="History of previous revisions and context")

    @property
    def language(self) -> str:
        return self.message_language or "English"

# Union type for all possible request types
GenerationRequest = Union[QuickDraftRequest, ReviseDraftRequest] 