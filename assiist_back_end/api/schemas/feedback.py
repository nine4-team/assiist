from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field, validator

class FeedbackCreateRequest(BaseModel):
    """Request schema for creating feedback."""
    feedback_text: str = Field(..., min_length=1, max_length=5000, description="Feedback content")
    feedback_type: str = Field(default="general", description="Type of feedback")
    app_version: Optional[str] = Field(None, description="App version for debugging context")
    platform: Optional[str] = Field(None, description="Platform: ios, android, web")
    screen_context: Optional[str] = Field(None, description="Screen where feedback was submitted")

    @validator('feedback_type')
    def validate_feedback_type(cls, v):
        allowed_types = {'general', 'bug_report', 'feature_request'}
        if v not in allowed_types:
            raise ValueError(f'feedback_type must be one of: {", ".join(allowed_types)}')
        return v

    @validator('platform')
    def validate_platform(cls, v):
        if v is not None:
            allowed_platforms = {'ios', 'android', 'web'}
            if v not in allowed_platforms:
                raise ValueError(f'platform must be one of: {", ".join(allowed_platforms)}')
        return v

class FeedbackResponse(BaseModel):
    """Response schema for feedback operations."""
    id: str
    account_id: str
    user_id: str
    feedback_text: str
    feedback_type: str
    user_email: str
    user_name: str
    app_version: Optional[str] = None
    platform: Optional[str] = None
    screen_context: Optional[str] = None
    status: str
    created_on: datetime
    
    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }

class FeedbackListResponse(BaseModel):
    """Response schema for listing feedback."""
    feedback: list[FeedbackResponse]
    total_count: int

class FeedbackUpdateRequest(BaseModel):
    """Request schema for updating feedback (admin use)."""
    status: Optional[str] = None
    admin_notes: Optional[str] = None

    @validator('status')
    def validate_status(cls, v):
        if v is not None:
            allowed_statuses = {'submitted', 'reviewed', 'resolved'}
            if v not in allowed_statuses:
                raise ValueError(f'status must be one of: {", ".join(allowed_statuses)}')
        return v 