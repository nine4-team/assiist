from pydantic import BaseModel, Field, EmailStr
from typing import Optional, List
from datetime import datetime

class CreateAccountRequest(BaseModel):
    account_name: str = Field(..., description="Business or account name")
    owner_id: Optional[str] = Field(None, description="Firebase User ID of account owner")
    
    class Config:
        json_schema_extra = {
            "example": {
                "account_name": "Acme Corporation",
                "owner_id": "firebase-id-string"
            }
        }

class CreateOwnerUserRequest(BaseModel):
    first_name: str = Field(..., description="Owner's first name")  
    last_name: str = Field(..., description="Owner's last name")
    email: EmailStr = Field(..., description="Owner's email address")
    password: str = Field(..., min_length=6, description="Owner's password (minimum 6 characters)")
    
    class Config:
        json_schema_extra = {
            "example": {
                "first_name": "John",
                "last_name": "Smith", 
                "email": "john@acme.com",
                "password": "securepass123"
            }
        }

class CreateAccountWithOwnerRequest(BaseModel):
    account_data: CreateAccountRequest
    owner_data: CreateOwnerUserRequest
    
class CreateUserRequest(BaseModel):
    account_id: str = Field(..., description="Primary account ID to assign user to")
    first_name: str = Field(..., description="User's first name")
    last_name: str = Field(..., description="User's last name") 
    email: EmailStr = Field(..., description="User's email address")
    password: str = Field(..., min_length=6, description="User's password (minimum 6 characters)")
    member_account_ids: List[str] = Field(default=[], description="Additional accounts this user is a member of")
    
    class Config:
        json_schema_extra = {
            "example": {
                "account_id": "account-uuid",
                "first_name": "Jane",
                "last_name": "Doe",
                "email": "jane@acme.com",
                "password": "securepass123",
                "member_account_ids": ["other-account-uuid"]
            }
        } 