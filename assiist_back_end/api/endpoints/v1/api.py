from fastapi import APIRouter

# Import endpoint routers
from . import (
    contacts,
    notes,
    appointments,
    users,  # UPDATED: Import consolidated users router
    tasks,
    debug,
    metrics,
    calendar_connections,
    oauth_google,
    genai,
    assistant,  # NEW: Import assistant router
    contact_sync,  # NEW: Contact sync incremental router
    google_webhook,
    accounts, # UPDATED: Import the consolidated accounts router
    reservations,
    notifications,  # NEW: Import notifications router
    revisions,  # NEW: Import revisions router
    feedback,  # NEW: Import feedback router
    transcription,
)

# Create the main v1 router
api_v1_router = APIRouter(prefix="/api/v1")

# Include endpoint routers
api_v1_router.include_router(contacts.router, prefix="/contacts")
api_v1_router.include_router(notes.router)
api_v1_router.include_router(notes.upload_router)  # Upload endpoints for file attachments
api_v1_router.include_router(appointments.router)
api_v1_router.include_router(appointments.contact_appointments_router)
api_v1_router.include_router(users.router, tags=["Users"])  # UPDATED: Use consolidated users router
api_v1_router.include_router(debug.debug_router)
api_v1_router.include_router(metrics.router)
api_v1_router.include_router(calendar_connections.router)
api_v1_router.include_router(oauth_google.google_oauth_router)
api_v1_router.include_router(genai.router)  # GenAI endpoints following implementation guide  
api_v1_router.include_router(tasks.tasks_router, tags=["Tasks"])
api_v1_router.include_router(tasks.contact_tasks_router)
api_v1_router.include_router(google_webhook.router, prefix="/webhooks/google", tags=["Google Webhooks"])
api_v1_router.include_router(accounts.router, tags=["Account"])  # UPDATED: Use consolidated accounts router - no prefix needed, already defined in router
api_v1_router.include_router(accounts.internal_router)  # Include internal accounts endpoints
api_v1_router.include_router(users.internal_router)  # Include internal users endpoints
api_v1_router.include_router(reservations.router, prefix="/reservations")
api_v1_router.include_router(notifications.router, prefix="/notifications", tags=["Notifications"])  # NEW: Include notifications router
api_v1_router.include_router(assistant.router)  # NEW: Include assistant router with both quick-actions and update-assistant endpoints
api_v1_router.include_router(revisions.revisions_router, tags=["Revisions"])  # NEW: Include revisions router
api_v1_router.include_router(feedback.router, tags=["Feedback"])  # NEW: Include feedback router
api_v1_router.include_router(transcription.router)
# NEW: Incremental contact sync router
api_v1_router.include_router(contact_sync.router)
# internal_genai functionality moved to genai.internal_router 