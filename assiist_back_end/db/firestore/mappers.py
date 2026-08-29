from datetime import datetime
from typing import Any, Dict, Optional, List
import uuid

# Firestore types
from google.cloud.firestore_v1 import DocumentSnapshot, SERVER_TIMESTAMP
from firebase_admin import firestore

# Domain models
from assiist_back_end.models.contact import (
    Contact, PhoneNumber, EmailAddress, Address,
    PersonalDetails, RelationshipDetail, BusinessDetails, BusinessOpportunity
)

# Add imports for new domain models
from assiist_back_end.models.appointment import Appointment, Attendee as AppointmentAttendee, Attachment as AppointmentAttachment
from assiist_back_end.models.note import Note
from assiist_back_end.models.task import Task, TaskStatus, TaskType
from assiist_back_end.models.generation import GenerationRequest, GenerationRequestStatus

# Helper for Firestore timestamp conversion if needed
# from google.cloud.firestore_v1 import DatetimeWithNanoseconds # Removed incorrect import

# --- Firestore to Domain Model Mappers ---

def _timestamp_to_datetime(timestamp: Any) -> Optional[datetime]:
    """Safely convert Firestore Timestamp or other potential types to datetime."""
    if isinstance(timestamp, firestore.Timestamp):
        return timestamp.to_datetime()
    if isinstance(timestamp, datetime):
        return timestamp # Already datetime
    # Add handling for other potential representations if necessary
    return None

def _map_to_phone_number(data: Dict[str, Any]) -> PhoneNumber:
    return PhoneNumber(
        label=data.get('label'),
        number=data.get('number')
    )

def _map_to_email_address(data: Dict[str, Any]) -> EmailAddress:
    return EmailAddress(
        label=data.get('label'),
        address=data.get('address')
    )

def _map_to_address(data: Dict[str, Any]) -> Address:
    return Address(
        label=data.get('label'),
        street=data.get('street'),
        city=data.get('city'),
        state=data.get('state'),
        zip=data.get('zip'),
        country=data.get('country')
    )

def _map_to_personal_details(data: Optional[Dict[str, Any]]) -> Optional[PersonalDetails]:
    if data is None: return None
    return PersonalDetails(
        family=data.get('family'),
        occupation=data.get('occupation'),
        recreation=data.get('recreation'),
        dreams=data.get('dreams')
    )

def _map_to_relationship_detail(data: Dict[str, Any]) -> RelationshipDetail:
    return RelationshipDetail(details=data.get('details'))

def _map_to_business_opportunity(data: Optional[Dict[str, Any]]) -> Optional[BusinessOpportunity]:
    if data is None: return None
    return BusinessOpportunity(
        opportunity_description=data.get('opportunity_description'),
        latest_development=data.get('latest_development')
    )

def _map_to_business_details(data: Optional[Dict[str, Any]]) -> Optional[BusinessDetails]:
    if data is None: return None
    opportunities = []
    if data.get('opportunities'):
        opportunities = [_map_to_business_opportunity(opp) for opp in data['opportunities'] if opp]
    elif data.get('business_opportunity'):  # Backwards compatibility
        opp = _map_to_business_opportunity(data.get('business_opportunity'))
        if opp:
            opportunities = [opp]
    return BusinessDetails(opportunities=opportunities)

def firestore_to_contact(data: Dict[str, Any]) -> Contact:
    """Maps a Firestore document dictionary to a Contact domain model."""
    return Contact.model_validate(data) # Ensure ID is included

# --- Appointment Mappers ---

def firestore_to_appointment(data: Dict[str, Any]) -> Optional[Appointment]:
    """Maps Firestore dictionary to Appointment domain model."""
    if not data:
        return None
    try:
        if 'id' in data and isinstance(data['id'], str):
             data['id'] = uuid.UUID(data['id'])
        if 'assiist_contact_ids' in data:
             data['assiist_contact_ids'] = [uuid.UUID(cid) for cid in data['assiist_contact_ids'] if isinstance(cid, str)]
        return Appointment.model_validate(data)
    except Exception as e:
        print(f"Error mapping Firestore data to Appointment: {e}. Data: {data}")
        return None

