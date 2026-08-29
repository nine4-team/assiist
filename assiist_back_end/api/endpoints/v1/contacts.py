from fastapi import APIRouter, Depends, HTTPException, status, Query, Body
from typing import List, Optional
from dependency_injector.wiring import inject, Provide

# Import your container and domain models
from assiist_back_end.containers import Container
# from core.models.contact import Contact # Not needed directly in endpoints anymore
from assiist_back_end.db.repositories.interfaces.contact_repository import ContactRepository
# Import the Pydantic Schemas
from assiist_back_end.api.schemas.contact import ContactCreateSchema, ContactResponseSchema, ContactUpdateSchema
# Import the mappers
from assiist_back_end.api.endpoints.v1.mappers import map_create_schema_to_domain, map_domain_to_response_schema, map_update_schema_to_dict
# --- Import the REAL authentication dependency ---
from assiist_back_end.api.endpoints.v1.dependencies import verify_firebase_token, UserContext
# from services.firestore_service import FirestoreService  # Adjust path if needed

# Create a router (Top level for contacts now)
router = APIRouter(
    # prefix="/users/{user_id}/contacts", # Prefix moved to main app setup likely
    tags=["Contacts"] # For API docs organization
)

# --- Move Search Endpoint Up --- #
@router.get(
    "/search",
    response_model=List[ContactResponseSchema],
    summary="Search contacts using Algolia"
)
@inject
async def search_contacts(
    query: str = Query(..., min_length=1, description="Search term for contacts"),
    limit: int = Query(10, gt=0, le=50, description="Maximum number of results to return"),
    offset: int = Query(0, ge=0, description="Offset for pagination"),
    contact_repo: ContactRepository = Depends(Provide[Container.contact_repository]),
    user_ctx: UserContext = Depends(verify_firebase_token),
) -> List[ContactResponseSchema]:
    """Searches contacts for the user's account using the configured search provider (Algolia)."""
    try:
        contacts_domain = await contact_repo.search_contacts_by_account( 
            account_id=user_ctx.account_id, 
            search_term=query, 
            limit=limit, 
            offset=offset
        )
        return [map_domain_to_response_schema(contact) for contact in contacts_domain]
    except HTTPException as e:
        raise e
    except Exception as e:
        print(f"Error in contact search endpoint: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"An unexpected error occurred during search: {e}"
        )
# --- END Moved Search Endpoint --- #

# Define endpoint to get a contact by ID
@router.get(
    "/{contact_id}",
    response_model=ContactResponseSchema,
    summary="Get a specific contact by ID"
)
@inject
async def get_contact(
    contact_id: str, # Removed user_id path parameter
    contact_repo: ContactRepository = Depends(Provide[Container.contact_repository]),
    # --- Use the REAL authentication dependency ---
    user_ctx: UserContext = Depends(verify_firebase_token),
) -> ContactResponseSchema:
    """Fetches details for a specific contact, checking account ownership."""
    # Use account_id from context for the repository call
    contact = await contact_repo.get_contact_by_id(
        account_id=user_ctx.account_id, # Pass account_id from context
        contact_id=contact_id
    )
    if contact is None or contact.is_deleted:
        # Check account_id in repo ensures this is either not found or not authorized
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Contact not found")
    # Use the dedicated mapper to convert domain object to response schema
    return map_domain_to_response_schema(contact)

# Endpoint to get contacts for a user
@router.get(
    "",
    response_model=List[ContactResponseSchema],
    summary="List contacts for the current user's account"
)
@inject
async def list_user_contacts(
    limit: int = Query(50, gt=0, le=100),
    offset: int = Query(0, ge=0),
    contact_repo: ContactRepository = Depends(Provide[Container.contact_repository]),
    user_ctx: UserContext = Depends(verify_firebase_token),
) -> List[ContactResponseSchema]:
    """Retrieve contacts for the authenticated user's account."""
    # This endpoint now ONLY lists contacts, search is handled by /search
    print(f"Fetching contacts for account: {user_ctx.account_id}, limit: {limit}, offset: {offset}")
    contacts_domain = await contact_repo.get_contacts_by_account(
        account_id=user_ctx.account_id, limit=limit, offset=offset
    )
    return [map_domain_to_response_schema(contact) for contact in contacts_domain]

