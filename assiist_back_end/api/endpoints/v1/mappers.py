import uuid
from datetime import datetime, timezone
from typing import Dict, Any, List, Type, Optional
from pydantic import BaseModel, Field, EmailStr

# --- Schema Imports ---
# Import Schemas (from api.schemas)
from assiist_back_end.api.schemas.contact import (
    ContactCreateSchema,
    EmailAddressSchema,
    PhoneNumberSchema,
    AddressSchema,
    PersonalDetailsSchema,
    BusinessDetailsSchema,
    RelationshipDetailSchema,
    BusinessOpportunitySchema,
    ContactResponseSchema,
    ContactUpdateSchema,
)

# --- Domain Model Imports ---
# Import Domain Models (from models) - Now Pydantic models
from assiist_back_end.models.contact import (
    Contact,
    EmailAddress,
    PhoneNumber,
    Address,
    PersonalDetails,
    BusinessDetails,
    RelationshipDetail,
    BusinessOpportunity,
)

# Add imports for new domain models
from assiist_back_end.models.appointment import Appointment, Attendee as AppointmentAttendee, Attachment as AppointmentAttachment
from assiist_back_end.models.note import Note
from assiist_back_end.models.task import Task
from assiist_back_end.models.reservation import Reservation

# --- Schema Imports ---
# ... (existing contact schema imports)
# Add imports for new API schemas
from assiist_back_end.api.schemas.appointment import (
    AppointmentCreateSchema,
    AppointmentResponseSchema,
    AppointmentUpdateSchema,
    AttendeeSchema as AppointmentAttendeeSchema, # Use aliases to avoid name clashes if needed
    AttachmentSchema as AppointmentAttachmentSchema
)
from assiist_back_end.api.schemas.note import (
    NoteCreateSchema,
    NoteResponseSchema,
    NoteUpdateSchema
)
from assiist_back_end.api.schemas.task import (
    TaskCreateSchema,
    TaskResponseSchema,
    TaskUpdateSchema,
)
from assiist_back_end.api.schemas.reservation import (
    ReservationCreateSchema,
    ReservationResponseSchema,
    ReservationUpdateSchema,
)

# --- Helper Functions ---

def map_schema_list_to_domain_list(schema_list: Optional[List[BaseModel]], domain_model_class: Type[BaseModel]) -> List[BaseModel]:
    """Helper function to map a list of Pydantic schemas to a list of domain models."""
    if schema_list is None:
        return []
    # Use model_dump() for Pydantic v2+ and validate into domain model
    return [domain_model_class.model_validate(item.model_dump()) for item in schema_list]

def map_create_schema_to_domain(schema: ContactCreateSchema, account_id: str, creator_user_id: str) -> Contact:
    """Maps a ContactCreateSchema Pydantic model to a Contact domain model (now also Pydantic).
       Requires account_id and creator_user_id for ownership/audit fields.
    """
    now = datetime.now(timezone.utc)
    doc_id = str(uuid.uuid4()) # Firestore document ID will be this

    # Dump the schema to a dict
    contact_data = schema.model_dump(exclude_unset=True)

    # Add required fields
    contact_data["id"] = doc_id
    contact_data["account_id"] = account_id
    contact_data["created_by"] = creator_user_id
    contact_data["created_on"] = now
    contact_data["updated_on"] = now # Set initial updated_on
    contact_data["updated_by"] = creator_user_id
    contact_data["is_deleted"] = False

    # Pydantic handles nested model validation automatically if types match
    # Just need to validate the whole dictionary into the domain Contact model
    return Contact.model_validate(contact_data)

# TODO: Add mapper for Contact domain -> ContactResponseSchema
# TODO: Add mapper for ContactUpdateSchema -> changes dict for repository

# --- Domain Model to Response Schema ---

def map_domain_list_to_schema_list(domain_list: Optional[List[BaseModel]], schema_model_class: Type[BaseModel]) -> List[BaseModel]:
    """Helper function to map a list of domain models (now Pydantic) to a list of Pydantic schemas."""
    if domain_list is None:
        return []
    # Dump each domain model (Pydantic) to dict, then validate with response schema
    return [schema_model_class.model_validate(item.model_dump(by_alias=True)) for item in domain_list]

def map_domain_to_response_schema(contact: Contact) -> ContactResponseSchema:
    """Maps a Contact domain model (Pydantic) to a ContactResponseSchema Pydantic model."""
    # Dump the domain model to dict (using aliases like 'zip') and validate into the response schema
    contact_data = contact.model_dump(by_alias=True)
    return ContactResponseSchema.model_validate(contact_data)

# --- Update Schema to Dict for Repository ---

def map_update_schema_to_dict(schema: ContactUpdateSchema, updater_user_id: str) -> Dict[str, Any]:
    """Converts a ContactUpdateSchema to a dictionary suitable for Firestore update,
       excluding unset fields.
    """
    # Use exclude_unset=True to only include fields explicitly set in the PATCH request
    # Use by_alias=True to ensure fields like 'zip' are used for Firestore keys if defined
    update_data = schema.model_dump(exclude_unset=True, by_alias=True)
    
    # No need to manually convert nested models to dicts anymore,
    # model_dump handles nested Pydantic models correctly.
    
    # The repository now handles setting updated_by and updated_on with server timestamps
    # So we don't need to add them here.
            
    return update_data 

# --- Appointment Mappers ---

