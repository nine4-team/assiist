from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class CalendarConnection(BaseModel):
    provider: str
    email: str
    access_token: Optional[str] = None
    id_token: Optional[str] = None # Often specific to Google Sign-In, may not be needed for just API access
    ics_url: Optional[str] = None
    created_on: Optional[str] = None # Should be a datetime string (ISO format)
    
    # New fields for robust token management (especially for Google/OAuth providers)
    refresh_token: Optional[str] = None
    token_expiry: Optional[str] = None # Store as ISO datetime string (e.g., from datetime.isoformat())
    scopes: Optional[List[str]] = None # List of scopes granted

    # Fields to indicate sync health and actions needed
    sync_status: Optional[str] = "active" # e.g., "active", "needs_reauthentication", "error_other", "channel_active", "needs_full_resync"
    sync_status_message: Optional[str] = None

    # --- NEW FIELDS for Google Webhooks ---
    google_channel_id: Optional[str] = None
    google_resource_id: Optional[str] = None
    google_channel_expiration: Optional[datetime] = None # Store expiry time as datetime
    google_sync_token: Optional[str] = None # For incremental sync
    # --- END NEW FIELDS --- 