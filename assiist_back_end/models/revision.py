from datetime import datetime
from typing import List, Dict, Any, Optional
import uuid
from pydantic import BaseModel, Field, validator

class RevisionEntry(BaseModel):
    """A single revision in the history"""
    revision_instructions: Optional[str] = Field(None, description="Instructions provided for this revision")
    revised_message: str = Field(description="The revised message content")
    timestamp: datetime = Field(default_factory=datetime.utcnow, description="When this revision was created")
    
    @validator('revised_message')
    def message_not_empty(cls, v):
        if not v or not v.strip():
            raise ValueError('Message cannot be empty')
        return v

class RevisionHistory(BaseModel):
    """Complete history of message revisions"""
    id: uuid.UUID = Field(default_factory=uuid.uuid4, description="Unique identifier")
    task_id: uuid.UUID = Field(description="ID of the associated task")
    user_id: str = Field(description="ID of the user who owns this revision history")
    original_message: str = Field(description="The initial message draft")
    revisions: List[RevisionEntry] = Field(default_factory=list, description="Sequence of revisions")
    context: Dict[str, Any] = Field(default_factory=dict, description="Context data for ML training, including original instructions")
    is_finalized: bool = Field(default=False, description="Whether the revision process is complete")
    finalized_on: Optional[datetime] = Field(None, description="When the message was finalized")
    created_on: datetime = Field(default_factory=datetime.utcnow, description="When this history was created")
    
    @validator('original_message')
    def original_message_not_empty(cls, v):
        if not v or not v.strip():
            raise ValueError('Original message cannot be empty')
        return v 