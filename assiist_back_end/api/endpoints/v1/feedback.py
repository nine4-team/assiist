from fastapi import APIRouter, Depends, HTTPException, status
from dependency_injector.wiring import inject, Provide
from google.cloud.firestore_v1.async_client import AsyncClient
import logging

from ...schemas.feedback import FeedbackCreateRequest, FeedbackResponse, FeedbackListResponse
from .dependencies import verify_firebase_token, UserContext
from ....models.feedback import Feedback
from ....db.repositories.interfaces.feedback_repository import FeedbackRepository
from ....containers import Container

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/feedback",
    tags=["feedback"],
    dependencies=[Depends(verify_firebase_token)]
)

@router.post("/", response_model=FeedbackResponse, status_code=status.HTTP_201_CREATED)
@inject
async def submit_feedback(
    request: FeedbackCreateRequest,
    user_context: UserContext = Depends(verify_firebase_token),
    feedback_repo: FeedbackRepository = Depends(Provide[Container.feedback_repository]),
    db: AsyncClient = Depends(Provide[Container.firestore_async_client])
):
    """Submit new feedback."""
    try:
        logger.info(f"User {user_context.user_id} submitting feedback for account {user_context.account_id}")
        
        # Fetch user profile data for email and display name
        user_email = "unknown@example.com"
        user_name = "Unknown User"
        
        try:
            user_ref = db.collection("users").document(user_context.user_id)
            user_doc = await user_ref.get()
            
            if user_doc.exists:
                user_data = user_doc.to_dict()
                user_email = user_data.get("email") or "unknown@example.com"
                
                # Calculate display name from first_name and last_name
                first_name = user_data.get("first_name", "").strip()
                last_name = user_data.get("last_name", "").strip()
                if first_name and last_name:
                    user_name = f"{first_name} {last_name}"
                elif first_name:
                    user_name = first_name
                elif last_name:
                    user_name = last_name
                elif user_email and user_email != "unknown@example.com":
                    user_name = user_email
                
        except Exception as user_fetch_error:
            logger.warning(f"Failed to fetch user profile for feedback submission: {user_fetch_error}")
            # Continue with defaults if user fetch fails
        
        # Create feedback model
        feedback = Feedback(
            account_id=user_context.account_id,
            user_id=user_context.user_id,
            feedback_text=request.feedback_text,
            feedback_type=request.feedback_type,
            user_email=user_email,
            user_name=user_name,
            app_version=request.app_version,
            platform=request.platform,
            screen_context=request.screen_context,
            created_by=user_context.user_id,
            updated_by=user_context.user_id
        )
        
        # Save to database
        created_feedback = await feedback_repo.create(feedback)
        
        logger.info(f"Successfully created feedback {created_feedback.id}")
        
        return FeedbackResponse(
            id=created_feedback.id,
            account_id=created_feedback.account_id,
            user_id=created_feedback.user_id,
            feedback_text=created_feedback.feedback_text,
            feedback_type=created_feedback.feedback_type,
            user_email=created_feedback.user_email,
            user_name=created_feedback.user_name,
            app_version=created_feedback.app_version,
            platform=created_feedback.platform,
            screen_context=created_feedback.screen_context,
            status=created_feedback.status,
            created_on=created_feedback.created_on
        )
        
    except Exception as e:
        logger.error(f"Failed to submit feedback: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to submit feedback: {str(e)}"
        )

@router.get("/", response_model=FeedbackListResponse)
@inject
async def list_feedback(
    user_context: UserContext = Depends(verify_firebase_token),
    feedback_repo: FeedbackRepository = Depends(Provide[Container.feedback_repository])
):
    """List feedback for current account (admin use)."""
    try:
        logger.info(f"Listing feedback for account {user_context.account_id}")
        
        feedback_list = await feedback_repo.list_by_account(user_context.account_id)
        
        return FeedbackListResponse(
            feedback=[
                FeedbackResponse(
                    id=f.id,
                    account_id=f.account_id,
                    user_id=f.user_id,
                    feedback_text=f.feedback_text,
                    feedback_type=f.feedback_type,
                    user_email=f.user_email,
                    user_name=f.user_name,
                    app_version=f.app_version,
                    platform=f.platform,
                    screen_context=f.screen_context,
                    status=f.status,
                    created_on=f.created_on
                ) for f in feedback_list
            ],
            total_count=len(feedback_list)
        )
        
    except Exception as e:
        logger.error(f"Failed to list feedback: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to list feedback: {str(e)}"
        ) 