from fastapi import APIRouter, Depends, HTTPException, status, Header, BackgroundTasks
from pydantic import BaseModel, Field, EmailStr
import firebase_admin.auth
from firebase_admin.auth import UserRecord
from google.cloud.firestore_v1.async_client import AsyncClient
from dependency_injector.wiring import inject, Provide
import logging
import uuid
from datetime import datetime, timezone
from typing import List, Optional, Dict

# Import container and dependencies
from assiist_back_end.containers import Container
from assiist_back_end.api.endpoints.v1.dependencies import verify_firebase_token, verify_internal_secret, UserContext
from assiist_back_end.models.user_settings_models import ContactSyncSettingsRequest, ContactSyncSettingsResponse
from .text_message_examples import router as text_message_examples_router

# --- Request/Response Models ---

# User schemas
from assiist_back_end.api.schemas.user import (
    UserCreateRequest,
    UserCreateResponse,
    UserUpdateRequest,
    UserResponse
)

# --- Router ---

# Public routes with Firebase auth
router = APIRouter(
    prefix="/users",
    tags=["Users"],
    dependencies=[Depends(verify_firebase_token)]
)

router.include_router(text_message_examples_router)

# Internal routes with API key auth
internal_router = APIRouter(
    prefix="/internal/users",
    tags=["Users"],
    dependencies=[Depends(verify_internal_secret)]
)

logger = logging.getLogger(__name__)

# --- Public Endpoints ---

@router.patch(
    "/settings/contact-sync",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Update Contact Sync Settings (partial)",
    description="Save or update the user's contact synchronization preferences and conflict resolution priority.",
)
@inject
async def update_contact_sync_settings(
    settings_data: ContactSyncSettingsRequest,
    user_ctx: UserContext = Depends(verify_firebase_token),
    db: AsyncClient = Depends(Provide[Container.firestore_async_client]),
):
    """Update user's contact sync settings."""
    user_settings_ref = db.collection("users").document(user_ctx.user_id)
    try:
        await user_settings_ref.set(
            {"settings": {"contact_sync": settings_data.model_dump(exclude_none=True)}},
            merge=True,
        )
        return None  # For HTTP 204
    except Exception as e:
        logger.error(f"Error updating contact sync settings: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Could not update contact sync settings.",
        )

@router.get(
    "/settings/contact-sync",
    response_model=Optional[ContactSyncSettingsResponse],
    status_code=status.HTTP_200_OK,
    summary="Get Contact Sync Settings",
    description="Retrieve the user's contact synchronization preferences and conflict resolution priority.",
)
@inject
async def get_contact_sync_settings(
    user_ctx: UserContext = Depends(verify_firebase_token),
    db: AsyncClient = Depends(Provide[Container.firestore_async_client]),
) -> Optional[ContactSyncSettingsResponse]:
    """Get user's contact sync settings."""
    user_doc_ref = db.collection("users").document(user_ctx.user_id)
    try:
        user_doc = await user_doc_ref.get(field_paths=["settings.contact_sync"])
        if user_doc.exists:
            user_data = user_doc.to_dict()
            contact_sync_settings = user_data.get("settings", {}).get("contact_sync")
            if contact_sync_settings:
                return ContactSyncSettingsResponse(**contact_sync_settings)
        return None # Return None if settings or user doc don't exist
    except Exception as e:
        logger.error(f"Error retrieving contact sync settings for user {user_ctx.user_id}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Could not retrieve contact sync settings.",
        )

@router.get(
    "/{user_id}",
    response_model=UserResponse,
    status_code=status.HTTP_200_OK,
    summary="Get user profile",
    description="Retrieves a user's profile from Firestore.",
)
@inject
async def get_user(
    user_id: str,
    user_ctx: UserContext = Depends(verify_firebase_token),
    db: AsyncClient = Depends(Provide[Container.firestore_async_client]),
):
    """Get user's profile."""
    user_ref = db.collection("users").document(user_id)
    user_doc = await user_ref.get()
    
    if not user_doc.exists:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User profile not found."
        )
    
    user_data = user_doc.to_dict()
    return UserResponse(
        id=user_id,
        email=user_data.get("email"),
        first_name=user_data.get("first_name"),
        last_name=user_data.get("last_name"),
        account_id=user_data.get("account_id"),
        member_account_ids=user_data.get("member_account_ids", [])
    )

