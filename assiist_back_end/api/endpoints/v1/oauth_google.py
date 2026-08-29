import httpx
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from pydantic import BaseModel
from typing import Any, List
from datetime import datetime, timedelta, timezone
from dependency_injector.wiring import Provide, Provider
import logging

from google.cloud.firestore_v1.async_client import AsyncClient as FirestoreAsyncClient

from assiist_back_end.config import Settings
from assiist_back_end.api.endpoints.v1.dependencies import verify_firebase_token, UserContext, get_settings, get_firestore_async_client
from assiist_back_end.containers import Container
from assiist_back_end.api.endpoints.v1.calendar_connections import CalendarConnection
from assiist_back_end.services.google_calendar_service import (
    create_google_watch,
    perform_initial_sync
)
from assiist_back_end.db.repositories.interfaces.appointment_repository import AppointmentRepository
from assiist_back_end.db.repositories.interfaces.contact_repository import ContactRepository
from assiist_back_end.db.repositories.interfaces.pending_contact_repository import PendingContactRepository

google_oauth_router = APIRouter()
logger = logging.getLogger(__name__)

GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
GOOGLE_USERINFO_URL = "https://www.googleapis.com/oauth2/v2/userinfo"

class GoogleAuthCodeExchangeRequest(BaseModel):
    auth_code: str

