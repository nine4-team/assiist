from fastapi import APIRouter, Depends, HTTPException, status, Query, Body
from typing import List, Optional
from dependency_injector.wiring import inject, Provide

from assiist_back_end.containers import Container
from assiist_back_end.db.repositories.interfaces.reservation_repository import ReservationRepository
from assiist_back_end.models.reservation import Reservation
from assiist_back_end.api.endpoints.v1.dependencies import verify_firebase_token, UserContext
from assiist_back_end.api.endpoints.v1.mappers import (
    map_reservation_create_schema_to_domain,
    map_reservation_domain_to_response_schema,
    map_reservation_update_schema_to_dict
)
from assiist_back_end.api.schemas.reservation import (
    ReservationCreateSchema,
    ReservationResponseSchema,
    ReservationUpdateSchema
)

router = APIRouter(tags=["Reservations"])

@router.post("", response_model=ReservationResponseSchema, status_code=status.HTTP_201_CREATED)
@inject
async def create_reservation(
    reservation: ReservationCreateSchema = Body(...),
    reservation_repo: ReservationRepository = Depends(Provide[Container.reservation_repository]),
    user_ctx: UserContext = Depends(verify_firebase_token)
):
    """Creates a new reservation for the authenticated user's account."""
    try:
        if reservation.account_id != user_ctx.account_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to create reservations for this account"
            )
        
        if await reservation_repo.exists(reservation.contact_id, reservation.account_id):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Reservation already exists for this contact"
            )
        
        domain_reservation = map_reservation_create_schema_to_domain(reservation, user_ctx.user_id)
        domain_reservation.created_by = user_ctx.user_id
        domain_reservation.updated_by = user_ctx.user_id
        
        created_reservation = await reservation_repo.create(domain_reservation)
        return map_reservation_domain_to_response_schema(created_reservation)
    except HTTPException as e:
        raise e
    except Exception as e:
        print(f"Error in create_reservation endpoint: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while creating the reservation"
        )

@router.get("", response_model=List[ReservationResponseSchema])
@inject
async def get_reservations(
    reservation_repo: ReservationRepository = Depends(Provide[Container.reservation_repository]),
    user_ctx: UserContext = Depends(verify_firebase_token),
    user_id: Optional[str] = Query(None),
    contact_id: Optional[str] = Query(None)
):
    """Retrieves reservations for the authenticated user's account."""
    try:
        filters = {}
        if user_id:
            filters["user_id"] = user_id
        if contact_id:
            filters["contact_id"] = contact_id
        
        reservations = await reservation_repo.get_by_account(user_ctx.account_id, filters)
        return [map_reservation_domain_to_response_schema(reservation) for reservation in reservations]
    except Exception as e:
        print(f"Error in get_reservations endpoint: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while retrieving reservations"
        )

@router.get("/{reservation_id}", response_model=ReservationResponseSchema)
@inject
async def get_reservation(
    reservation_id: str,
    reservation_repo: ReservationRepository = Depends(Provide[Container.reservation_repository]),
    user_ctx: UserContext = Depends(verify_firebase_token)
):
    """Retrieves a specific reservation by ID."""
    try:
        reservation = await reservation_repo.get_by_id(reservation_id)
        if not reservation:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Reservation not found"
            )
        if reservation.account_id != user_ctx.account_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to access this reservation"
            )
        return map_reservation_domain_to_response_schema(reservation)
    except HTTPException as e:
        raise e
    except Exception as e:
        print(f"Error in get_reservation endpoint: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while retrieving the reservation"
        )

@router.patch("/{reservation_id}", response_model=ReservationResponseSchema)
@inject
async def update_reservation(
    reservation_id: str,
    reservation: ReservationUpdateSchema = Body(...),
    reservation_repo: ReservationRepository = Depends(Provide[Container.reservation_repository]),
    user_ctx: UserContext = Depends(verify_firebase_token)
):
    """Updates a specific reservation."""
    try:
        existing_reservation = await reservation_repo.get_by_id(reservation_id)
        if not existing_reservation:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Reservation not found"
            )
        if existing_reservation.account_id != user_ctx.account_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to update this reservation"
            )
        
        update_data = map_reservation_update_schema_to_dict(reservation)
        update_data["updated_by"] = user_ctx.user_id
        
        updated_reservation = await reservation_repo.update(reservation_id, update_data)
        return map_reservation_domain_to_response_schema(updated_reservation)
    except HTTPException as e:
        raise e
    except Exception as e:
        print(f"Error in update_reservation endpoint: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while updating the reservation"
        )

@router.delete("/{reservation_id}", status_code=status.HTTP_204_NO_CONTENT)
@inject
async def delete_reservation(
    reservation_id: str,
    reservation_repo: ReservationRepository = Depends(Provide[Container.reservation_repository]),
    user_ctx: UserContext = Depends(verify_firebase_token)
):
    """Deletes a specific reservation."""
    try:
        reservation = await reservation_repo.get_by_id(reservation_id)
        if not reservation:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Reservation not found"
            )
        if reservation.account_id != user_ctx.account_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to delete this reservation"
            )
        
        success = await reservation_repo.delete(reservation_id)
        if not success:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to delete reservation"
            )
    except HTTPException as e:
        raise e
    except Exception as e:
        print(f"Error in delete_reservation endpoint: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while deleting the reservation"
        ) 