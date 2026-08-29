import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field

class TextMessageExample(BaseModel):
    id: uuid.UUID = Field(default_factory=uuid.uuid4)
    user_id: str
    example_text: str
    created_on: datetime = Field(default_factory=datetime.utcnow)
    updated_on: Optional[datetime] = None

    class Config:
        from_attributes = True 