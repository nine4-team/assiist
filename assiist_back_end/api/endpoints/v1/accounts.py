from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from google.cloud.firestore_v1.async_client import AsyncClient
from dependency_injector.wiring import inject, Provide
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional, List

# Import container and dependencies
from assiist_back_end.containers import Container
from assiist_back_end.api.endpoints.v1.dependencies import verify_firebase_token, verify_internal_secret, UserContext
from assiist_back_end.models.account_models import AccountDetailsResponse, AccountDetailsUpdateRequest
from assiist_back_end.db.repositories.interfaces.account_repository import AccountRepository

# Account schemas
from assiist_back_end.api.schemas.account import (
    AccountCreateRequest,
    AccountCreateResponse,
    AccountResponse
)

# --- Router ---

# Public routes with Firebase auth
router = APIRouter(
    prefix="/accounts",
    tags=["Account"],
    dependencies=[Depends(verify_firebase_token)]
)

# Internal routes with API key auth
internal_router = APIRouter(
    prefix="/internal/accounts",
    tags=["Account"],
    dependencies=[Depends(verify_internal_secret)]
)

logger = logging.getLogger(__name__)

# Helper function for account creation that can be used by other modules
async def create_account(
    db: AsyncClient,
    account_name: str,
    owner_id: str | None = None,
    batch = None
) -> str:
    """
    Creates a Firestore account document.
    Can be used with or without a batch operation.
    Returns the new account ID.
    """
    new_account_id = str(uuid.uuid4())
    account_ref = db.collection("accounts").document(new_account_id)
    now = datetime.now(timezone.utc)

    account_data = {
        "account_name": account_name,
        "created_on": now,
        "updated_on": now,
    }
    
    if owner_id:
        account_data["owner_id"] = owner_id

    try:
        if batch:
            batch.set(account_ref, account_data)
            logger.debug(f"Batch: Added set operation for account {new_account_id}")
        else:
            await account_ref.set(account_data)
            logger.info(f"Successfully created Firestore account {new_account_id}")

    except Exception as e:
        logger.error(f"Error creating Firestore account document {new_account_id}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create account record in database.",
        )

    return new_account_id

# --- Public Endpoints ---

@router.get("/details", response_model=Optional[AccountDetailsResponse])
@inject
async def get_account_details_endpoint(
    user_ctx: UserContext = Depends(verify_firebase_token),
    account_repo: AccountRepository = Depends(Provide[Container.account_repository])
):
    """Fetch the current user's account details (business type and description)."""
    if not user_ctx.account_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account ID not found in user context.")
    
    details = await account_repo.get_account_details(account_id=user_ctx.account_id)
    if details is None:
        return AccountDetailsResponse(business_description=None, business_type=None) 
    return details

@router.put("/details", response_model=AccountDetailsResponse)
@inject
async def update_account_details_endpoint(
    update_request: AccountDetailsUpdateRequest,
    user_ctx: UserContext = Depends(verify_firebase_token),
    account_repo: AccountRepository = Depends(Provide[Container.account_repository])
):
    """Update the current user's account details (business type and/or description)."""
    if not user_ctx.account_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account ID not found in user context.")

    if update_request.business_description is None and update_request.business_type is None:
        current_details = await account_repo.get_account_details(account_id=user_ctx.account_id)
        if current_details is None:
             return AccountDetailsResponse(business_description=None, business_type=None)
        return current_details
        
    updated_details = await account_repo.update_account_details(
        account_id=user_ctx.account_id, 
        details=update_request
    )
    return updated_details

# --- Internal Endpoints ---

@internal_router.post(
    "/",
    response_model=AccountCreateResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new account",
    description="Creates a Firestore account document based on the provided business name.",
)
@inject
async def create_internal_account(
    request: AccountCreateRequest,
    db: AsyncClient = Depends(Provide[Container.firestore_async_client]),
):
    """Creates a Firestore account document."""
    logger.info(f"Attempting account creation for business: {request.business_name}")

    new_account_id = await create_account(
        db=db,
        account_name=request.business_name
    )

    return AccountCreateResponse(id=new_account_id)

