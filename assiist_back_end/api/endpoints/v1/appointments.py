import uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status, Path, Query, Body
from dependency_injector.wiring import inject, Provide
from pydantic import BaseModel, Field
import logging

# Container
from assiist_back_end.containers import Container

# Schemas (Use two dots to reach api_server/api/schemas/)
# from ....schemas.appointment import (
from assiist_back_end.api.schemas.appointment import (
    AppointmentCreateSchema,
    AppointmentResponseSchema,
    AppointmentUpdateSchema
)
# from ....schemas.pending_contact_schemas import PendingContactResponse
from assiist_back_end.api.schemas.pending_contact_schemas import PendingContactResponse
# Remove import for non-existent file
# from ....schemas.error_schemas import ErrorResponse
# from ...schemas.error_schemas import ErrorResponse

# Domain Models (Keep 4 dots - target api_server/core/)
from assiist_back_end.models.appointment import Appointment
from assiist_back_end.models.contact import Contact

# Repositories Interfaces (Keep 4 dots - target api_server/core/)
from assiist_back_end.db.repositories.interfaces.appointment_repository import AppointmentRepository
from assiist_back_end.db.repositories.interfaces.contact_repository import ContactRepository
from assiist_back_end.db.repositories.interfaces.pending_contact_repository import PendingContactRepository

# Mappers (Keep 2 dots - target api_server/api/v1/)
from assiist_back_end.api.endpoints.v1.mappers import (
    map_appointment_create_schema_to_domain,
    map_appointment_domain_to_response_schema,
    map_appointment_update_schema_to_dict
)

# Dependencies (Keep 2 dots - target api_server/api/v1/)
from assiist_back_end.api.endpoints.v1.dependencies import verify_firebase_token, UserContext
from assiist_back_end.api.endpoints.v1.dependencies import verify_contact_ownership

router = APIRouter(
    prefix="/appointments",
    tags=["Appointments"]
)

# --- NEW Router for Contact-Specific Appointments --- 
contact_appointments_router = APIRouter(
    prefix="/contacts/{contact_id}/appointments",
    tags=["Appointments"]
)
# --- END NEW Router --- 

@router.post(
    "",
    response_model=AppointmentResponseSchema,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new appointment for the current user"
)
@inject
async def create_appointment(
    appointment_in: AppointmentCreateSchema,
    # user_id: str = Depends(get_current_user_id),
    user_ctx: UserContext = Depends(verify_firebase_token), # Use UserContext
    repo: AppointmentRepository = Depends(Provide[Container.appointment_repository]) # Inject repo
):
    """Creates a new calendar event/appointment associated with the authenticated user."""
    # Use user_id from the verified context
    appointment_domain = map_appointment_create_schema_to_domain(appointment_in, user_ctx.user_id)
    # Add created_by if needed in domain model/repo
    # appointment_domain.created_by = user_ctx.user_id 
    created_appointment = await repo.add(user_id=user_ctx.user_id, appointment=appointment_domain)
    return map_appointment_domain_to_response_schema(created_appointment)

@router.get(
    "",
    response_model=List[AppointmentResponseSchema],
    summary="List appointments for the current user"
)
@inject
async def list_appointments(
    # TODO: Add optional date range query parameters (start_date, end_date)
    # user_id: str = Depends(get_current_user_id),
    user_ctx: UserContext = Depends(verify_firebase_token),
    repo: AppointmentRepository = Depends(Provide[Container.appointment_repository])
):
    """Retrieves a list of appointments/calendar events for the authenticated user."""
    appointments = await repo.get_for_user(user_id=user_ctx.user_id)
    return [map_appointment_domain_to_response_schema(appt) for appt in appointments]

@router.get(
    "/pending-contacts",
    response_model=List[PendingContactResponse],
    summary="List Pending Contacts by Status",
    description="Retrieves pending contact records, optionally filtered by status (e.g., 'pending', 'ignored')."
)
@inject
async def list_pending_contacts_by_status(
    user_ctx: UserContext = Depends(verify_firebase_token),
    status: Optional[str] = Query(None, description="Filter by pending contact status (e.g., 'pending', 'ignored', or null for default behavior)"),
    repo: PendingContactRepository = Depends(Provide[Container.pending_contact_repository])
):
    """Retrieves pending contact records, filterable by status."""
    pending_contacts_data = await repo.get_pending_contacts(user_id=user_ctx.user_id, status=status)
    return pending_contacts_data

