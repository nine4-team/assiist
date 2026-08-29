from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
from datetime import datetime

# Using Pydantic models now

class PhoneNumber(BaseModel):
    label: Optional[str] = None
    number: Optional[str] = None

class EmailAddress(BaseModel):
    label: Optional[str] = None
    address: str

class Address(BaseModel):
    label: Optional[str] = None
    street: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    zip_code: Optional[str] = Field(None, alias="zip") # Use alias for 'zip' if needed in Firestore
    country: Optional[str] = None

class PersonalDetails(BaseModel):
    family: Optional[str] = None
    occupation: Optional[str] = None
    recreation: Optional[str] = None
    dreams: Optional[str] = None
    additional_info: Optional[str] = None

class RelationshipDetail(BaseModel):
    user_id: Optional[str] = None
    details: Optional[str] = None

class BusinessOpportunity(BaseModel):
    opportunity_description: Optional[str] = None
    latest_development: Optional[str] = None

class BusinessDetails(BaseModel):
    opportunities: List[BusinessOpportunity] = Field(default_factory=list)

class Contact(BaseModel):
    id: str = Field(..., description="Firestore document ID")
    account_id: str
    assigned_user: Optional[str] = None
    created_by: Optional[str] = None
    created_on: Optional[datetime] = None
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    addressed_as: Optional[str] = None
    date_of_birth: Optional[datetime] = None
    business_name: Optional[str] = None
    business_type: Optional[str] = None
    phone_numbers: List[PhoneNumber] = Field(default_factory=list)
    emails: List[EmailAddress] = Field(default_factory=list)
    addresses: List[Address] = Field(default_factory=list)
    personal_details: Optional[PersonalDetails] = None
    relationship_details: Dict[str, RelationshipDetail] = Field(default_factory=dict)  # Key is user_id
    business_details: Optional[BusinessDetails] = None
    source: Optional[str] = None
    tags: List[str] = Field(default_factory=list)
    updated_on: Optional[datetime] = None
    updated_by: Optional[str] = None
    is_deleted: bool = False
    last_contacted_on: Optional[datetime] = None
    last_contacted_days: Optional[int] = None
    is_vip: bool = False
    device_contact_uuid: Optional[str] = Field(None, description="iOS device contact UUID for sync tracking")

    class Config:
        str_strip_whitespace = True
        validate_assignment = True
        # Allow Firestore Timestamps to be parsed as datetime
        # (Pydantic v2 handles this better, but good practice)
        # Enable populate_by_name to allow using field name or alias (like zip_code vs zip)
        populate_by_name = True
        # Consider adding custom JSON encoders if needed for specific types,
        # although Firestore handles datetimes well.
        json_encoders = {
            datetime: lambda v: v.isoformat() if v else None,
        }

    # Note: from_dict / to_dict methods would be needed here
    # for serialization/deserialization, especially handling
    # nested dataclasses and datetime <-> Firestore Timestamp conversion. 