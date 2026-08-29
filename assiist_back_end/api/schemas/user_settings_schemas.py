from pydantic import BaseModel, EmailStr
from typing import List

# Schema for adding an email to the ignore list
class IgnoredEmailCreate(BaseModel):
    email: EmailStr # Use EmailStr for validation

# Schema for removing an email (if using request body instead of query param)
# class IgnoredEmailDelete(BaseModel):
#     email: EmailStr

# Schema for the response when getting the list
class IgnoredEmailListResponse(BaseModel):
    items: List[EmailStr] # Return validated emails 