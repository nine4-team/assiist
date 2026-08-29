from fastapi import APIRouter, Depends, status, Header, HTTPException
from dependency_injector.wiring import inject, Provide
from assiist_back_end.containers import Container
from assiist_back_end.db.repositories.interfaces.user_metrics_repository import UserMetricsRepository
from assiist_back_end.models.user_metrics import UserMetrics
from assiist_back_end.api.endpoints.v1.dependencies import verify_firebase_token, verify_contact_ownership, UserContext

router = APIRouter(prefix="/metrics", tags=["Metrics"])

@router.post("/contacts/{contact_id}/messages", status_code=status.HTTP_204_NO_CONTENT)
@inject
async def increment_messages_sent(
    contact_id: str,
    idempotency_key: str = Header(..., alias="Idempotency-Key"),
    user_ctx: UserContext = Depends(verify_firebase_token),
    verified_contact = Depends(verify_contact_ownership),
    repo: UserMetricsRepository = Depends(Provide[Container.user_metrics_repository])
):
    """Increment the messages sent metric for a user/contact."""
    await repo.increment_messages_sent(user_ctx.user_id, contact_id, idempotency_key)

@router.post("/contacts/{contact_id}/notes", status_code=status.HTTP_204_NO_CONTENT)
@inject
async def increment_notes_logged(
    contact_id: str,
    user_ctx: UserContext = Depends(verify_firebase_token),
    verified_contact = Depends(verify_contact_ownership),
    repo: UserMetricsRepository = Depends(Provide[Container.user_metrics_repository])
):
    """Increment the notes logged metric for a user/contact."""
    await repo.increment_notes_logged(user_ctx.user_id, contact_id)

@router.get("/contacts/{contact_id}", response_model=UserMetrics)
@inject
async def get_metrics_for_contact(
    contact_id: str,
    user_ctx: UserContext = Depends(verify_firebase_token),
    verified_contact = Depends(verify_contact_ownership),
    repo: UserMetricsRepository = Depends(Provide[Container.user_metrics_repository])
):
    """Get metrics for a specific contact."""
    return await repo.get_metrics_for_contact(user_ctx.user_id, contact_id)

@router.get("/total")
@inject
async def get_metrics_for_user(
    user_ctx: UserContext = Depends(verify_firebase_token),
    repo: UserMetricsRepository = Depends(Provide[Container.user_metrics_repository])
):
    """Get total metrics for a user."""
    return await repo.get_metrics_for_user(user_ctx.user_id) 