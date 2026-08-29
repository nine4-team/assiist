from fastapi import APIRouter, Depends, HTTPException
from typing import List
from google.cloud.firestore_v1.async_client import AsyncClient
from assiist_back_end.api.endpoints.v1.dependencies import verify_firebase_token, UserContext
from assiist_back_end.models.calendar_connection import CalendarConnection
from datetime import datetime, timezone

router = APIRouter(prefix="/calendars")

@router.post("", status_code=201)
async def add_calendar(
    calendar: CalendarConnection,
    user_ctx: UserContext = Depends(verify_firebase_token)
):
    db = AsyncClient(database="assiist-app") # Consider using DI for db client from container
    # TODO: When creating/updating a CalendarConnection, ensure all relevant fields 
    # (access_token, refresh_token, token_expiry, scopes, id_token if applicable) 
    # from the OAuth provider are correctly mapped and stored.
    # The `calendar.dict()` will now include these new fields if provided in the request.
    
    # Set created_on if not provided
    calendar_dict = calendar.dict(exclude_none=True)
    if 'created_on' not in calendar_dict:
        calendar_dict['created_on'] = datetime.now(timezone.utc).isoformat()
    
    doc_ref = db.collection("users").document(user_ctx.user_id).collection("connected_calendars").document(calendar.email)
    await doc_ref.set(calendar_dict) # exclude_none=True is good practice
    return {"status": "success"}

@router.get("", response_model=List[CalendarConnection])
async def list_calendars(
    user_ctx: UserContext = Depends(verify_firebase_token)
):
    db = AsyncClient(database="assiist-app") # Consider using DI for db client
    col_ref = db.collection("users").document(user_ctx.user_id).collection("connected_calendars")
    docs = [doc async for doc in col_ref.stream()]
    # The CalendarConnection model will now correctly parse the new fields if they exist in Firestore.
    return [CalendarConnection(**doc.to_dict()) for doc in docs]

@router.delete("/{email}")
async def remove_calendar(
    email: str,
    user_ctx: UserContext = Depends(verify_firebase_token)
):
    db = AsyncClient(database="assiist-app") # Consider using DI for db client
    doc_ref = db.collection("users").document(user_ctx.user_id).collection("connected_calendars").document(email)
    await doc_ref.delete()
    return {"status": "deleted"} 