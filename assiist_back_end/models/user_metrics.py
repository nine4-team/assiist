from datetime import datetime
from pydantic import BaseModel, Field

class UserMetrics(BaseModel):
    """Model for tracking user metrics per contact."""
    user_id: str = Field(..., description="The ID of the user")
    contact_id: str = Field(..., description="The ID of the contact")
    messages_sent: int = Field(default=0, description="Number of messages sent to this contact")
    notes_logged: int = Field(default=0, description="Number of notes logged for this contact")
    last_updated: datetime = Field(default_factory=datetime.utcnow, description="Last time the metrics were updated") 