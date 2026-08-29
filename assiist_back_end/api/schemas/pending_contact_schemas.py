from pydantic import BaseModel, Field, EmailStr
from typing import Optional
import datetime

class PendingContactResponse(BaseModel):
    id: str
    display_name: str  # JSON: display_name (snake_case for frontend)
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    status: str
    created_on: Optional[datetime.datetime] = None  # JSON: created_on (snake_case for frontend)
    source_event_id: Optional[str] = None  # JSON: source_event_id (snake_case for frontend)
    source_event_title: Optional[str] = None  # JSON: source_event_title (snake_case for frontend)
    appointment_time: Optional[datetime.datetime] = None  # JSON: appointment_time
    appointment_notes: Optional[str] = None  # JSON: appointment_notes

    class Config:
        from_attributes = True  # Allow creating instances from ORM objects or other attribute-based objects

class PendingContactListResponse(BaseModel):
     items: list[PendingContactResponse] 