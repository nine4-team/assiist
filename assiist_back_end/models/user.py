from pydantic import BaseModel, Field, EmailStr
from typing import List, Dict, Optional, Any
from datetime import datetime

class CalendarIntegration(BaseModel):
    """Represents details for a single linked calendar account."""
    provider: str # e.g., 'google', 'microsoft'
    account_email: str
    credentials: Optional[Dict[str, Any]] = None # Store tokens/credentials securely
    sync_enabled: bool = True
    last_sync_status: Optional[str] = None # e.g., 'success', 'error: auth_failed'
    last_sync_time: Optional[str] = None # ISO 8601 format preferrably

class ContactSyncSettings(BaseModel):
    """Represents settings related to contact synchronization."""
    sync_enabled: bool = False
    last_sync_status: Optional[str] = None
    last_sync_time: Optional[str] = None
    # Add any other relevant sync settings, e.g., sync direction, specific groups

class User(BaseModel):
    """User domain model for authentication and notifications."""
    id: Optional[str] = None  # Firebase UID or document ID
    email: Optional[EmailStr] = None
    account_id: Optional[str] = None  # For multi-tenant isolation
    created_on: Optional[datetime] = None
    updated_on: Optional[datetime] = None
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    full_name: Optional[str] = None
    hashed_password: Optional[str] = None # Store hashed passwords only
    timezone: str = "UTC"  # IANA timezone, default UTC
    is_active: Optional[bool] = True
    
    # Helper method for display purposes (calculated, not stored)
    @property
    def display_name(self) -> str:
        """Calculate display name from first_name and last_name"""
        if self.first_name and self.last_name:
            return f"{self.first_name} {self.last_name}".strip()
        elif self.first_name:
            return self.first_name
        elif self.last_name:
            return self.last_name
        elif self.email:
            return self.email
        return "User"

class UserInDB(User):
    # If your DB model differs slightly or includes the hashed password explicitly
    pass
