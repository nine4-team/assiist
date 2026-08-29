from pydantic import BaseModel, Field
from typing import Optional, Dict, Any, List

class QuickActionsRequestSchema(BaseModel):
    """Unified schema for both quick drafts and revisions using CANONICAL field names."""
    
    # Common fields
    contact_id: str = Field(..., description="ID of the contact")
    request_type: str = Field(..., description="Type of request: 'quick_draft' or 'revise_draft'")
    
    # Quick draft fields (CANONICAL NAMES)
    message_instructions: Optional[str] = Field(None, description="Instructions for quick draft generation")
    message_language: Optional[str] = Field("english", description="Language for the message")
    
    # Revision fields (CANONICAL NAMES) - SIMPLIFIED: backend fetches message_draft and revision_history
    task_id: Optional[str] = Field(None, description="ID of the task being revised")
    revision_instructions: Optional[str] = Field(None, description="Instructions for revising the draft")
    # REMOVED: message_draft, revision_history - backend fetches these from task_id

class ProcessNoteRequest(BaseModel):
    contact_id: str
    note_content: str
    context: Optional[Dict[str, Any]] = None
    note_type: str = "user"  # "user" or "system"
    user_timezone: Optional[str] = None  # IANA timezone of the user making the request
    # Optional fields for internal (server-to-server) calls
    user_id: Optional[str] = None
    account_id: Optional[str] = None
    appointment_id: Optional[str] = None
    source_event_id: Optional[str] = None
    event_type: Optional[str] = None

    class Config:
        # Allow additional fields so internal services can evolve without
        # breaking strict validation (e.g. future metadata attributes).
        extra = "allow"

class ProcessNoteResponse(BaseModel):
    success: bool
    request_ids: Dict[str, str]  # {"update_tasks": "id1", "update_context": "id2", "process_note": "id3"}
    message: str
    estimated_completion_time: str
    next_steps: List[str] 