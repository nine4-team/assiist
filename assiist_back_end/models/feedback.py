from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field

class Feedback(BaseModel):
    """
    Represents a feedback entry submitted by users.
    Includes user feedback text, metadata, and administrative status.
    """
    id: Optional[str] = None
    account_id: str = Field(..., description="Account ID for multi-tenant isolation")
    user_id: str = Field(..., description="User who submitted the feedback")
    feedback_text: str = Field(..., min_length=1, max_length=5000, description="The feedback content")
    feedback_type: str = Field(default="general", description="Type of feedback: general, bug_report, feature_request")
    user_email: str = Field(..., description="User email for follow-up if needed")
    user_name: str = Field(..., description="Display name for context")
    app_version: Optional[str] = Field(None, description="App version for debugging context")
    platform: Optional[str] = Field(None, description="Platform: ios, android, web")
    screen_context: Optional[str] = Field(None, description="Screen where feedback was submitted")
    created_on: Optional[datetime] = None
    updated_on: Optional[datetime] = None
    created_by: Optional[str] = None
    updated_by: Optional[str] = None
    is_deleted: bool = Field(default=False, description="Soft delete flag")
    status: str = Field(default="submitted", description="Status: submitted, reviewed, resolved")
    admin_notes: Optional[str] = Field(None, description="Optional admin response")

    class Config:
        str_strip_whitespace = True
        validate_assignment = True
        json_encoders = {
            datetime: lambda v: v.isoformat()
        } 