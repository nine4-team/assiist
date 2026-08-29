from pydantic import BaseModel, Field
from typing import Optional

class AccountDetailsBase(BaseModel):
    business_description: Optional[str] = Field(default=None, description="The account's business description.")
    business_type: Optional[str] = Field(default=None, description="The account's business type.")

class AccountDetailsUpdateRequest(BaseModel): # Does not inherit, fields are explicitly optional for update
    business_description: Optional[str] = Field(default=None, description="The account's business description to update.")
    business_type: Optional[str] = Field(default=None, description="The account's business type to update.")

class AccountDetailsResponse(AccountDetailsBase):
    pass 