# --- Internal Endpoints ---

@internal_router.get(
    "/",
    response_model=List[dict],  # Change to dict to include enriched data
    status_code=status.HTTP_200_OK,
    summary="Get all users",
    description="Retrieves all users from Firestore for admin portal with enriched account information.",
)
@inject
async def get_all_users(
    db: AsyncClient = Depends(Provide[Container.firestore_async_client]),
):
    """Get all users for admin portal with enriched account information."""
    try:
        users_ref = db.collection("users")
        users_docs = users_ref.stream()
        
        users = []
        async for user_doc in users_docs:
            if user_doc.exists:
                user_data = user_doc.to_dict()
                
                # Get account information if account_id exists
                account_info = None
                if user_data.get("account_id"):
                    try:
                        account_ref = db.collection("accounts").document(user_data["account_id"])
                        account_doc = await account_ref.get()
                        if account_doc.exists:
                            account_data = account_doc.to_dict()
                            account_info = {
                                "id": user_data["account_id"],
                                "account_name": account_data.get("account_name", "Unnamed Account")
                            }
                    except Exception as account_error:
                        logger.warning(f"Failed to fetch account info for user {user_doc.id}: {account_error}")
                
                # Convert Firestore timestamps to ISO strings for JSON serialization
                created_on = user_data.get("created_on")
                updated_on = user_data.get("updated_on")
                
                # Convert Firestore Timestamp objects to ISO strings
                if created_on and hasattr(created_on, 'isoformat'):
                    created_on = created_on.isoformat()
                elif created_on:
                    created_on = created_on.isoformat() if hasattr(created_on, 'isoformat') else str(created_on)
                    
                if updated_on and hasattr(updated_on, 'isoformat'):
                    updated_on = updated_on.isoformat()
                elif updated_on:
                    updated_on = updated_on.isoformat() if hasattr(updated_on, 'isoformat') else str(updated_on)

                # Build enriched user data
                enriched_user = {
                    "id": user_doc.id,
                    "email": user_data.get("email", ""),
                    "first_name": user_data.get("first_name", ""),
                    "last_name": user_data.get("last_name", ""),
                    "account_id": user_data.get("account_id", ""),
                    "member_account_ids": user_data.get("member_account_ids", []),
                    "created_on": created_on,
                    "updated_on": updated_on,
                    "account_info": account_info
                }
                
                users.append(enriched_user)
        
        logger.info(f"Retrieved {len(users)} users with enriched account information for admin portal")
        return users
        
    except Exception as e:
        logger.error(f"Error fetching all users: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve users."
        )

