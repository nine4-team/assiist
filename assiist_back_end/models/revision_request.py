from dataclasses import dataclass
from typing import Optional, List, Dict, Any
from datetime import datetime
import uuid

@dataclass
class UserContext:
    user_id: str
    first_name: str
    last_name: str
    email: str

@dataclass  
class BusinessContext:
    account_id: str
    business_name: str
    business_type: str
    business_description: Optional[str] = None

@dataclass
class ContactContext:
    contact_id: str
    recipient_name: str
    recipient_phone: str
    personal_details: Optional[dict] = None
    relationship_details: Optional[dict] = None
    business_details: Optional[dict] = None

@dataclass
class RevisionRequest:
    # Core Identity - REQUIRED fields first
    id: str
    task_id: str
    message_draft: str
    revision_instructions: str      # ← CANONICAL: Always this name
    message_language: str          # ← CANONICAL: Always this name  
    revision_history: str
    context: Dict[str, Any]         # ← UNIFIED: Single context object from GenAI utilities
    language_examples: List[str]    # ← Converted from string during creation
    
    # Optional fields with defaults come AFTER required fields
    request_type: str = "revise_draft"
    status: str = "pending"
    created_on: datetime = None
    processed_on: Optional[datetime] = None
    error_message: Optional[str] = None
    result_task_id: Optional[str] = None
    result_task_data: Optional[dict] = None
    
    def __post_init__(self):
        # Set created_on if not provided
        if self.created_on is None:
            self.created_on = datetime.utcnow()

@dataclass
class QuickDraftRequest:
    # Core Identity - REQUIRED fields first
    id: str
    message_instructions: str       # ← CANONICAL: Always this name
    message_language: str          # ← CANONICAL: Always this name  
    context: Dict[str, Any]         # ← UNIFIED: Single context object from GenAI utilities
    language_examples: List[str]    # ← Converted from string during creation
    
    # Optional fields with defaults come AFTER required fields
    request_type: str = "quick_draft"
    status: str = "pending"
    created_on: datetime = None
    processed_on: Optional[datetime] = None
    error_message: Optional[str] = None
    result_task_id: Optional[str] = None
    result_task_data: Optional[dict] = None
    
    def __post_init__(self):
        # Set created_on if not provided
        if self.created_on is None:
            self.created_on = datetime.utcnow() 