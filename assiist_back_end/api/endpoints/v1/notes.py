import uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status, Path, UploadFile, File
from dependency_injector.wiring import inject, Provide

# Container
from assiist_back_end.containers import Container

# Schemas
from assiist_back_end.api.schemas.note import (
    NoteCreateSchema,
    NoteResponseSchema,
    NoteUpdateSchema
)
from assiist_back_end.api.schemas.attachment import (
    AttachmentUploadResponse
)

# Domain Models
from assiist_back_end.models.note import Note
from assiist_back_end.models.contact import Contact # Import Contact for type hint

# Repositories Interfaces
from assiist_back_end.db.repositories.interfaces.note_repository import NoteRepository
# Need ContactRepository is needed by the dependency now
# from core.repositories.contact_repository import ContactRepository

# Mappers
from assiist_back_end.api.endpoints.v1.mappers import (
    map_note_create_schema_to_domain,
    map_note_domain_to_response_schema,
    map_note_update_schema_to_dict
)

# Dependencies
from assiist_back_end.api.endpoints.v1.dependencies import verify_firebase_token, verify_contact_ownership, UserContext

# Services
from assiist_back_end.services.attachment_service import AttachmentService

router = APIRouter(
    # Notes are specific to a contact, so prefix includes contact_id
    prefix="/contacts/{contact_id}/notes", 
    tags=["Notes"]
)

# Separate router for file upload (not tied to specific contact)
upload_router = APIRouter(
    tags=["Notes", "Attachments"]
)

@router.post(
    "",
    response_model=NoteResponseSchema,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new note for a contact"
)
@inject
async def create_note(
    note_in: NoteCreateSchema,
    contact_id: uuid.UUID = Path(..., description="The ID of the contact to associate the note with"),
    user_ctx: UserContext = Depends(verify_firebase_token),
    # Add contact verification dependency (assign to _ if contact obj not needed here)
    _contact: Contact = Depends(verify_contact_ownership), 
    repo: NoteRepository = Depends(Provide[Container.note_repository])
):
    """Creates a new note associated with a specific contact."""
    # Contact ownership is now verified by the dependency
    
    # Map from the request body schema, ignoring any contact_id potentially within note_in
    note_domain = map_note_create_schema_to_domain(note_in, user_id=user_ctx.user_id)

    # Explicitly set the contact_id from the path parameter onto the domain object
    # This overrides any contact_id that might have been mapped from the request body.
    # Ensure type consistency (repo likely expects str)
    note_domain.contact_id = str(contact_id) 

    # Pass the domain object (now guaranteed to have the correct contact_id from the path)
    # and the path contact_id to the repository.
    created_note = await repo.add(user_id=user_ctx.user_id, contact_id=str(contact_id), note=note_domain)
    return map_note_domain_to_response_schema(created_note)

@router.get(
    "",
    response_model=List[NoteResponseSchema],
    summary="List notes for a specific contact"
)
@inject
async def list_notes(
    contact_id: uuid.UUID = Path(..., description="The ID of the contact whose notes to retrieve"),
    user_ctx: UserContext = Depends(verify_firebase_token),
    # Add contact verification dependency 
    _contact: Contact = Depends(verify_contact_ownership), 
    repo: NoteRepository = Depends(Provide[Container.note_repository])
):
    """Retrieves all notes associated with a specific contact."""
    # Contact ownership is now verified by the dependency
    notes = await repo.get_for_contact(user_id=user_ctx.user_id, contact_id=str(contact_id))
    return [map_note_domain_to_response_schema(note) for note in notes]