@internal_router.post(
    "/",
    response_model=UserCreateResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new user and associated account",
    description="Creates a Firebase user and corresponding Firestore user/account documents.",
)
@inject
async def create_user(
    request: UserCreateRequest,
    db: AsyncClient = Depends(Provide[Container.firestore_async_client]),
):
    """Creates a Firebase user and corresponding Firestore user/account documents."""
    logger.info(f"Attempting user creation for email: {request.email}")

    # --- 1. Create Firebase Auth User ---
    try:
        # Calculate display name for Firebase Auth from first_name and last_name
        display_name = f"{request.first_name or ''} {request.last_name or ''}".strip() or request.email
        user_record: UserRecord = firebase_admin.auth.create_user(
            email=request.email,
            password=request.password,
            display_name=display_name,
            email_verified=False
        )
        uid = user_record.uid
        logger.info(f"Firebase user created successfully with uid: {uid}")

    except firebase_admin.auth.EmailAlreadyExistsError:
        logger.warning(f"Firebase Auth email already exists: {request.email}")
        
        # Check if there's a corresponding Firestore user document
        try:
            # Get the existing Firebase user to get their UID
            existing_user = firebase_admin.auth.get_user_by_email(request.email)
            uid = existing_user.uid
            
            # Check if Firestore document exists
            user_ref = db.collection("users").document(uid)
            user_doc = await user_ref.get()
            
            if user_doc.exists:
                # Both Firebase Auth and Firestore user exist - this is a legitimate conflict
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=f"The email '{request.email}' is already registered.",
                )
            else:
                # Orphaned Firebase Auth user exists - delete it and recreate both
                logger.info(f"Found orphaned Firebase Auth user for {request.email}, cleaning up and recreating")
                firebase_admin.auth.delete_user(uid)
                
                # Retry user creation with the same parameters
                display_name = f"{request.first_name or ''} {request.last_name or ''}".strip() or request.email
                user_record: UserRecord = firebase_admin.auth.create_user(
                    email=request.email,
                    password=request.password,
                    display_name=display_name,
                    email_verified=False
                )
                uid = user_record.uid
                logger.info(f"Firebase user recreated successfully with uid: {uid}")
                
        except firebase_admin.auth.UserNotFoundError:
            # This shouldn't happen since we just got EmailAlreadyExistsError, but handle it gracefully
            logger.error(f"Inconsistent state: EmailAlreadyExistsError but user not found for {request.email}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Authentication system is in an inconsistent state. Please try again.",
            )
    except Exception as e:
        logger.error(f"Error creating Firebase user for {request.email}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create user in authentication system.",
        )

    # --- 2. Create Firestore Documents (User & Optionally Account) ---
    user_ref = db.collection("users").document(uid)
    now = datetime.now(timezone.utc)
    
    # Determine primary account_id
    if request.account_id:
        # Add user to existing account as primary
        target_account_id = request.account_id
        logger.info(f"Adding user {uid} to existing account {target_account_id} as primary")
        
        # Verify primary account exists and check if it needs an owner
        account_ref = db.collection("accounts").document(target_account_id)
        account_doc = await account_ref.get()
        if not account_doc.exists:
            # Cleanup Firebase user
            try:
                firebase_admin.auth.delete_user(uid)
            except Exception:
                pass
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Primary account with ID '{target_account_id}' does not exist.",
            )
        
        # Check if account has no owner and make this user the owner
        account_data = account_doc.to_dict()
        should_set_as_owner = not account_data.get("owner_id")
        if should_set_as_owner:
            logger.info(f"Account {target_account_id} has no owner, setting user {uid} as owner")
    else:
        # Create new account for user as primary
        target_account_id = str(uuid.uuid4())
        logger.info(f"Creating new account {target_account_id} for user {uid} as primary")
    
    # Verify all member accounts exist
    valid_member_account_ids = []
    if request.member_account_ids:
        for member_account_id in request.member_account_ids:
            if member_account_id == target_account_id:
                continue  # Skip primary account if it's also in member list
            member_account_ref = db.collection("accounts").document(member_account_id)
            member_account_doc = await member_account_ref.get()
            if member_account_doc.exists:
                valid_member_account_ids.append(member_account_id)
            else:
                logger.warning(f"Member account {member_account_id} does not exist, skipping")
        logger.info(f"User {uid} will be member of {len(valid_member_account_ids)} additional accounts")

    try:
        # Common user data
        user_data = {
            "id": uid,   # New standardized primary key field
            "email": request.email,
            "first_name": request.first_name or "",
            "last_name": request.last_name or "",
            "created_on": now,
            "updated_on": now,
            "account_id": target_account_id,
            "member_account_ids": valid_member_account_ids,
        }
        
        if request.account_id:
            # Create user document for existing account
            if should_set_as_owner:
                # Use batch to atomically create user and update account ownership
                batch = db.batch()
                batch.set(user_ref, user_data)
                batch.update(account_ref, {
                    "owner_id": uid,
                    "updated_on": now
                })
                await batch.commit()
                logger.info(f"Successfully created user {uid} and set as owner of account {target_account_id} with {len(valid_member_account_ids)} member accounts")
            else:
                # Just create user document
                await user_ref.set(user_data)
                logger.info(f"Successfully created user {uid} in existing account {target_account_id} with {len(valid_member_account_ids)} member accounts")
        else:
            # Create both user and account atomically
            batch = db.batch()
            account_ref = db.collection("accounts").document(target_account_id)
            
            # User document
            batch.set(user_ref, user_data)
            
            # Account document
            account_data = {
                "owner_id": uid,
                "account_name": f"Account {uid[:8]}",  # Use uid prefix instead of display name
                "created_on": now,
                "updated_on": now,
            }
            batch.set(account_ref, account_data)
            
            # Commit the batch
            await batch.commit()
            logger.info(f"Successfully created user {uid} and new account {target_account_id} with {len(valid_member_account_ids)} member accounts")

    except Exception as e:
        logger.error(f"Error creating Firestore documents for user {uid}: {e}", exc_info=True)
        # Attempt to clean up the created Firebase user if Firestore fails
        try:
            firebase_admin.auth.delete_user(uid)
            logger.warning(f"Rolled back Firebase user creation for {uid} due to Firestore error.")
        except Exception as delete_error:
            logger.error(f"Failed to rollback Firebase user {uid} after Firestore error: {delete_error}", exc_info=True)

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create user records in database.",
        )

    return UserCreateResponse(id=uid, account_id=target_account_id)

