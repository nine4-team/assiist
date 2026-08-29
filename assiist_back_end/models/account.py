from pydantic import BaseModel, Field
from typing import Optional, Dict, Any

class Account(BaseModel):
    """
    Represents an account document stored in Firestore.
    An account may group multiple users.
    """
    id: str = Field(..., description="The unique ID for the account.")
    account_name: Optional[str] = None
    subscription_level: Optional[str] = None # e.g., 'free', 'pro', 'enterprise'
    created_on: Optional[str] = None # ISO 8601 format
    
    # Placeholder for non-standard account-level settings or data
    custom_account_settings: Optional[Dict[str, Any]] = None

    class Config:
        str_strip_whitespace = True
        validate_assignment = True 