# Endpoint to create a contact for the current user's account
@router.post(
    "",
    response_model=ContactResponseSchema,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new contact"
)
@inject
async def create_contact(
    contact_in: ContactCreateSchema = Body(...),
    contact_repo: ContactRepository = Depends(Provide[Container.contact_repository]),
    # --- Use the REAL authentication dependency ---
    user_ctx: UserContext = Depends(verify_firebase_token),
) -> ContactResponseSchema:
    """Creates a new contact associated with the authenticated user's account."""
    try:
        # --- Duplicate Check: Email & Phone ---
        # Check for existing contact with any matching email address
        if contact_in.emails:
            for email_obj in contact_in.emails:
                existing = await contact_repo.get_contact_by_email(
                    account_id=user_ctx.account_id,
                    email=email_obj.address,
                )
                if existing and not existing.is_deleted:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail={
                            "code": "duplicate_contact",
                            "field": "email",
                            "value": email_obj.address,
                            "existing_contact_id": existing.id,
                        },
                    )

        # Check for existing contact with any matching phone number
        if contact_in.phone_numbers:
            for phone_obj in contact_in.phone_numbers:
                existing = await contact_repo.get_contact_by_phone(
                    account_id=user_ctx.account_id,
                    phone=phone_obj.number,
                )
                if existing and not existing.is_deleted:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail={
                            "code": "duplicate_contact",
                            "field": "phone",
                            "value": phone_obj.number,
                            "existing_contact_id": existing.id,
                        },
                    )

        # Map the input schema to the domain model using the imported mapper
        contact_domain = map_create_schema_to_domain(
            schema=contact_in,
            account_id=user_ctx.account_id,
            creator_user_id=user_ctx.user_id
        )

        # Call the repository to create the contact (repo needs account_id)
        created_contact = await contact_repo.create_contact(contact=contact_domain)

        # Map the resulting domain model back to the response schema
        return map_domain_to_response_schema(created_contact)

    except HTTPException as http_exc:
        # Re-throw HTTP errors such as duplicate-contact 409 so the client receives the correct code.
        raise http_exc
    except Exception as e:
        # Catch-all for other unexpected errors
        print(f"Error in create_contact endpoint: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while creating the contact."
        )

# Endpoint to update a contact
@router.patch(
    "/{contact_id}",
    response_model=ContactResponseSchema,
    summary="Update an existing contact"
)
@inject
async def update_contact(
    contact_id: str,
    contact_update: ContactUpdateSchema = Body(...),
    contact_repo: ContactRepository = Depends(Provide[Container.contact_repository]),
    # --- Use the REAL authentication dependency ---
    user_ctx: UserContext = Depends(verify_firebase_token),
) -> ContactResponseSchema:
    """Updates specific fields of an existing contact, checking account ownership."""
    updates_dict = map_update_schema_to_dict(contact_update, user_ctx.user_id)

    if not updates_dict:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No update data provided."
        )

    try:
        # Call the repository to update the contact
        updated_contact_domain = await contact_repo.update_contact(
            account_id=user_ctx.account_id,
            contact_id=contact_id,
            updates=updates_dict,
            updater_user_id=user_ctx.user_id
        )
        # Note: Repository now raises errors instead of returning None on failure
        # The check below is removed as the try/except handles failures

    except FileNotFoundError as e:
        # Repository raises FileNotFoundError if contact ID doesn't exist
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Contact not found: {e}" # Include original error message if desired
        )
    except PermissionError as e:
        # Repository raises PermissionError if account_id doesn't match
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"User not authorized to update this contact: {e}" # Include original error message if desired
        )
    except HTTPException as http_exc:
         # Re-raise HTTP exceptions directly (e.g., from bad request check)
         raise http_exc
    except Exception as e:
        # Catch any other unexpected errors from the repository or mapping
        print(f"Unexpected error during contact update: {e}") # Log for debugging
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"An unexpected error occurred during the update: {e}"
        )

    # If no exception was raised, the update was successful
    if updated_contact_domain is None:
         # This case should ideally not be reached if repo raises errors, but handle defensively
         print(f"Warning: update_contact repo call returned None unexpectedly for {contact_id}")
         raise HTTPException(status_code=500, detail="Update completed but failed to retrieve contact.")

    return map_domain_to_response_schema(updated_contact_domain)

# Endpoint to delete a contact
@router.delete(
    "/{contact_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a contact"
)
@inject
async def delete_contact(
    contact_id: str,
    hard_delete: bool = Query(False, description="If true, permanently deletes the contact. If false (default), performs soft delete."),
    contact_repo: ContactRepository = Depends(Provide[Container.contact_repository]),
    # --- Use the REAL authentication dependency ---
    user_ctx: UserContext = Depends(verify_firebase_token),
) -> None:
    """Deletes a contact, checking account ownership.
    
    By default performs a soft delete (marks as deleted but keeps the record).
    Set hard_delete=true to permanently remove the contact from the database.
    """
    try:
        # Call repo method, which now returns True on success or raises specific exceptions
        await contact_repo.delete_contact(
            account_id=user_ctx.account_id,
            contact_id=contact_id,
            deleter_user_id=user_ctx.user_id,
            hard_delete=hard_delete
        )
        # If no exception, return None for 204 response
        return

    except FileNotFoundError as e:
        # Repository raises FileNotFoundError if contact ID doesn't exist
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Contact not found: {e}"
        )
    except PermissionError as e:
        # Repository raises PermissionError if account_id doesn't match
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"User not authorized to delete this contact: {e}"
        )
    except HTTPException as http_exc:
        # Re-raise other HTTP exceptions if any were raised by repo
        raise http_exc
    except Exception as e:
        # Catch any other unexpected errors from the repository
        print(f"Unexpected error during contact delete endpoint: {e}") # Log for debugging
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"An unexpected error occurred during delete: {e}"
        )