@internal_router.patch(
    "/{user_id}",
    response_model=UserResponse,
    status_code=status.HTTP_200_OK,
    summary="Update user profile",
    description="Updates Firebase Auth user and corresponding Firestore user document.",
)
@inject
async def update_user(
    user_id: str,
    request: UserUpdateRequest,
    db: AsyncClient = Depends(Provide[Container.firestore_async_client]),
):
    """Updates a user's profile information in both Firebase Auth and Firestore."""
    logger.info(f"Attempting user update for uid: {user_id}")

    # Check if there's anything to update
    update_data_auth = request.model_dump(exclude_unset=True)
    update_data_firestore = update_data_auth.copy()

    if not update_data_auth:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No update data provided."
        )

    # --- 1. Update Firebase Auth User ---
    try:
        updated_user_record = firebase_admin.auth.update_user(
            uid=user_id,
            **update_data_auth
        )
        logger.info(f"Firebase user updated successfully for uid: {user_id}")

    except firebase_admin.auth.UserNotFoundError:
        logger.warning(f"User not found in Firebase Auth for update: {user_id}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"User with ID '{user_id}' not found."
        )
    except Exception as e:
        logger.error(f"Error updating Firebase user {user_id}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update user in authentication system."
        )

    # --- 2. Update Firestore User Document ---
    if update_data_firestore:
        user_ref = db.collection("users").document(user_id)
        try:
            await user_ref.update(update_data_firestore)
            logger.info(f"Firestore user document updated successfully for uid: {user_id}")

            # Get updated data to return
            updated_doc = await user_ref.get()
            if updated_doc.exists:
                updated_user_firestore_data = updated_doc.to_dict()
                return UserResponse(
                    id=updated_user_record.uid,
                    email=updated_user_record.email,
                    first_name=updated_user_firestore_data.get("first_name"),
                    last_name=updated_user_firestore_data.get("last_name"),
                    account_id=updated_user_firestore_data.get("account_id", "N/A"),
                    member_account_ids=updated_user_firestore_data.get("member_account_ids", [])
                )
            else:
                logger.error(f"Firestore document for user {user_id} disappeared after update attempt.")
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="User updated, but failed to retrieve full updated details."
                )

        except Exception as e:
            logger.error(f"Error updating Firestore user document for {user_id}: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to update user record in database."
            )

@internal_router.delete(
    "/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Soft delete a user",
    description="Marks a user as deleted by setting is_deleted=True, deleted_on timestamp, and deleted_by user_id."
)
@inject
async def soft_delete_user(
    user_id: str,
    request: dict,
    db: AsyncClient = Depends(Provide[Container.firestore_async_client]),
):
    """Soft delete a user following the standard pattern."""
    logger.info(f"Attempting to soft delete user: {user_id}")
    
    # Extract deleter_user_id from request body
    deleter_user_id = request.get("deleter_user_id")
    if not deleter_user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="deleter_user_id is required in request body"
        )
    
    try:
        user_ref = db.collection("users").document(user_id)
        user_doc = await user_ref.get()
        
        if not user_doc.exists:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"User {user_id} not found"
            )
        
        # Check if already deleted
        user_data = user_doc.to_dict()
        if user_data.get("is_deleted", False):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"User {user_id} is already deleted"
            )
        
        # Perform soft delete using standard fields (following implementation guide)
        soft_delete_data = {
            "is_deleted": True,
            "deleted_on": datetime.now(timezone.utc),  # ⚠️ Using *_on suffix per guide
            "deleted_by": deleter_user_id,
            "updated_on": datetime.now(timezone.utc),
            "updated_by": deleter_user_id
        }
        
        await user_ref.update(soft_delete_data)
        logger.info(f"User {user_id} soft deleted successfully by user {deleter_user_id}")
        
        # Note: We're NOT deleting from Firebase Auth - this is just a Firestore soft delete
        # Firebase Auth user remains active for potential account recovery
        
        return  # Return None for 204 status
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error soft deleting user {user_id}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete user from database.",
        ) 