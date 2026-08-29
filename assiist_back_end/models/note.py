import uuid
from datetime import datetime
from typing import Optional, List

from pydantic import BaseModel, Field

class ProcessedNote(BaseModel):
    """Structured processed note with separate body and key points."""
    body: str = Field(..., description="AI-cleaned and formatted note content")
    key_points: List[str] = Field(default_factory=list, description="Extracted key insights")

class Note(BaseModel):
    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    created_on: datetime = Field(default_factory=datetime.utcnow)
    created_by: str # User ID
    raw_note: str  # ← CHANGED FROM raw_body
    processed_note: Optional[ProcessedNote] = None  # ← CHANGED FROM processed_body

    # Link back to parent contact
    contact_id: uuid.UUID 
    user_id: str # Owning user ID
    
    # Additional fields that frontend expects
    updated_on: Optional[datetime] = None
    updated_by: Optional[str] = None

    class Config:
        from_attributes = True 