import uuid
from datetime import datetime
from typing import Optional, Literal, Dict, Any, List
from enum import Enum

from pydantic import BaseModel, Field, field_validator, ValidationInfo
from assiist_back_end.utils.time import utc_now

# Define possible task statuses - UPDATED
TaskStatus = Literal["pending", "completed", "deleted"]
# Define possible task types - NEW
TaskType = Literal["message", "action"]

class Task(BaseModel):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, description="Unique identifier for the task")
    account_id: Optional[str] = Field(None, description="Account ID for multi-tenant isolation")
    user_id: str # Owning User ID / Primary user associated with the task
    actionable_date: Optional[datetime] = None
    due_date: Optional[datetime] = None
    title: str
    body: Optional[str] = None # task description for action tasks or message content for message tasks
    status: TaskStatus = "pending" # UPDATED enum and default
    type: TaskType # NEW field

    created_on: datetime = Field(default_factory=utc_now)
    created_by: str # User ID of the creator (as requested)
    updated_on: Optional[datetime] = None
    updated_by: Optional[str] = None # User ID of the last updater (as requested)

    # Link back to parent contact
    contact_id: Optional[uuid.UUID] = None # Foreign key to Contact

    # SMS-related fields
    llm_provider: Optional[str] = Field(None, description="AI provider used to generate the content")
    sms_url: Optional[str] = Field(None, description="Platform-specific SMS URL for sending the message (e.g., sms:+1234567890?body=message for Android or sms:+1234567890&body=message for iOS)")
    assistant_message: Optional[str] = Field(None, description="Assistant message to display to user about the generated content")

    completed_on: Optional[datetime] = None # <<< ADD completed_on

    # Optional field for the Contact object itself, excluded from DB/API mapping by default
    # contact: Optional['Contact'] = Field(None, exclude=True) 

    contact_display_name: Optional[str] = Field(None, description="Denormalized display name of the associated contact") # NEW FIELD

    # Revision history reference - ONLY field needed for revision tracking
    revision_history_id: Optional[str] = Field(None, description="ID of the associated revision history document")

    class Config:
        from_attributes = True
        use_enum_values = True # Ensure enum values are used when exporting

    @field_validator('updated_on', 'completed_on', mode='before', check_fields=False)
    def set_default_on_update(cls, v, info: ValidationInfo):
        status = info.data.get('status')

        if info.field_name == 'updated_on':
            # Set updated_on if status is being changed, or if any other field is presumably updated.
            # For simplicity, if 'status' is in the data (implying an update that might change it or other fields),
            # we set updated_on. A more robust check might involve comparing old vs new data if available.
            if status is not None or info.data: # if status is part of update or any data is present for update
                return utc_now()

        if info.field_name == 'completed_on':
            if status == "completed" and v is None:
                return utc_now()
        
        return v

    @field_validator('sms_url', mode='before')
    def validate_sms_url(cls, v, info: ValidationInfo):
        """Validate that message tasks have an SMS URL."""
        task_type = info.data.get('type')
        if task_type == 'message' and not v:
            raise ValueError("Message tasks must have an SMS URL")
        return v 