@router.get(
    "/{appointment_id}",
    response_model=AppointmentResponseSchema,
    summary="Get a specific appointment by ID"
)
@inject
async def get_appointment(
    appointment_id: uuid.UUID,
    # user_id: str = Depends(get_current_user_id),
    user_ctx: UserContext = Depends(verify_firebase_token),
    repo: AppointmentRepository = Depends(Provide[Container.appointment_repository])
):
    """Retrieves details of a specific appointment belonging to the user."""
    appointment = await repo.get_by_id(user_id=user_ctx.user_id, appointment_id=str(appointment_id))
    if not appointment:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Appointment not found")
    return map_appointment_domain_to_response_schema(appointment)

@router.patch(
    "/{appointment_id}",
    response_model=AppointmentResponseSchema,
    summary="Update an appointment"
)
@inject
async def update_appointment(
    appointment_id: uuid.UUID,
    appointment_in: AppointmentUpdateSchema,
    # user_id: str = Depends(get_current_user_id),
    user_ctx: UserContext = Depends(verify_firebase_token),
    repo: AppointmentRepository = Depends(Provide[Container.appointment_repository])
):
    """Updates specific fields of an appointment."""
    update_dict = map_appointment_update_schema_to_dict(appointment_in)
    if not update_dict:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No update fields provided")
    
    try:
        updated_appointment = await repo.update(user_id=user_ctx.user_id, appointment_id=str(appointment_id), update_data=update_dict)
        # Repository now raises exceptions on failure or returns the updated object
        return map_appointment_domain_to_response_schema(updated_appointment)
    except FileNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except PermissionError as e: # Catch if repo adds permission checks later
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(e))
    except Exception as e:
        print(f"Error during appointment update endpoint: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Error updating appointment")

@router.delete(
    "/{appointment_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete an appointment"
)
@inject
async def delete_appointment(
    appointment_id: uuid.UUID,
    # user_id: str = Depends(get_current_user_id),
    user_ctx: UserContext = Depends(verify_firebase_token),
    repo: AppointmentRepository = Depends(Provide[Container.appointment_repository])
):
    """Deletes a specific appointment for the user."""
    try:
        await repo.delete(user_id=user_ctx.user_id, appointment_id=str(appointment_id))
        # No exception means success
        return # Return None for 204 
    except FileNotFoundError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except PermissionError as e: # Catch if repo adds permission checks later
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(e))
    except Exception as e:
        print(f"Error during appointment delete endpoint: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Error deleting appointment") 

# --- NEW Endpoint for Contact Appointments --- 
@contact_appointments_router.get(
    "",
    response_model=List[AppointmentResponseSchema],
    summary="List appointments associated with a specific contact"
)
@inject
async def list_contact_appointments(
    contact_id: uuid.UUID = Path(..., description="The ID of the contact"),
    user_ctx: UserContext = Depends(verify_firebase_token),
    # Verify contact ownership
    _contact: Contact = Depends(verify_contact_ownership), 
    repo: AppointmentRepository = Depends(Provide[Container.appointment_repository])
):
    """Retrieves appointments associated with the specified contact ID."""
    # Use the new repository method
    appointments = await repo.get_for_contact(user_id=user_ctx.user_id, contact_id=str(contact_id))
    return [map_appointment_domain_to_response_schema(appt) for appt in appointments]
# --- END NEW Endpoint --- 

# Add Pydantic schema for status update
class PendingContactStatusUpdateSchema(BaseModel):
    status: str = Field(..., description="The new status for the pending contact (e.g., 'ignored', 'added')")

@router.patch(
    "/pending-contacts/{pending_contact_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Update Pending Contact Status",
    description="Updates the status of a specific pending contact (e.g., to 'ignored' or 'added')."
)
@inject
async def update_pending_contact_status(
    pending_contact_id: str,
    update_data: PendingContactStatusUpdateSchema = Body(...),
    user_ctx: UserContext = Depends(verify_firebase_token),
    repo: PendingContactRepository = Depends(Provide[Container.pending_contact_repository])
):
    """Updates the status of a pending contact for the user."""
    try:
        updated_contact = await repo.update_status(
            user_id=user_ctx.user_id,
            pending_contact_id=pending_contact_id,
            status=update_data.status
        )
        if not updated_contact:
            # This case might indicate the contact was not found or user not authorized
            # The repository should ideally raise a specific exception handled below
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Pending contact not found or user not authorized to update."
            )
        # On success, HTTP 204 No Content is returned automatically
        return
    except FileNotFoundError: # Assuming repo might raise this
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Pending contact not found."
        )
    except PermissionError: # Assuming repo might raise this for auth issues
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User not authorized to update this pending contact."
        )
    except Exception as e:
        # Log the exception e here if logging is set up
        logger = logging.getLogger(__name__) # Get logger instance
        logger.error(f"PATCH /pending-contacts/{pending_contact_id} - Unhandled exception: {type(e).__name__} - {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"An unexpected error occurred while updating pending contact: {str(e)}"
        )
