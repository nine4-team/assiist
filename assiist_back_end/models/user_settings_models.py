from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime

class ContactSyncSettingsBase(BaseModel):
    source_preference: Optional[str] = Field(
        None,
        description="Preferred source for contact sync (e.g., 'ios', 'google').",
    )
    source_priority: Optional[str] = Field(
        None,
        description="Conflict resolution strategy (e.g., 'local_wins', 'remote_wins').",
    )
    # Lean incremental-sync additions
    last_successful_sync_ts: Optional[datetime] = Field(
        None,
        description="Timestamp of the last fully successful contacts sync. Used for incremental fetches.",
        alias="last_sync_ts",
    )
    sync_direction: str = Field(
        "bidirectional",
        description="Sync direction policy: 'bidirectional', 'device_to_server', or 'server_to_device'.",
    )

class ContactSyncSettingsRequest(ContactSyncSettingsBase):
    pass

class ContactSyncSettingsResponse(ContactSyncSettingsBase):
    pass

class UserSettings(BaseModel):
    # This model can be expanded later with other user-specific settings
    contact_sync: Optional[ContactSyncSettingsResponse] = None
    # email_ignore_list: Optional[list[str]] = None # Example if we stored ignore list here too 