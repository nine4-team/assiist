import uuid
from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, Field

# --- Request Schemas for AI Generation ---

class QuickDraftGenerationRequestSchema(BaseModel):
    contact_id: uuid.UUID = Field(..., description="The ID of the contact this quick draft relates to.")
    message_instructions: str = Field(..., description="The user's instructions for the quick message draft to be generated.")
    language: str = Field(..., description="The target language for the draft (e.g., 'english', 'spanish').")

# --- Response Schemas for AI Generation ---

class GenerationAcceptedResponseSchema(BaseModel):
    id: str = Field(..., description="The unique ID of the generation request.")
    status: str = Field(..., description="The current status of the request (e.g., 'pending', 'processing', 'completed', 'failed').")
    message: str = Field(..., description="A user-friendly message about the request status.")
    contact_id: str = Field(..., description="The ID of the contact this request relates to.")
    instructions: str = Field(..., description="The user's instructions for the generation.")
    language: str = Field(..., description="The target language for the generation.")
    estimated_completion_time: str = Field(..., description="Estimated time for completion (e.g., '10-30 seconds').")
    next_steps: List[str] = Field(..., description="List of next steps that will happen during processing.")

class EnhancedStatusResponseSchema(BaseModel):
    """Enhanced status response with detailed progress information."""
    id: str = Field(..., description="The unique ID of the generation request.")
    status: str = Field(..., description="Current status: pending, processing, completed, failed")
    progress_step: str = Field(..., description="Current step: submitting, analyzing, generating, finalizing, completed, failed")
    progress_percentage: int = Field(..., description="Progress as percentage (0-100)")
    current_step_title: str = Field(..., description="Human-readable title for current step")
    current_step_description: str = Field(..., description="Detailed description of what's happening")
    estimated_time_remaining: int = Field(..., description="Estimated seconds remaining")
    contact_id: str = Field(..., description="The ID of the contact this request relates to.")
    request_type: str = Field(..., description="Type of request: quick_draft or revise_draft")
    error_message: Optional[str] = Field(None, description="Error message if status is failed")
    created_on: datetime = Field(..., description="When the request was created")
    started_processing_on: Optional[datetime] = Field(None, description="When processing started")
    completed_on: Optional[datetime] = Field(None, description="When processing completed")
    
    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat() if v else None
        }

# --- Draft Request Schema (moved from genai.py) ---

class DraftRequestSchema(BaseModel):
    """Unified schema for both quick drafts and revisions."""
    
    # Common fields
    contact_id: str = Field(..., description="ID of the contact")
    request_type: str = Field(..., description="Type of request: 'quick_draft' or 'revise_draft'")
    
    # Quick draft fields
    message_instructions: Optional[str] = Field(None, description="Instructions for quick draft generation")
    language: Optional[str] = Field("English", description="Language for the message")
    
    # Revision fields  
    task_id: Optional[str] = Field(None, description="ID of the task being revised")
    message_draft: Optional[str] = Field(None, description="Current message draft to revise")
    revision_instructions: Optional[str] = Field(None, description="Instructions for revising the draft")
    message_language: Optional[str] = Field("English", description="Language for the revised message") 
    revision_history: Optional[str] = Field("", description="History of previous revisions")
    
    def validate_request_type(self):
        """Validate that required fields are present for each request type."""
        if self.request_type == "quick_draft":
            if not self.message_instructions:
                raise ValueError("message_instructions is required for quick_draft requests")
        elif self.request_type == "revise_draft":
            if not all([self.task_id, self.message_draft, self.revision_instructions]):
                raise ValueError("task_id, message_draft, and revision_instructions are required for revise_draft requests")
        else:
            raise ValueError(f"Invalid request_type: {self.request_type}. Must be 'quick_draft' or 'revise_draft'")

# --- Response Schemas (if needed for async later) ---
# For now, endpoints return TaskResponseSchema directly 