from typing import Optional
from datetime import datetime
import uuid

from pydantic import BaseModel, Field, EmailStr

class PendingContact(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4())) # Firestore document ID
    user_id: str # ID of the user this pending contact belongs to
    
    email: EmailStr
    display_name: Optional[str] = None
    phone: Optional[str] = None
    source_event_id: Optional[str] = None # From which event this was generated
    source_event_title: Optional[str] = None # ADDED: Title of the event
    appointment_time: Optional[datetime] = None  # Start time of the appointment
    appointment_notes: Optional[str] = None  # Description/notes of the appointment
    
    status: str = "pending" # e.g., "pending", "created_contact", "ignored"
    
    created_on: Optional[datetime] = None # Set by Firestore SERVER_TIMESTAMP
    updated_on: Optional[datetime] = None # Set by Firestore SERVER_TIMESTAMP
    
    # Reschedule tracking fields
    is_rescheduled: bool = False # Whether this is from a rescheduled appointment
    original_appointment_time: Optional[datetime] = None # Original time before reschedule
    reschedule_reason: Optional[str] = None # Reason for reschedule if available

    class Config:
        from_attributes = True
        populate_by_name = True
        json_encoders = {
            datetime: lambda v: v.isoformat() if v else None,
        } 