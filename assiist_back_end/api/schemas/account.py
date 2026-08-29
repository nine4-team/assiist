from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional

class AccountCreateRequest(BaseModel):
    business_name: str = Field(..., description="The required name for the business/account.")

class AccountCreateResponse(BaseModel):
    id: str

class AccountResponse(BaseModel):
    id: str
    account_name: str
    owner_id: Optional[str] = None
    created_on: datetime
    updated_on: datetime 