def map_appointment_create_schema_to_domain(schema: AppointmentCreateSchema, user_id: str) -> Appointment:
    """Maps AppointmentCreateSchema to Appointment domain model, injecting user_id."""
    appointment_data = schema.model_dump(exclude_unset=True)
    appointment_data['user_id'] = user_id
    # Assuming ID is generated by default_factory in the model
    # created_by/updated_by might be set here or handled by repo/service
    # appointment_data['created_by'] = user_id # Example
    return Appointment.model_validate(appointment_data)

def map_appointment_domain_to_response_schema(appointment: Appointment) -> AppointmentResponseSchema:
    """Maps Appointment domain model to AppointmentResponseSchema."""
    return AppointmentResponseSchema.model_validate(appointment.model_dump())

def map_appointment_update_schema_to_dict(schema: AppointmentUpdateSchema) -> Dict[str, Any]:
    """Converts AppointmentUpdateSchema to a dictionary for repository update.
       Excludes unset fields.
    """
    # Use exclude_unset=True to only include fields explicitly set in the PATCH request
    update_data = schema.model_dump(exclude_unset=True, exclude={'id', 'user_id'}) # Prevent updating ID or owner
    
    # Handle potential nested updates if necessary (Pydantic v2 model_dump handles this better)
    if schema.attendees is not None:
        # You might need specific logic if you allow partial updates of attendees/attachments
        # For now, assume full replacement if provided
        update_data['attendees'] = [attendee.model_dump() for attendee in schema.attendees]
    if schema.attachments is not None:
        update_data['attachments'] = [attachment.model_dump() for attachment in schema.attachments]
    if schema.organizer is not None:
        update_data['organizer'] = schema.organizer.model_dump()
        
    # updated_by/updated_on are usually handled by the repository/endpoint logic
    return update_data 

# --- Note Mappers ---

def map_note_create_schema_to_domain(schema: NoteCreateSchema, user_id: str) -> Note:
    """Maps NoteCreateSchema to Note domain model, injecting user_id and created_by."""
    note_data = schema.model_dump(exclude_unset=True)
    note_data['user_id'] = user_id
    note_data['created_by'] = user_id
    # ID and created_on are generated by default_factory in the model
    return Note.model_validate(note_data)

def map_note_domain_to_response_schema(note: Note) -> NoteResponseSchema:
    """Maps Note domain model to NoteResponseSchema."""
    return NoteResponseSchema.model_validate(note.model_dump())

def map_note_update_schema_to_dict(schema: NoteUpdateSchema) -> Dict[str, Any]:
    """Converts NoteUpdateSchema to a dictionary for repository update.
       Excludes unset fields.
    """
    update_data = schema.model_dump(exclude_unset=True, exclude={'id', 'user_id', 'contact_id', 'created_by', 'created_on'})
    # updated_by/updated_on handled by repository/endpoint
    return update_data 

# --- Task Mappers ---

def map_task_create_schema_to_domain(schema: TaskCreateSchema, authenticated_user_id: str) -> Task:
    """Maps TaskCreateSchema to Task domain model, injecting authenticated_user_id for user_id, created_by, and updated_by."""
    return Task(
        user_id=authenticated_user_id,
        contact_id=schema.contact_id,
        title=schema.title,
        body=schema.body,
        type=schema.type,
        status=schema.status, 
        actionable_date=schema.actionable_date,
        due_date=schema.due_date,
        sms_url=schema.sms_url,
        # assigned_user is no longer a field in schema or domain model for this simplified approach
        created_by=authenticated_user_id,
        updated_by=authenticated_user_id, # Set initial updater as creator
        # id, created_on, updated_on, completed_on are set by model/repo default_factory or validators
    )

def map_task_domain_to_response_schema(task: Task) -> TaskResponseSchema:
    """Maps Task domain model to TaskResponseSchema."""
    return TaskResponseSchema(
        id=task.id,
        user_id=task.user_id,
        contact_id=task.contact_id,
        contact_display_name=task.contact_display_name,
        title=task.title,
        body=task.body,
        type=task.type,
        status=task.status,
        actionable_date=task.actionable_date,
        due_date=task.due_date,
        completed_on=task.completed_on,
        sms_url=task.sms_url,
        # assigned_user is no longer a field in domain model or response schema
        created_on=task.created_on,
        created_by=task.created_by,
        updated_on=task.updated_on,
        updated_by=task.updated_by
    )

def map_task_update_schema_to_dict(schema: TaskUpdateSchema) -> Dict[str, Any]:
    """Maps TaskUpdateSchema to a dictionary for repository update, excluding unset fields."""
    return schema.model_dump(exclude_unset=True) # Pydantic v2 style
    # For Pydantic v1: return schema.dict(exclude_unset=True)

# --- Reservation Mappers ---

def map_reservation_create_schema_to_domain(schema: ReservationCreateSchema, user_id: str) -> Reservation:
    """Maps ReservationCreateSchema to Reservation domain model, injecting user_id."""
    reservation_data = schema.model_dump(exclude_unset=True)
    reservation_data['user_id'] = user_id
    reservation_data['created_by'] = user_id
    reservation_data['updated_by'] = user_id
    return Reservation.model_validate(reservation_data)

def map_reservation_domain_to_response_schema(reservation: Reservation) -> ReservationResponseSchema:
    """Maps Reservation domain model to ReservationResponseSchema."""
    return ReservationResponseSchema.model_validate(reservation.model_dump())

def map_reservation_update_schema_to_dict(schema: ReservationUpdateSchema) -> Dict[str, Any]:
    """Converts ReservationUpdateSchema to a dictionary for repository update.
       Excludes unset fields.
    """
    update_data = schema.model_dump(exclude_unset=True, exclude={'id', 'user_id', 'account_id'})
    return update_data