import asyncio
import time
import logging
import uuid # Not strictly needed for this endpoint, but often useful in debug routers

from fastapi import APIRouter, Depends
from dependency_injector.wiring import inject, Provide
from google.cloud.firestore_v1.async_client import AsyncClient

from assiist_back_end.containers import Container
from assiist_back_end.api.endpoints.v1.dependencies import verify_firebase_token, UserContext
from assiist_back_end.services.assistant_service import AssistantService

# Get a logger instance
logger = logging.getLogger(__name__)
# If you have a central logging config, this might not be needed here.
# Basic config if no handlers are present for this logger, to ensure output.
if not logger.handlers:
    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    logger.setLevel(logging.INFO) 


debug_router = APIRouter(
    prefix="/debug",
    tags=["Debug"],
    dependencies=[Depends(verify_firebase_token)] # Secure this debug endpoint
)

@debug_router.get("/test-firestore-user-lookup", summary="Test Firestore user doc fetch performance repeatedly")
@inject
async def test_firestore_performance_endpoint(
    user_ctx: UserContext = Depends(verify_firebase_token), # Ensures user is authenticated for the test context
    db: AsyncClient = Depends(Provide[Container.firestore_async_client])
):
    results = []
    num_attempts = 7 # Let's do 7 attempts
    sleep_duration = 0.5 # seconds between attempts
    
    logger.info(f"[DEBUG ENDPOINT] Starting in-app Firestore performance test for user: {user_ctx.user_id}")

    for i in range(num_attempts):
        iteration_start_time = time.monotonic() # Time the whole iteration including sleep for context
        logger.info(f"[DEBUG ENDPOINT] Attempt {i + 1}/{num_attempts} starting...")
        
        doc_ref = db.collection("users").document(user_ctx.user_id)
        actual_fetch_start_time = time.monotonic()
        try:
            doc = await doc_ref.get()
            actual_fetch_end_time = time.monotonic()
            duration = actual_fetch_end_time - actual_fetch_start_time
            if doc.exists:
                msg = f"Attempt {i+1}: Fetched user doc successfully in {duration:.4f} seconds."
                results.append({"status": "success", "duration": duration, "message": msg})
                logger.info(f"[DEBUG ENDPOINT] {msg}")
            else:
                # This case should ideally not happen if user_ctx was successfully created by verify_firebase_token
                msg = f"Attempt {i+1}: User doc NOT FOUND (UID: {user_ctx.user_id}). Lookup took {duration:.4f} seconds."
                results.append({"status": "not_found", "duration": duration, "message": msg})
                logger.warning(f"[DEBUG ENDPOINT] {msg}")
        except Exception as e:
            actual_fetch_end_time = time.monotonic()
            duration = actual_fetch_end_time - actual_fetch_start_time
            msg = f"Attempt {i+1}: Error after {duration:.4f} seconds: {str(e)}"
            results.append({"status": "error", "duration": duration, "message": msg})
            logger.error(f"[DEBUG ENDPOINT] {msg}", exc_info=True)
        
        iteration_end_time = time.monotonic()
        logger.info(f"[DEBUG ENDPOINT] Attempt {i + 1}/{num_attempts} finished. Iteration time (incl. sleep if any): {iteration_end_time - iteration_start_time:.4f}s")

        if i < num_attempts - 1:
            await asyncio.sleep(sleep_duration)
            
    total_successful_duration = sum(r['duration'] for r in results if r['status'] == 'success')
    num_successful = len([r for r in results if r['status'] == 'success'])
    average_duration = total_successful_duration / num_successful if num_successful > 0 else 0
    
    summary = f"In-app test complete for UID {user_ctx.user_id}. Average for {num_successful} successful fetches: {average_duration:.4f}s"
    logger.info(f"[DEBUG ENDPOINT] {summary}")
    return {"test_summary": summary, "user_id_tested": user_ctx.user_id, "attempts": results} 