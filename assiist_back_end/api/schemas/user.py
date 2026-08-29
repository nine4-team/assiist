from pydantic import BaseModel, Field, EmailStr
from typing import Optional, List

class UserCreateRequest(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=6)  # Firebase requires min 6 chars
    first_name: str | None = None
    last_name: str | None = None
    account_id: str | None = None  # Primary account ID - if not provided, creates new account
    member_account_ids: List[str] = Field(default=[], description="Additional accounts this user is a member of")

class UserCreateResponse(BaseModel):
    id: str
    account_id: str

class UserUpdateRequest(BaseModel):
    first_name: str | None = None
    last_name: str | None = None
    emailVerified: bool | None = None

class UserResponse(BaseModel):
    id: str
    email: EmailStr
    first_name: str | None = None
    last_name: str | None = None
    account_id: str  # Primary account
    member_account_ids: List[str] = Field(default=[], description="Additional accounts this user is a member of") 