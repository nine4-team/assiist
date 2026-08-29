import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field

class TextMessageExampleCreateSchema(BaseModel):
    example_text: str

class TextMessageExampleUpdateSchema(BaseModel):
    example_text: Optional[str] = None

class TextMessageExampleResponseSchema(BaseModel):
    id: uuid.UUID
    user_id: str
    example_text: str
    created_on: datetime
    updated_on: Optional[datetime] = None

    class Config:
        from_attributes = True 