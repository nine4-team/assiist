from datetime import datetime
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from dependency_injector.wiring import inject, Provide

from assiist_back_end.containers import Container
from assiist_back_end.db.repositories.interfaces.contact_repository import ContactRepository
from assiist_back_end.schemas.contact_sync import (
    IncrementalSyncRequest,
    IncrementalSyncResponse,
)
from assiist_back_end.api.endpoints.v1.dependencies import (
    verify_firebase_token,
    UserContext,
)

from google.cloud.firestore_v1 import AsyncClient  # type: ignore


router = APIRouter(prefix="/contact_sync", tags=["Contact Sync"])


@router.post(
    "/sync/incremental",
    response_model=IncrementalSyncResponse,
    summary="Perform an incremental contact sync (lean version)",
    status_code=status.HTTP_200_OK,
)
@inject
async def incremental_contact_sync(
    payload: IncrementalSyncRequest,
    contact_repo: ContactRepository = Depends(Provide[Container.contact_repository]),
    user_ctx: UserContext = Depends(verify_firebase_token),
    db: AsyncClient = Depends(Provide[Container.firestore_async_client]),
) -> IncrementalSyncResponse:
    """Handles incremental contact synchronisation.

    1. Apply client-side changes (TODO – currently stubbed).
    2. Return server-side changes since the provided `last_sync_ts`.
    """

    # ------------------------------------------------------------------
    # 1) Apply client-side changes – STUB (handled later)
    # ------------------------------------------------------------------
    try:
        for contact in payload.client_changes:
            # Upsert logic – placeholder; we assume client passes full Contact model.
            existing = await contact_repo.get_contact_by_id(
                account_id=user_ctx.account_id,
                contact_id=contact.id,
            ) if contact.id else None

            if existing:
                # Simple timestamp comparison; overwrite if client newer.
                if contact.is_deleted:
                    # Client deleted contact – propagate soft delete on server
                    await contact_repo.delete_contact(
                        account_id=user_ctx.account_id,
                        contact_id=existing.id,
                        deleter_user_id=user_ctx.user_id,
                        hard_delete=False,
                    )
                elif contact.updated_on and (
                    not existing.updated_on or contact.updated_on > existing.updated_on
                ):
                    # Convert to dict and save – ignoring immutable fields.
                    updates = contact.model_dump(exclude={"id"}, exclude_none=True)
                    await contact_repo.update_contact(
                        account_id=user_ctx.account_id,
                        contact_id=existing.id,
                        updates=updates,
                        updater_user_id=user_ctx.user_id,
                    )
            else:
                if contact.is_deleted:
                    # Contact deleted on device but not present on server – nothing to do.
                    continue
                # Create – ensure account_id is set
                contact.account_id = user_ctx.account_id
                await contact_repo.create_contact(contact)
    except Exception as e:
        print(f"Error applying client changes during incremental sync: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to apply client-side changes during sync.",
        )

    # ------------------------------------------------------------------
    # 2) Return server-side changes since last_sync_ts
    # ------------------------------------------------------------------
    last_ts = payload.last_sync_ts or datetime(1970, 1, 1)
    server_changes: List = await contact_repo.get_contacts_changed_since(
        account_id=user_ctx.account_id,
        timestamp=last_ts,
    )

    # ------------------------------------------------------------------
    # 3) Persist last_successful_sync_ts for the user
    # ------------------------------------------------------------------
    try:
        now_ts = datetime.utcnow()
        await db.collection("users").document(user_ctx.user_id).set(
            {"settings": {"contact_sync": {"last_sync_ts": now_ts}}}, merge=True
        )
    except Exception as e:
        # Non-fatal – log but continue
        print(f"Warning: unable to update last_sync_ts for user {user_ctx.user_id}: {e}")

    return IncrementalSyncResponse(server_changes=server_changes) 