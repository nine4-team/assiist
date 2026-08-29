import uuid
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field, EmailStr

class Attendee(BaseModel):
    email: Optional[EmailStr] = None
    name: Optional[str] = None
    response_status: Optional[str] = None # e.g., accepted, declined, tentative, needsAction
    is_optional: Optional[bool] = False

# Simple structure for attachments, assuming URLs for now
class Attachment(BaseModel):
    file_url: str
    mime_type: Optional[str] = None
    title: Optional[str] = None

class Appointment(BaseModel):
    id: uuid.UUID = Field(default_factory=uuid.uuid4) # Our internal ID
    user_id: str # Added: Link to the owning user
    external_id: Optional[str] = None # ID from the source calendar (e.g., Google event ID)
    calendar_provider: Optional[str] = None # e.g., "google", "outlook", "apple", "native-ios", "native-android", "manual"
    
    title: Optional[str] = None
    description: Optional[str] = None
    
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
    timezone: Optional[str] = None # IANA timezone name if available
    is_all_day: bool = False
    
    location: Optional[str] = None
    
    organizer: Optional[Attendee] = None # Simplified: just one organizer
    attendees: List[Attendee] = []
    attachments: List[Attachment] = [] # Added attachments
    
    status: Optional[str] = None # e.g., confirmed, tentative, cancelled
    
    source_created_on: Optional[datetime] = None # Renamed from created_at_source
    source_updated_on: Optional[datetime] = None # Renamed from updated_at_source
    created_on: Optional[datetime] = None # When created in our Firestore DB (consistent with user preference)
    updated_on: Optional[datetime] = None # When last updated in our Firestore DB (consistent with user preference)

    # --- Fields for linking within our system ---
    assiist_contact_ids: List[uuid.UUID] = [] # Link to zero or more contacts
    source_account_id: Optional[str] = None # ID of the user's linked calendar account (e.g., specific google account)
    processed_on: Optional[datetime] = None # Reverted to processed_on for standard terminology
    needs_contact_creation_prompt: bool = False # Flag for UI
    
    # --- Reschedule tracking fields ---
    is_rescheduled: bool = False # Flag indicating if this appointment has been rescheduled
    original_start_time: Optional[datetime] = None # Original start time before reschedule
    original_end_time: Optional[datetime] = None # Original end time before reschedule
    reschedule_reason: Optional[str] = None # Optional reason for reschedule
    reschedule_count: int = 0 # Track number of reschedules

    class Config:
        from_attributes = True # If using with an ORM like SQLAlchemy
        # Consider adding example data for documentation
        # schema_extra = { ... } 