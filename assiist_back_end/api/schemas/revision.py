from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, Field

class ReviseDraftRequest(BaseModel):
    """Request to revise a message draft."""
    task_id: str = Field(..., description="ID of the task to revise")
    contact_id: str = Field(..., description="ID of the contact")
    message_draft: str = Field(..., description="Current message draft to revise")
    revision_instructions: str = Field(..., description="Specific instructions for this revision")
    recipient_name: str = Field(..., description="Name of the recipient")
    recipient_phone: str = Field(..., description="Phone number of the recipient")
    message_language: Optional[str] = Field("English", description="Language for the message")
    revision_history: Optional[str] = Field("", description="History of previous revisions and context")
    language_examples: Optional[List[str]] = Field(default_factory=list, description="Text message examples for language style")
    
class RevisionResponse(BaseModel):
    """Response for message revision operations."""
    success: bool = Field(..., description="Whether the operation was successful")
    message: str = Field(..., description="The revised message content")
    task_id: str = Field(..., description="ID of the associated task")
    task_title: str = Field(..., description="Title of the task")
    sms_url: str = Field(..., description="URL for sending the message via SMS")
    error: Optional[str] = Field(None, description="Error message, if any")
    
class RevisionEntryResponse(BaseModel):
    """A single revision entry in the history."""
    revision_instructions: Optional[str] = Field(None, description="Instructions provided for this revision")
    revised_message: str = Field(..., description="The revised message content")
    timestamp: datetime = Field(..., description="When this revision was created")
    
class RevisionHistoryResponse(BaseModel):
    """Complete history of message revisions."""
    task_id: str = Field(..., description="ID of the associated task")
    original_message: str = Field(..., description="The initial message draft")
    revisions: List[RevisionEntryResponse] = Field(..., description="Sequence of revisions")
    created_on: datetime = Field(..., description="When this history was created")
    is_finalized: bool = Field(..., description="Whether the revision process is complete")
    finalized_on: Optional[datetime] = Field(None, description="When the message was finalized")
    
class SuccessResponse(BaseModel):
    """Simple success response."""
    success: bool = Field(..., description="Whether the operation was successful")
    message: str = Field(..., description="Success message") 