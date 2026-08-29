from fastapi import APIRouter, Request, Header, HTTPException, Depends, BackgroundTasks
from typing import Annotated
import logging

from dependency_injector.wiring import inject, Provide
from google.cloud.firestore_v1.async_client import AsyncClient

from assiist_back_end.services.google_calendar_service import handle_webhook_notification
from assiist_back_end.config import Settings
from assiist_back_end.containers import Container

logger = logging.getLogger(__name__)

router = APIRouter()

@router.post("/notifications", tags=["Google Calendar Webhook"])
@inject
async def google_calendar_webhook(
    request: Request,
    background_tasks: BackgroundTasks,
    x_goog_channel_id: Annotated[str | None, Header()] = None,
    x_goog_resource_id: Annotated[str | None, Header()] = None,
    x_goog_resource_state: Annotated[str | None, Header()] = None,
    x_goog_message_number: Annotated[str | None, Header()] = None,
    x_goog_resource_uri: Annotated[str | None, Header()] = None,
    x_goog_channel_expiration: Annotated[str | None, Header()] = None,
    x_goog_channel_token: Annotated[str | None, Header()] = None,
    db_client: AsyncClient = Depends(Provide[Container.firestore_async_client]),
    app_settings: Settings = Depends(Provide[Container.config])
):
    """
    Receives push notifications from Google Calendar API.
    Validates the notification and enqueues a background task for processing.
    """
    logger.info(f"Received Google Calendar webhook notification. State: {x_goog_resource_state}")
    logger.debug(f"Headers: channel_id={x_goog_channel_id}, resource_id={x_goog_resource_id}, message_number={x_goog_message_number}, resource_uri={x_goog_resource_uri}, expiration={x_goog_channel_expiration}, token={x_goog_channel_token}")

    if not all([x_goog_channel_id, x_goog_resource_id, x_goog_resource_state]):
        logger.warning("Missing required Google Calendar webhook headers.")
        raise HTTPException(status_code=400, detail="Missing required Google Calendar webhook headers")

    logger.info(f"Adding handle_webhook_notification to background tasks for channel_id: {x_goog_channel_id}")
    background_tasks.add_task(
        handle_webhook_notification,
        db_client=db_client,
        settings=app_settings,
        channel_id_from_header=x_goog_channel_id,
        resource_id_from_header=x_goog_resource_id,
        resource_state_from_header=x_goog_resource_state,
    )
    logger.info(f"Successfully added handle_webhook_notification to background tasks")

    return {"message": "Notification received"}

@router.post("/verify-domain", include_in_schema=False)
async def verify_google_domain(request: Request):
    logger.info("Domain verification endpoint hit.")
    return {"message": "Domain verification endpoint placeholder"} 