def appointment_to_firestore(appointment: Appointment) -> Dict[str, Any]:
    """Maps Appointment domain model to Firestore dictionary."""
    firestore_data = appointment.model_dump(exclude={'id'}, exclude_none=True)
    if 'assiist_contact_ids' in firestore_data:
        firestore_data['assiist_contact_ids'] = [str(cid) for cid in firestore_data['assiist_contact_ids']]
    return firestore_data

# --- Note Mappers ---

def firestore_to_note(data: Dict[str, Any]) -> Optional[Note]:
    """Maps Firestore dictionary to Note domain model with new structure."""
    if not data:
        return None
    try:
        # Handle UUID conversions
        if 'id' in data and isinstance(data['id'], str):
            data['id'] = uuid.UUID(data['id'])
        if 'contact_id' in data and isinstance(data['contact_id'], str):
            data['contact_id'] = uuid.UUID(data['contact_id'])
        
        # Handle UUID conversions and field validation
        data['raw_note'] = data.get('raw_note', '')
        
        # Ensure processed_note has proper structure if it exists
        if 'processed_note' in data and isinstance(data['processed_note'], dict):
            processed_note_data = data['processed_note']
            # Ensure it has required fields
            if 'body' not in processed_note_data:
                processed_note_data['body'] = ''
            if 'key_points' not in processed_note_data:
                processed_note_data['key_points'] = []
        elif 'processed_note' not in data:
            data['processed_note'] = None
        
        return Note.model_validate(data)
        
    except Exception as e:
        print(f"Error mapping Firestore data to Note: {e}. Data: {data}")
        return None

def note_to_firestore(note: Note) -> Dict[str, Any]:
    """Maps Note domain model to Firestore dictionary with new structure."""
    firestore_data = note.model_dump(exclude={'id'}, exclude_none=True)
    
    # Convert UUIDs to strings
    if 'contact_id' in firestore_data:
        firestore_data['contact_id'] = str(firestore_data['contact_id'])
    
    # Ensure processed_note is properly serialized
    if 'processed_note' in firestore_data and firestore_data['processed_note']:
        processed_note = firestore_data['processed_note']
        if hasattr(processed_note, 'model_dump'):
            firestore_data['processed_note'] = processed_note.model_dump()
    
    return firestore_data

# --- Task Mappers ---

def firestore_to_task(doc: Any) -> Optional[Task]:
    """Converts a Firestore document (snapshot or dict) to a Task domain model."""
    if doc is None:
        return None

    if isinstance(doc, DocumentSnapshot):
        data = doc.to_dict() or {}
        data['id'] = doc.id # Ensure ID is present from snapshot
    elif isinstance(doc, dict):
        data = doc # doc is already a dictionary
    else:
        # Or raise an error if type is unexpected
        return None 

    # Ensure 'id' is present in the data if it was a dict initially
    # (snapshot case handles it above)
    if 'id' not in data and isinstance(doc, dict):
         # This case implies the dict passed didn't have an id, which might be an issue
         # For robustness, we could try to skip or log, but ideally ID is always present.
         print(f"Warning: Firestore data for task is missing 'id': {data.get('title')}")
         # return None # Or proceed if ID is truly optional before this point

    # Handle potential string UUID for id if it was a dict
    if isinstance(data.get('id'), str):
        try:
            data['id'] = uuid.UUID(data['id'])
        except ValueError:
            print(f"Warning: Invalid UUID string for task id: {data.get('id')}")
            return None # Cannot create Task without valid UUID id

    # Convert contact_id to UUID if it's a string
    contact_id_str = data.get('contact_id')
    if isinstance(contact_id_str, str):
        try:
            data['contact_id'] = uuid.UUID(contact_id_str)
        except ValueError:
            print(f"Warning: Invalid UUID string for contact_id: {contact_id_str}")
            data['contact_id'] = None # Or handle error as appropriate
    
    # Ensure created_on, updated_on, due_date, actionable_date, completed_on are datetimes
    # Firestore timestamps are often returned as datetime objects already by google-cloud-firestore
    # but if they could be strings, parsing would be needed here.
    # Pydantic will handle type conversion for datetime fields if they are in ISO format strings.
    
    try:
        return Task(**data)
    except Exception as e:
        print(f"Error mapping Firestore data to Task model: {e} - Data: {data}")
        return None

