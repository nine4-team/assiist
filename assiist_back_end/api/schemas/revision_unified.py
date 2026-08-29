from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime

class RevisionRequestSchema(BaseModel):
    """Unified schema used across Frontend, API, and backend"""
    # Core fields - CONSISTENT EVERYWHERE
    id: Optional[str] = None
    task_id: str
    contact_id: str
    message_draft: str
    revision_instructions: str      # ← CANONICAL: Frontend, API, backend all use this
    message_language: str = "english"  # ← CANONICAL: Frontend, API, backend all use this TODO: are you sure?
    revision_history: Optional[str] = ""

class QuickDraftRequestSchema(BaseModel):
    """Unified schema for quick draft requests"""
    # Core fields - CONSISTENT EVERYWHERE
    id: Optional[str] = None
    contact_id: str
    message_instructions: str       # ← CANONICAL: Frontend, API, backend all use this
    message_language: str = "english"  # ← CANONICAL: Frontend, API, backend all use this  TODO: are you sure?

class RevisionContextSchema(BaseModel):
    """Full context schema for internal processing"""
    id: str
    revision_instructions: str      
    message_language: str          # ← TODO: are we not using 'language' everywhere else?
    task_id: str
    message_draft: str
    revision_history: str
    user_id: str
    contact_id: str
    account_id: str
    user_first_name: str
    business_name: str
    business_type: str
    recipient_name: str
    recipient_phone: str
    language_examples: List[str] = []

class QuickDraftContextSchema(BaseModel):
    """Full context schema for quick draft internal processing"""
    id: str
    message_instructions: str       
    message_language: str          # ← TODO: are we not using 'language' everywhere else?
    user_id: str
    contact_id: str
    account_id: str
    user_first_name: str
    business_name: str
    business_type: str
    recipient_name: str
    recipient_phone: str
    language_examples: List[str] = []



class AssistantResponseSchema(BaseModel):
    """Unified response schema for assistant operations"""
    id: str
    status: str
    message: str
    contact_id: str
    estimated_completion_time: str # <- TODO: this is weird and seems useless. delete?
    next_steps: List[str] 