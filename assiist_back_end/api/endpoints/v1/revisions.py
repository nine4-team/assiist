import uuid
from typing import List, Optional
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status, Path
from dependency_injector.wiring import inject, Provide

# Container
from assiist_back_end.containers import Container

# Schemas
from assiist_back_end.api.schemas.revision import (
    RevisionHistoryResponse,
    RevisionEntryResponse,
    SuccessResponse
)

# Domain Models
from assiist_back_end.models.revision import RevisionEntry

# Repositories Interfaces
from assiist_back_end.db.repositories.interfaces.revision_repository import RevisionHistoryRepository
from assiist_back_end.db.repositories.interfaces.task_repository import TaskRepository

# Dependencies
from assiist_back_end.api.endpoints.v1.dependencies import verify_firebase_token, UserContext

# Router for revision-specific endpoints
revisions_router = APIRouter(
    prefix="/revisions",
    tags=["Revisions"],
    dependencies=[Depends(verify_firebase_token)]
)

@revisions_router.get("/task/{task_id}", response_model=RevisionHistoryResponse)
@inject
async def get_task_revision_history(
    task_id: str,
    user_ctx: UserContext = Depends(verify_firebase_token),
    revision_repo: RevisionHistoryRepository = Depends(Provide[Container.revision_history_repository]),
    task_repo: TaskRepository = Depends(Provide[Container.task_repository])
):
    """Get the revision history for a task.
    
    Args:
        task_id: The ID of the task
        user_ctx: The user context from the auth token
        revision_repo: The revision history repository (injected)
        task_repo: The task repository (injected)
        
    Returns:
        The revision history for the task
        
    Raises:
        HTTPException: If the task doesn't exist or the user doesn't have access
    """
    # First verify the user has access to the task
    # We need to find the task across all contacts since we only have task_id
    # Use get_all_for_user and filter by task_id
    all_tasks = await task_repo.get_all_for_user(user_id=user_ctx.user_id)
    task = next((t for t in all_tasks if t.id == task_id), None)
    
    if not task:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Task {task_id} not found or you don't have access to it"
        )
        
    # Get the revision history
    revision_history = await revision_repo.get_for_task(task_id)
    
    if not revision_history:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No revision history found for task {task_id}"
        )
        
    return RevisionHistoryResponse(
        task_id=task_id,
        revision_count=len(revision_history.revisions),
        revisions=[
            RevisionEntryResponse(
                revision_number=entry.revision_number,
                message_content=entry.message_content,
                revision_instructions=entry.revision_instructions,
                created_on=entry.created_on
            ) for entry in revision_history.revisions
        ],
        is_finalized=revision_history.is_finalized,
        created_on=revision_history.created_on,
        updated_on=revision_history.updated_on
    )

@revisions_router.post("/task/{task_id}/finalize", response_model=SuccessResponse)
@inject
async def finalize_task_revision(
    task_id: str,
    user_ctx: UserContext = Depends(verify_firebase_token),
    revision_repo: RevisionHistoryRepository = Depends(Provide[Container.revision_history_repository]),
    task_repo: TaskRepository = Depends(Provide[Container.task_repository])
):
    """Mark a task's revision history as finalized.
    
    Args:
        task_id: The ID of the task
        user_ctx: The user context from the auth token
        revision_repo: The revision history repository (injected)
        task_repo: The task repository (injected)
        
    Returns:
        Success response
        
    Raises:
        HTTPException: If the task doesn't exist or the user doesn't have access
    """
    # First verify the user has access to the task
    # We need to find the task across all contacts since we only have task_id
    # Use get_all_for_user and filter by task_id
    all_tasks = await task_repo.get_all_for_user(user_id=user_ctx.user_id)
    task = next((t for t in all_tasks if t.id == task_id), None)
    
    if not task:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Task {task_id} not found or you don't have access to it"
        )
        
    # Get the revision history
    revision_history = await revision_repo.get_for_task(task_id)
    
    if not revision_history:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No revision history found for task {task_id}"
        )
        
    # Finalize the revision history
    await revision_repo.finalize(task_id)
    
    return SuccessResponse(message="Revision history finalized successfully")

@revisions_router.post("/task/{task_id}/add", response_model=RevisionHistoryResponse)
@inject
async def add_task_revision(
    task_id: str,
    revision: RevisionEntry,
    user_ctx: UserContext = Depends(verify_firebase_token),
    revision_repo: RevisionHistoryRepository = Depends(Provide[Container.revision_history_repository]),
    task_repo: TaskRepository = Depends(Provide[Container.task_repository])
):
    """Add a new revision to a task's revision history.
    
    Args:
        task_id: The ID of the task
        revision: The new revision entry to add
        user_ctx: The user context from the auth token
        revision_repo: The revision history repository (injected)
        task_repo: The task repository (injected)
        
    Returns:
        The updated revision history
        
    Raises:
        HTTPException: If the task doesn't exist, the user doesn't have access,
                      or the revision history is already finalized
    """
    # First verify the user has access to the task
    # We need to find the task across all contacts since we only have task_id
    # Use get_all_for_user and filter by task_id
    all_tasks = await task_repo.get_all_for_user(user_id=user_ctx.user_id)
    task = next((t for t in all_tasks if t.id == task_id), None)
    
    if not task:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Task {task_id} not found or you don't have access to it"
        )
        
    # Get the revision history
    revision_history = await revision_repo.get_for_task(task_id)
    
    if not revision_history:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No revision history found for task {task_id}"
        )
        
    # Check if already finalized
    if revision_history.is_finalized:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot add revision to finalized revision history"
        )
        
    # Add the new revision
    updated_history = await revision_repo.add_revision(task_id, revision)
    
    return RevisionHistoryResponse(
        task_id=task_id,
        revision_count=len(updated_history.revisions),
        revisions=[
            RevisionEntryResponse(
                revision_number=entry.revision_number,
                message_content=entry.message_content,
                revision_instructions=entry.revision_instructions,
                created_on=entry.created_on
            ) for entry in updated_history.revisions
        ],
        is_finalized=updated_history.is_finalized,
        created_on=updated_history.created_on,
        updated_on=updated_history.updated_on
    ) 