@router.get(
    "/{note_id}",
    response_model=NoteResponseSchema,
    summary="Get a specific note by ID"
)
@inject
async def get_note(
    contact_id: uuid.UUID = Path(..., description="The ID of the contact"),
    note_id: uuid.UUID = Path(..., description="The ID of the note to retrieve"),
    user_ctx: UserContext = Depends(verify_firebase_token),
    # Add contact verification dependency 
    _contact: Contact = Depends(verify_contact_ownership), 
    repo: NoteRepository = Depends(Provide[Container.note_repository])
):
    """Retrieves details of a specific note for a contact."""
    # Contact ownership is now verified by the dependency
    note = await repo.get_by_id(user_id=user_ctx.user_id, contact_id=str(contact_id), note_id=str(note_id))
    if not note:
        # This check remains, as the note itself might not exist even if contact does
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note not found")
    return map_note_domain_to_response_schema(note)

@router.patch(
    "/{note_id}",
    response_model=NoteResponseSchema,
    summary="Update a note"
)
@inject
async def update_note(
    note_in: NoteUpdateSchema,
    contact_id: uuid.UUID = Path(..., description="The ID of the contact"),
    note_id: uuid.UUID = Path(..., description="The ID of the note to update"),
    user_ctx: UserContext = Depends(verify_firebase_token),
    # Add contact verification dependency 
    _contact: Contact = Depends(verify_contact_ownership), 
    repo: NoteRepository = Depends(Provide[Container.note_repository])
):
    """Updates specific fields of a note."""
    # Contact ownership is now verified by the dependency
    update_dict = map_note_update_schema_to_dict(note_in)
    if not update_dict:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No update fields provided")
    
    try:
        updated_note = await repo.update(user_id=user_ctx.user_id, contact_id=str(contact_id), note_id=str(note_id), update_data=update_dict)
        # Note: We will refactor repo.update later to raise exceptions
        if not updated_note:
             raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note not found or update failed")
        return map_note_domain_to_response_schema(updated_note)
    except FileNotFoundError as e:
         raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except PermissionError as e:
         raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(e))
    except Exception as e:
        print(f"Error during note update endpoint: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Error updating note")

@router.delete(
    "/{note_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a note"
)
@inject
async def delete_note(
    contact_id: uuid.UUID = Path(..., description="The ID of the contact"),
    note_id: uuid.UUID = Path(..., description="The ID of the note to delete"),
    user_ctx: UserContext = Depends(verify_firebase_token),
    # Add contact verification dependency 
    _contact: Contact = Depends(verify_contact_ownership), 
    repo: NoteRepository = Depends(Provide[Container.note_repository])
):
    """Deletes a specific note for a contact."""
    # Contact ownership is now verified by the dependency
    try:
        deleted = await repo.delete(user_id=user_ctx.user_id, contact_id=str(contact_id), note_id=str(note_id))
        # Note: We will refactor repo.delete later to raise exceptions
        if not deleted:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Note not found")
        return # Return None for 204 
    except FileNotFoundError as e:
         raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except PermissionError as e:
         raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(e))
    except Exception as e:
        print(f"Error during note delete endpoint: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Error deleting note")


# Upload endpoint for file attachments
@upload_router.post(
    "/notes/upload-attachment",
    response_model=AttachmentUploadResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Upload a file attachment"
)
@inject
async def upload_attachment(
    file: UploadFile = File(..., description="File to upload"),
    user_ctx: UserContext = Depends(verify_firebase_token),
    attachment_service: AttachmentService = Depends(Provide[Container.attachment_service])
):
    """
    Upload a file and return public URL and metadata.
    
    - Validates file type and size
    - Uploads to Cloud Storage with account-based path
    - Returns public URL and attachment metadata
    """
    try:
        # Upload file using attachment service
        attachment = await attachment_service.upload_file(
            file=file,
            user_id=user_ctx.user_id,
            account_id=user_ctx.account_id
        )
        
        # Return response schema
        return AttachmentUploadResponse(
            attachment_id=attachment.id,
            public_url=attachment.public_url,
            filename=attachment.filename,
            original_filename=attachment.original_filename,
            file_type=attachment.file_type,
            file_size=attachment.file_size,
            created_on=attachment.created_on
        )
        
    except HTTPException:
        # Re-raise HTTP exceptions from service
        raise
    except Exception as e:
        print(f"Error during file upload: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to upload file"
        ) 