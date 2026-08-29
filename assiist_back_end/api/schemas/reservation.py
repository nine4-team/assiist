from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field
from enum import Enum

class ReservationStatus(str, Enum):
    """Possible statuses for a reservation."""
    ON_LIST = "on_list"
    OFF_LIST = "off_list"

class ReservationBaseSchema(BaseModel):
    """Base schema for reservation data."""
    contact_id: str = Field(..., description="ID of the contact this reservation is for")
    account_id: str = Field(..., description="ID of the account this reservation belongs to")
    contact_name: str = Field(..., description="Name of the contact")
    contact_email: Optional[str] = Field(None, description="Email of the contact")
    contact_phone: Optional[str] = Field(None, description="Phone number of the contact")

class ReservationCreateSchema(ReservationBaseSchema):
    """Schema for creating a new reservation."""
    pass

class ReservationUpdateSchema(BaseModel):
    """Schema for updating an existing reservation."""
    contact_name: Optional[str] = Field(None, description="Updated name of the contact")
    contact_email: Optional[str] = Field(None, description="Updated email of the contact")
    contact_phone: Optional[str] = Field(None, description="Updated phone number of the contact")

class ReservationResponseSchema(ReservationBaseSchema):
    """Schema for reservation responses."""
    id: str = Field(..., description="Unique identifier for the reservation")
    user_id: str = Field(..., description="ID of the user who created the reservation")
    created_on: datetime = Field(..., description="When the reservation was created")
    updated_on: datetime = Field(..., description="When the reservation was last updated")
    created_by: str = Field(..., description="ID of the user who created the reservation")
    updated_by: str = Field(..., description="ID of the user who last updated the reservation")

    class Config:
        from_attributes = True 