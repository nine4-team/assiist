import uuid
from datetime import datetime
from typing import Optional, Dict, Any, List
from pydantic import BaseModel, Field

# --- Request Schemas for Update Assistant ---

class UpdateTasksRequestSchema(BaseModel):
    # Request metadata
    id: str = Field(..., description="Unique request ID")
    raw_note: str = Field(..., description="The note content to analyze for task updates")
    
    # Business context for AI processing (no database IDs)
    user_first_name: str = Field(default="", description="User's first name for personalization")
    business_name: str = Field(default="", description="User's business name")
    business_type: str = Field(default="", description="Type of business") 
    recipient_name: str = Field(default="", description="How to address the contact")
    recipient_phone: str = Field(default="", description="Contact's phone number")
    relationship_details: str = Field(default="", description="Relationship context")
    personal_details: str = Field(default="", description="Personal information about contact")
    business_details: str = Field(default="", description="Business information about contact")
    current_datetime: str = Field(default="", description="User's current local datetime")
    user_timezone: str = Field(default="", description="User's IANA timezone (e.g., America/Denver)")
    follow_up_immediately: bool = Field(default=False, description="Whether immediate follow-up is required")
    language_examples: str = Field(default="", description="User's communication style examples")
    
    # Historical context arrays
    subset_notes: List[Dict[str, Any]] = Field(default_factory=list, description="Recent notes")
    subset_tasks: List[Dict[str, Any]] = Field(default_factory=list, description="Existing tasks")
    subset_appointments: List[Dict[str, Any]] = Field(default_factory=list, description="Relevant appointments")
    
    # Testing support
    test_mode: bool = Field(default=False, description="Whether running in test mode")

class UpdateContextRequestSchema(BaseModel):
    # Request metadata  
    id: str = Field(..., description="Unique request ID")
    raw_note: str = Field(..., description="The note content to analyze for context updates")
    
    # Business context for AI processing (no database IDs)
    user_first_name: str = Field(default="", description="User's first name")
    user_last_name: str = Field(default="", description="User's last name")
    business_name: str = Field(default="", description="User's business name")
    business_type: str = Field(default="", description="Type of business")
    contact_name: str = Field(default="", description="Contact's full name")
    addressed_as: str = Field(default="", description="How contact prefers to be addressed")
    personal_details: Dict[str, Any] = Field(default_factory=dict, description="Current personal details")
    relationship_details: Dict[str, Any] = Field(default_factory=dict, description="Current relationship details")
    business_details: Dict[str, Any] = Field(default_factory=dict, description="Current business details")
    user_timezone: str = Field(default="", description="User's IANA timezone (e.g., America/Denver)")

class ProcessNoteRequestSchema(BaseModel):
    """Simplified schema for process note requests - AI only needs note content."""
    id: str = Field(..., description="Unique request ID")
    raw_note: str = Field(..., description="The raw note content to process")
    contact_name: str = Field(default="Contact", description="Contact name for context") 
    test_mode: bool = Field(default=False, description="Whether running in test mode")
    user_timezone: str = Field(default="", description="User's IANA timezone (e.g., America/Denver)")

# --- Response Schemas ---

class UpdateAssistantAcceptedResponseSchema(BaseModel):
    id: str = Field(..., description="Unique ID for this update request")
    request_type: str = Field(..., description="Type of update request (update_tasks or update_context)")
    status: str = Field(default="pending", description="Current status of the request")
    submitted_at: datetime = Field(default_factory=datetime.utcnow, description="When the request was submitted")
    message: str = Field(default="Update request submitted successfully", description="Human-readable status message")
    
    # Request confirmation details
    contact_id: str = Field(..., description="Confirmed contact ID")
    note_content: str = Field(..., description="Confirmed note content")
    
    # Processing info
    estimated_completion_time: Optional[str] = Field("30-60 seconds", description="Estimated time to completion")
    next_steps: List[str] = Field(default_factory=lambda: [
        "AI is analyzing the note content",
        "Processing context and generating updates",  
        "Updates will be applied automatically",
        "Processing continues in background"
    ], description="What happens next")

# --- Cloud Function Response Models ---

class TaskOperationSchema(BaseModel):
    operation: str = Field(..., description="Operation type: create, edit, delete, keep")
    operation_justification: Optional[str] = Field(None, description="Explanation for the operation")
    id: Optional[str] = Field(None, description="Task ID for edit/delete/keep operations")
    title: Optional[str] = Field(None, description="Task title (for edit/create)")
    assistant_message: Optional[str] = Field(None, description="Natural reminder text (for edit/create)")
    body: Optional[str] = Field(None, description="Task body/message content (for edit/create)")
    actionable_date: Optional[str] = Field(None, description="ISO datetime when task becomes actionable (for edit/create)")
    due_date: Optional[str] = Field(None, description="ISO datetime when task is due (for edit/create)")
    type: Optional[str] = Field(None, description="Task type: message or action (for edit/create)")
    
    # NEW: Task metadata for debugging/analysis
    task_metadata: Optional[Dict[str, Any]] = Field(None, description="Task metadata including validation results and creation details")
    
    # DEPRECATED: These fields are now part of task_metadata
    task_validation: Optional[List[Dict[str, Any]]] = Field(None, description="DEPRECATED: Task validation results (now in task_metadata)")
    claim_verification: Optional[List[Dict[str, Any]]] = Field(None, description="DEPRECATED: Claim verification results (now in task_metadata)")

class ContextUpdateSchema(BaseModel):
    personal_details_updates: Optional[Dict[str, Any]] = Field(None, description="Updates to personal details")
    relationship_details_updates: Optional[Dict[str, str]] = Field(None, description="Updates to relationship details (user_id -> details)")
    business_details_updates: Optional[Dict[str, Any]] = Field(None, description="Updates to business details")
    reason: Optional[str] = Field(None, description="Explanation for the updates")

# --- Internal Processing Schemas ---

class UpdateTasksCloudFunctionResponseSchema(BaseModel):
    success: bool = Field(..., description="Whether the processing was successful")
    tasks: List[TaskOperationSchema] = Field(default_factory=list, description="List of task operations to execute")
    analysis_tables: Optional[Dict[str, Any]] = Field(None, description="Analysis tables from prompt processing")
    error: Optional[str] = Field(None, description="Error message if processing failed")
    llm_provider: Optional[str] = Field(None, description="LLM provider used for analysis")
    llm_model: Optional[str] = Field(None, description="LLM model used for analysis")
    processing_time_ms: Optional[int] = Field(None, description="Processing time in milliseconds")

class UpdateContextCloudFunctionResponseSchema(BaseModel):
    success: bool = Field(..., description="Whether the processing was successful")
    context_updates: Optional[ContextUpdateSchema] = Field(None, description="Context updates to apply")
    error: Optional[str] = Field(None, description="Error message if processing failed")
    llm_provider: Optional[str] = Field(None, description="LLM provider used for analysis")

class ProcessNoteCloudFunctionResponseSchema(BaseModel):
    """Schema for process note cloud function responses."""
    success: bool
    data: Optional[Dict[str, Any]] = None  # Contains date, day, cleaned_note, key_points
    error: Optional[str] = None
    raw_response: Optional[str] = None  # For debugging 