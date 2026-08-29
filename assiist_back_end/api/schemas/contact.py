from pydantic import BaseModel, Field, EmailStr
from typing import Optional, List, Dict
from datetime import datetime

# Nested Schemas (adjust fields as needed for API)
class EmailAddressSchema(BaseModel):
    address: EmailStr
    label: Optional[str] = None # E.g., 'Work', 'Home'

class PhoneNumberSchema(BaseModel):
    number: str # Removed pattern validation for now
    label: Optional[str] = None # E.g., 'Mobile', 'Work'

class AddressSchema(BaseModel):
    street: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None # Renamed from state_province
    zip: Optional[str] = None # Renamed from postal_code
    country: Optional[str] = None
    label: Optional[str] = None # E.g., 'Home', 'Work'

class PersonalDetailsSchema(BaseModel):
    family: Optional[str] = None
    occupation: Optional[str] = None
    recreation: Optional[str] = None
    dreams: Optional[str] = None
    additional_info: Optional[str] = None

class BusinessOpportunitySchema(BaseModel): # Needs definition based on domain
    opportunity_description: Optional[str] = None
    latest_development: Optional[str] = None # Matches domain model
    # potential_value: Optional[float] = None # Fields from earlier schema attempt, add if needed
    # stage: Optional[str] = None

class BusinessDetailsSchema(BaseModel):
    # Only contains the nested opportunity, as per reconciled plan
    # business_opportunity: Optional[BusinessOpportunitySchema] = None # Old structure
    opportunities: List[BusinessOpportunitySchema] = Field(default_factory=list) # New structure

class RelationshipDetailSchema(BaseModel):
    user_id: Optional[str] = None # ID of the user this relationship detail pertains to
    details: Optional[str] = None # From domain model
    # notes: Optional[str] = None # Removed notes

# Schema for Creating a Contact (input)
class ContactCreateSchema(BaseModel):
    first_name: str = Field(..., min_length=1)
    last_name: Optional[str] = None
    addressed_as: Optional[str] = None
    assigned_user: Optional[str] = None # Kept as per feedback
    date_of_birth: Optional[datetime] = None
    business_name: Optional[str] = None # Renamed from company
    business_type: Optional[str] = None
    emails: Optional[List[EmailAddressSchema]] = []
    phone_numbers: Optional[List[PhoneNumberSchema]] = []
    addresses: Optional[List[AddressSchema]] = []
    personal_details: Optional[PersonalDetailsSchema] = None
    business_details: Optional[BusinessDetailsSchema] = None # Contains nested opportunity
    relationship_details: Optional[Dict[str, RelationshipDetailSchema]] = {}
    tags: Optional[List[str]] = []
    source: Optional[str] = None
    last_contacted_on: Optional[datetime] = None  # ADDED: Last contact timestamp
    is_vip: bool = False
    device_contact_uuid: Optional[str] = Field(None, description="iOS device contact UUID for sync tracking")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "first_name": "Jane",
                    "last_name": "Doe",
                    "addressed_as": "Jenny", 
                    "assigned_user": "user_abc",
                    "date_of_birth": "1990-01-01T00:00:00",
                    "business_name": "Example Corp", # Renamed from company
                    "business_type": "Client",
                    "emails": [{"address": "jane.doe@example.com", "label": "Work"}],
                    "phone_numbers": [{"number": "+1234567890", "label": "Mobile"}],
                    "personal_details": {
                        "family": "Married, 2 children",
                        "occupation": "Software Engineer",
                        "recreation": "Hiking, reading",
                        "dreams": "Wants to travel the world",
                        "additional_info": "Prefers morning meetings"
                    },
                    "business_details": {
                        "opportunities": [
                            {
                                "opportunity_description": "Potential project Q3",
                                "latest_development": "Initial discussion held"
                            }
                        ]
                    },
                    "relationship_details": {
                       "user_xyz": {
                           "details": "Met at conference, discussed potential synergy."
                       }
                    },
                    "source": "manual_entry",
                    "tags": ["important", "q3-target"],
                    "last_contacted_on": "2023-10-27T12:00:00"
                }
            ]
        }
    }

# Schema for Responding with Contact data (output)
class ContactResponseSchema(BaseModel):
    id: str
    account_id: str 
    assigned_user: Optional[str] = None # Kept as per feedback
    first_name: str
    last_name: Optional[str] = None
    addressed_as: Optional[str] = None
    date_of_birth: Optional[datetime] = None
    business_name: Optional[str] = None # Renamed from company
    business_type: Optional[str] = None
    emails: Optional[List[EmailAddressSchema]] = []
    phone_numbers: Optional[List[PhoneNumberSchema]] = []
    addresses: Optional[List[AddressSchema]] = []
    personal_details: Optional[PersonalDetailsSchema] = None
    business_details: Optional[BusinessDetailsSchema] = None # Contains nested opportunity
    relationship_details: Optional[Dict[str, RelationshipDetailSchema]] = {}
    tags: Optional[List[str]] = []
    source: Optional[str] = None
    created_on: datetime
    updated_on: datetime
    created_by: Optional[str] = None
    updated_by: Optional[str] = None
    is_deleted: bool
    last_contacted_on: Optional[datetime] = None  # ADDED: Last contact timestamp
    is_vip: bool
    device_contact_uuid: Optional[str] = Field(None, description="iOS device contact UUID for sync tracking")

    model_config = {
        "from_attributes": True # Enable ORM mode equivalent for Pydantic v2
    }

# Schema for Updating a Contact (input for PUT/PATCH)
class ContactUpdateSchema(BaseModel):
    first_name: Optional[str] = Field(None, min_length=1)
    last_name: Optional[str] = None
    addressed_as: Optional[str] = None
    assigned_user: Optional[str] = Field(None) # Kept as per feedback
    date_of_birth: Optional[datetime] = None
    business_name: Optional[str] = None # Renamed from company
    business_type: Optional[str] = None
    emails: Optional[List[EmailAddressSchema]] = None
    phone_numbers: Optional[List[PhoneNumberSchema]] = None
    addresses: Optional[List[AddressSchema]] = None
    personal_details: Optional[PersonalDetailsSchema] = None
    business_details: Optional[BusinessDetailsSchema] = None # Contains nested opportunity
    relationship_details: Optional[Dict[str, RelationshipDetailSchema]] = None
    tags: Optional[List[str]] = None
    source: Optional[str] = None
    last_contacted_on: Optional[datetime] = None  # ADDED: Last contact timestamp
    is_vip: Optional[bool] = None
    device_contact_uuid: Optional[str] = Field(None, description="iOS device contact UUID for sync tracking")
    # Removed notes
    # Removed top-level business_opportunities

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    # Example: Update last name, business_name, and add/update relationship details
                    "last_name": "Smith",
                    "date_of_birth": "1985-05-05T00:00:00",
                    "business_name": "New Co Inc.", # Renamed from company
                    "tags": ["priority"],
                    "relationship_details": {
                        "user_xyz": {
                            "details": "Followed up via email on 2023-10-27."
                        },
                        "user_abc": {
                            "details": "Initial introduction by Jane Doe."
                        }
                    },
                    "last_contacted_on": "2023-10-27T12:00:00"
                }
            ]
        }
    } 