@google_oauth_router.post("/oauth/google/exchange-code", status_code=201, response_model=CalendarConnection)
async def exchange_google_auth_code(
    request_data: GoogleAuthCodeExchangeRequest,
    background_tasks: BackgroundTasks,
    user_ctx: UserContext = Depends(verify_firebase_token),
    settings: Settings = Depends(get_settings),
    firestore_client: FirestoreAsyncClient = Depends(get_firestore_async_client),
    appointment_repo: AppointmentRepository = Depends(Provide[Container.appointment_repository]),
    contact_repo: ContactRepository = Depends(Provide[Container.contact_repository]),
    pending_contact_repo: PendingContactRepository = Depends(Provide[Container.pending_contact_repository]),
):
    logger.info(f"Attempting to exchange Google auth code for user_id: {user_ctx.user_id}, auth_code[:10]: {request_data.auth_code[:10]}...")

    try:
        if not settings.GOOGLE_CLIENT_ID or not settings.GOOGLE_CLIENT_SECRET:
            logger.error("Google OAuth client credentials not configured on server.")
            raise HTTPException(status_code=500, detail="Google OAuth client credentials not configured on server.")

        redirect_uri = f"{settings.API_URL}/oauth/google/callback"
        logger.info(f"OAUTH DEBUG: API_URL = {settings.API_URL}")
        logger.info(f"OAUTH DEBUG: Constructed redirect_uri = {redirect_uri}")
        logger.info(f"OAUTH DEBUG: Google Client ID = {settings.GOOGLE_CLIENT_ID}")

        token_payload = {
            "code": request_data.auth_code,
            "client_id": settings.GOOGLE_CLIENT_ID,
            "client_secret": settings.GOOGLE_CLIENT_SECRET.get_secret_value() if settings.GOOGLE_CLIENT_SECRET else None,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code",
        }
        logger.info(f"OAUTH DEBUG: Sending to Google - client_id: {settings.GOOGLE_CLIENT_ID}, redirect_uri: {redirect_uri}")

        async with httpx.AsyncClient() as client:
            try:
                logger.info("Step 1: Exchanging auth_code for tokens with Google...")
                token_response = await client.post(GOOGLE_TOKEN_URL, data=token_payload)
                logger.debug(f"Google token endpoint response status: {token_response.status_code}")
                token_response.raise_for_status()
                token_json = token_response.json()
                logger.info("Successfully exchanged auth_code for tokens.")

                access_token = token_json.get("access_token")
                refresh_token = token_json.get("refresh_token")
                expires_in = token_json.get("expires_in")
                scopes_from_token = token_json.get("scope", "").split()
                id_token_from_google = token_json.get("id_token")

                if not access_token:
                    logger.error("Failed to obtain access_token from Google response.")
                    raise HTTPException(status_code=500, detail="Failed to obtain access token from Google.")
                if not refresh_token:
                    logger.warning("Google did not return a refresh_token. Offline sync might not be possible.")
                
                logger.info("Step 2: Fetching user's email from Google...")
                userinfo_headers = {"Authorization": f"Bearer {access_token}"}
                userinfo_response = await client.get(GOOGLE_USERINFO_URL, headers=userinfo_headers)
                logger.debug(f"Google userinfo endpoint response status: {userinfo_response.status_code}")
                userinfo_response.raise_for_status()
                userinfo_json = userinfo_response.json()
                google_user_email = userinfo_json.get("email")
                logger.info(f"Successfully fetched Google user email: {google_user_email}")

                if not google_user_email:
                    logger.error("Failed to obtain user email from Google userinfo response.")
                    raise HTTPException(status_code=500, detail="Failed to obtain user email from Google.")

            except httpx.HTTPStatusError as e:
                error_detail = f"HTTPStatusError communicating with Google: Status {e.response.status_code}"
                error_request_url = e.request.url
                logger.error(f"Request URL: {error_request_url}")
                try:
                    error_body = e.response.json()
                    error_detail += f" - Body: {error_body}"
                    logger.error(f"Response Body: {error_body}")
                except Exception:
                    error_detail += f" - Text: {e.response.text}"
                    logger.error(f"Response Text: {e.response.text}")
                logger.error(f"Full HTTPStatusError during Google OAuth code exchange: {error_detail}", exc_info=True)
                raise HTTPException(status_code=500, detail=error_detail)
            except Exception as e:
                logger.error(f"Unexpected error during Google API interaction: {type(e).__name__} - {e}", exc_info=True)
                raise HTTPException(status_code=500, detail=f"An unexpected error occurred during Google API interaction: {str(e)}")

        token_expiry_dt = datetime.now(timezone.utc) + timedelta(seconds=expires_in) if expires_in else None
        logger.debug(f"Calculated token_expiry_dt: {token_expiry_dt}")

        calendar_connection_obj = CalendarConnection(
            provider="google",
            email=google_user_email,
            access_token=access_token,
            refresh_token=refresh_token,
            token_expiry=token_expiry_dt.isoformat() if token_expiry_dt else None,
            scopes=scopes_from_token,
            id_token=id_token_from_google,
            created_on=datetime.now(timezone.utc).isoformat()
        )
        logger.info(f"Prepared CalendarConnection object for Firestore for email: {google_user_email}")

        try:
            logger.info("Step 3: Saving CalendarConnection to Firestore...")
            doc_ref = firestore_client.collection("users").document(user_ctx.user_id).collection("connected_calendars").document(google_user_email)
            await doc_ref.set(calendar_connection_obj.model_dump(exclude_none=True))
            logger.info(f"Successfully stored Google Calendar connection for user {user_ctx.user_id} and email {google_user_email}")

            try:
                webhook_url = settings.GOOGLE_CALENDAR_WEBHOOK_URL
                logger.critical(f"DEBUG: GOOGLE_CALENDAR_WEBHOOK_URL value: '{webhook_url}'")
                if not webhook_url:
                    logger.error(f"GOOGLE_CALENDAR_WEBHOOK_URL not configured. Cannot register watch for {google_user_email}")
                else:
                    logger.critical(f"Step 4: Registering Google Calendar webhook for {google_user_email}...")
                    connection_data_dict = calendar_connection_obj.model_dump(exclude_none=True)
                    await create_google_watch(
                        user_id=user_ctx.user_id,
                        connection_data=connection_data_dict,
                        db_client=firestore_client,
                        settings=settings,
                        webhook_url=webhook_url
                    )

                logger.info(f"OAuth Step 5a: PRE-ENQUEUE - About to call background_tasks.add_task for perform_initial_sync for {google_user_email}.")
                background_tasks.add_task(
                    perform_initial_sync,
                    user_id=user_ctx.user_id,
                    connection_data=connection_data_dict,
                    db_client=firestore_client,
                    settings=settings
                )
                logger.info(f"OAuth Step 5b: POST-ENQUEUE - Call to background_tasks.add_task for perform_initial_sync for {google_user_email} has completed.")

            except Exception as e_watch_sync:
                logger.error(f"Error during post-save webhook registration or initial sync enqueue for {google_user_email}: {e_watch_sync}", exc_info=True)

        except Exception as e:
            logger.error(f"Firestore error while saving calendar connection for user {user_ctx.user_id}, email {google_user_email}: {type(e).__name__} - {e}", exc_info=True)
            raise HTTPException(status_code=500, detail="Failed to save calendar connection to database.")

        return calendar_connection_obj

    except HTTPException:
        raise
    except Exception as e:
        logger.critical(f"CRITICAL - Unhandled exception in exchange_google_auth_code for user {user_ctx.user_id}: {type(e).__name__} - {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"A critical server error occurred: {str(e)}")

# Note for frontend:
# 1. When initiating Google Sign-In (e.g., using `google_sign_in` package in Flutter):
#    - Ensure you request the `serverClientId`. This client ID should be the
#      "Web application" type OAuth 2.0 Client ID from your Google Cloud Console
#      (the one for which you have the client_secret in your backend .env).
#    - Request appropriate scopes, including \'email\', \'profile\',
#      \'https://www.googleapis.com/auth/calendar.readonly\'.
#    - The `google_sign_in` package, when configured with `serverClientId`, should
#      provide a `