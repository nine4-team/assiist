from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field
from uuid import uuid4

class Reservation(BaseModel):
    """Domain model for a reservation."""
    id: str = Field(default_factory=lambda: str(uuid4()))
    contact_id: str = Field(..., description="ID of the contact this reservation is for")
    account_id: str = Field(..., description="ID of the account this reservation belongs to")
    user_id: str = Field(..., description="ID of the user who created the reservation")
    contact_name: str = Field(..., description="Name of the contact")
    contact_email: Optional[str] = Field(None, description="Email of the contact")
    contact_phone: Optional[str] = Field(None, description="Phone number of the contact")
    created_on: datetime = Field(default_factory=datetime.utcnow, description="When the reservation was created")
    updated_on: datetime = Field(default_factory=datetime.utcnow, description="When the reservation was last updated")
    created_by: str = Field(..., description="ID of the user who created the reservation")
    updated_by: str = Field(..., description="ID of the user who last updated the reservation")

    class Config:
        from_attributes = True
        json_encoders = {
            datetime: lambda v: v.isoformat()
        } 