@internal_router.get(
    "/",
    response_model=List[dict],  # Change to dict to include owner info
    summary="Get all accounts",
    description="Returns a list of all accounts in the system with owner information.",
)
@inject
async def get_all_accounts(
    db: AsyncClient = Depends(Provide[Container.firestore_async_client]),
):
    """Get all accounts from Firestore with enriched owner information."""
    logger.info("Fetching all accounts with owner information")
    
    try:
        accounts_ref = db.collection("accounts")
        docs = await accounts_ref.get()
        
        accounts = []
        for doc in docs:
            if doc.exists:
                account_data = doc.to_dict()
                # Add document ID as id field
                account_data["id"] = doc.id
                
                # Ensure required fields exist
                if "created_on" not in account_data:
                    account_data["created_on"] = datetime.now(timezone.utc)
                if "updated_on" not in account_data:
                    account_data["updated_on"] = account_data.get("created_on", datetime.now(timezone.utc))
                if "account_name" not in account_data:
                    account_data["account_name"] = "Unnamed Account"
                
                # Enrich with owner information if owner_id exists
                owner_info = None
                if account_data.get("owner_id"):
                    try:
                        user_ref = db.collection("users").document(account_data["owner_id"])
                        user_doc = await user_ref.get()
                        if user_doc.exists:
                            user_data = user_doc.to_dict()
                            owner_info = {
                                "id": account_data["owner_id"],
                                "first_name": user_data.get("first_name", ""),
                                "last_name": user_data.get("last_name", ""),
                                "email": user_data.get("email", "")
                            }
                    except Exception as owner_error:
                        logger.warning(f"Failed to fetch owner info for account {doc.id}: {owner_error}")
                
                # Add owner info to account data
                account_data["owner_info"] = owner_info
                accounts.append(account_data)
        
        logger.info(f"Retrieved {len(accounts)} accounts with owner information")
        return accounts
        
    except Exception as e:
        logger.error(f"Error fetching accounts: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch accounts from database.",
        )

@internal_router.patch(
    "/{account_id}/owner",
    status_code=status.HTTP_200_OK,
    summary="Update account owner",
    description="Sets or updates the owner of an account."
)
@inject
async def update_account_owner(
    account_id: str,
    request: dict,
    db: AsyncClient = Depends(Provide[Container.firestore_async_client]),
):
    """Update account ownership."""
    logger.info(f"Attempting to update owner for account: {account_id}")
    
    new_owner_id = request.get("owner_id")
    if not new_owner_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="owner_id is required in request body"
        )
    
    try:
        # Verify account exists
        account_ref = db.collection("accounts").document(account_id)
        account_doc = await account_ref.get()
        
        if not account_doc.exists:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Account {account_id} not found"
            )
        
        # Verify user exists and is associated with this account
        user_ref = db.collection("users").document(new_owner_id)
        user_doc = await user_ref.get()
        
        if not user_doc.exists:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"User {new_owner_id} not found"
            )
        
        user_data = user_doc.to_dict()
        if user_data.get("account_id") != account_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"User {new_owner_id} is not associated with account {account_id}"
            )
        
        # Update account ownership
        await account_ref.update({
            "owner_id": new_owner_id,
            "updated_on": datetime.now(timezone.utc)
        })
        
        logger.info(f"Account {account_id} owner updated to user {new_owner_id}")
        return {"success": True, "message": f"Account owner updated to {new_owner_id}"}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error updating account owner {account_id}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update account owner.",
        )

@internal_router.delete(
    "/{account_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Soft delete an account",
    description="Marks an account as deleted by setting is_deleted=True, deleted_on timestamp, and deleted_by user_id."
)
@inject
async def soft_delete_account(
    account_id: str,
    request: dict,
    db: AsyncClient = Depends(Provide[Container.firestore_async_client]),
):
    """Soft delete an account following the standard pattern."""
    logger.info(f"Attempting to soft delete account: {account_id}")
    
    # Extract deleter_user_id from request body
    deleter_user_id = request.get("deleter_user_id")
    if not deleter_user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="deleter_user_id is required in request body"
        )
    
    try:
        account_ref = db.collection("accounts").document(account_id)
        account_doc = await account_ref.get()
        
        if not account_doc.exists:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Account {account_id} not found"
            )
        
        # Check if already deleted
        account_data = account_doc.to_dict()
        if account_data.get("is_deleted", False):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Account {account_id} is already deleted"
            )
        
        # Perform soft delete using standard fields (following implementation guide)
        soft_delete_data = {
            "is_deleted": True,
            "deleted_on": datetime.now(timezone.utc),  # ⚠️ Using *_on suffix per guide
            "deleted_by": deleter_user_id,
            "updated_on": datetime.now(timezone.utc),
            "updated_by": deleter_user_id
        }
        
        await account_ref.update(soft_delete_data)
        logger.info(f"Account {account_id} soft deleted successfully by user {deleter_user_id}")
        
        return  # Return None for 204 status
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error soft deleting account {account_id}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete account from database.",
        ) 