def task_to_firestore(task: Task) -> Dict[str, Any]:
    """Maps Task domain model to a Firestore-compatible dictionary."""
    # Exclude fields that are document ID or managed by server/defaults if not explicitly set by task logic
    # The Pydantic model's dict() or model_dump() method is useful here with exclude/include
    data = task.model_dump(exclude_none=True, exclude={'id'}) # Pydantic v2, excludes id and fields that are None
    # For Pydantic v1: data = task.dict(exclude_none=True, exclude={'id'})
    
    # Ensure UUIDs are stored as strings if not automatically handled by Firestore client for dicts
    if 'contact_id' in data and isinstance(data['contact_id'], uuid.UUID):
        data['contact_id'] = str(data['contact_id'])
    # created_on and updated_on are often handled by SERVER_TIMESTAMP in the repository add/update methods
    # but if they are already datetime objects on the model, they should be converted correctly by Pydantic.
    return data

# --- Domain Model to Firestore Mappers ---

def _datetime_to_firestore(dt: Optional[datetime]) -> Optional[datetime]:
    """Converts datetime to Firestore compatible format (passthrough for now, use SERVER_TIMESTAMP in repo)."""
    # Firestore admin SDK handles Python datetime objects automatically
    # For SERVER_TIMESTAMP, it must be set directly in the update/set call
    return dt

def _dataclass_to_dict(obj: Any) -> Optional[Dict[str, Any]]:
    """Basic helper to convert a dataclass instance to a dictionary, skipping None values."""
    if obj is None:
        return None
    if hasattr(obj, '__dict__'): # Basic check if it's likely a dataclass/object
        return {k: v for k, v in obj.__dict__.items() if v is not None}
    return None # Or raise an error if input type is unexpected

def contact_to_firestore(contact: Contact) -> Dict[str, Any]:
    """Maps a Contact domain model to a Firestore document dictionary."""
    data = {
        # Exclude 'id' as it's the document key
        'account_id': contact.account_id,
        'assigned_user': contact.assigned_user,
        'created_by': contact.created_by,
        'created_on': _datetime_to_firestore(contact.created_on),
        'first_name': contact.first_name,
        'last_name': contact.last_name,
        'addressed_as': contact.addressed_as,
        'date_of_birth': _datetime_to_firestore(contact.date_of_birth),
        'business_name': contact.business_name,
        'business_type': contact.business_type,
        'phone_numbers': [_dataclass_to_dict(pn) for pn in contact.phone_numbers],
        'emails': [_dataclass_to_dict(em) for em in contact.emails],
        'addresses': [_dataclass_to_dict(addr) for addr in contact.addresses],
        'personal_details': _dataclass_to_dict(contact.personal_details),
        'relationship_details': {
            user_id: _dataclass_to_dict(details)
            for user_id, details in contact.relationship_details.items()
        },
        'business_details': {
            'opportunities': [_dataclass_to_dict(opp) for opp in contact.business_details.opportunities]
        } if contact.business_details else None,
        'source': contact.source,
        'tags': contact.tags,
        'updated_on': _datetime_to_firestore(contact.updated_on),
        'updated_by': contact.updated_by,
        'is_deleted': contact.is_deleted,
        'last_contacted_on': _datetime_to_firestore(contact.last_contacted_on),
        'is_vip': contact.is_vip
    }
    # Filter out None values at the top level
    return {k: v for k, v in data.items() if v is not None} 