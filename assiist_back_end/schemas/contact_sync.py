from typing import List, Optional
from datetime import datetime
from pydantic import BaseModel, Field

from assiist_back_end.models.contact import Contact

class IncrementalSyncRequest(BaseModel):
    """Payload from the mobile device requesting an incremental sync.

    Attributes:
        last_sync_ts: The timestamp of the device's last successful sync. If
            omitted (first-time incremental), the server will treat it as the
            epoch and return all contacts.
        client_changes: Contacts that have been created/updated on the device
            since `last_sync_ts`.  This includes deletions, represented by
            contacts with `is_deleted=True`.
    """

    last_sync_ts: Optional[datetime] = Field(None, description="Client's last successful sync timestamp.")
    client_changes: List[Contact] = Field(default_factory=list, description="Contacts changed on the device since last sync.")


class IncrementalSyncResponse(BaseModel):
    """Payload returned to the mobile device after the server processes the request."""

    server_changes: List[Contact] = Field(default_factory=list, description="Contacts changed on the server since last_sync_ts.") 