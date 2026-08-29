import uuid
from typing import List, Optional, Any
import logging

from fastapi import APIRouter, Depends, HTTPException, status, Path, Query, Body, Response
from dependency_injector.wiring import inject, Provide

# Container
from assiist_back_end.containers import Container

# Schemas
from assiist_back_end.api.schemas.task import (
    TaskCreateSchema,
    TaskResponseSchema,
    TaskUpdateSchema
)
from assiist_back_end.api.schemas.revision import RevisionHistoryResponse, SuccessResponse  # Added import for revision schemas

# Domain Models
from assiist_back_end.models.task import Task, TaskStatus, TaskType
from assiist_back_end.models.contact import Contact

# Repositories Interfaces
from assiist_back_end.db.repositories.interfaces.task_repository import TaskRepository
from assiist_back_end.db.repositories.interfaces.revision_repository import RevisionHistoryRepository  # Added import for revision repository

# Mappers
from assiist_back_end.api.endpoints.v1.mappers import (
    map_task_create_schema_to_domain,
    map_task_domain_to_response_schema,
    map_task_update_schema_to_dict
)

# Dependency injection
from dependency_injector.wiring import inject, Provide
from assiist_back_end.containers import Container

# Dependencies
# Import the moved helper and UserContext
from assiist_back_end.api.endpoints.v1.dependencies import (
    verify_firebase_token, 
    verify_contact_ownership, 
    UserContext
)
# Repository interfaces import (using standard dependency injection)
from assiist_back_end.db.repositories.interfaces.revision_repository import RevisionHistoryRepository

import google.api_core.exceptions # Added import for google exceptions

# Router for contact-specific tasks
contact_tasks_router = APIRouter(
    prefix="/contacts/{contact_id}/tasks",
    tags=["Tasks"], # CHANGED Tag to just "Tasks"
    dependencies=[Depends(verify_firebase_token), Depends(verify_contact_ownership)]
)

# Router for general tasks
tasks_router = APIRouter(
    prefix="/tasks",
    tags=["Tasks"], # CHANGED Tag to just "Tasks"
    dependencies=[Depends(verify_firebase_token)]
)

logger = logging.getLogger(__name__)

# --- User Level Endpoint ---
@tasks_router.get(
    "",
    response_model=List[TaskResponseSchema],
    summary="List all tasks for the authenticated user"
)
@inject
async def list_all_user_tasks(
    user_ctx: UserContext = Depends(verify_firebase_token),
    repo: TaskRepository = Depends(Provide[Container.task_repository])
):
    """Retrieves all tasks associated with the authenticated user across all contacts."""
    try:
        tasks = await repo.get_all_for_user(user_id=user_ctx.user_id)
        # TODO: Decide if contact info needs to be populated here for the dashboard
        # This would require fetching each contact based on task.contact_id (potentially slow)
        return [map_task_domain_to_response_schema(task) for task in tasks]
    except google.api_core.exceptions.FailedPrecondition as e:
        # Catch missing index error specifically
        print(f"Firestore index missing for get_all_for_user: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Backend configuration error: Firestore index required. Please check server logs for creation link. Error: {e}"
        )
    except Exception as e:
        print(f"Error listing all user tasks: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Error retrieving user tasks")

# --- Contact Specific Endpoints (Use the other router) ---

@contact_tasks_router.post(
    "",
    response_model=TaskResponseSchema,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new task for a contact"
)
@inject
async def create_task(
    task_in: TaskCreateSchema,
    user_ctx: UserContext = Depends(verify_firebase_token),
    verified_contact: Contact = Depends(verify_contact_ownership),
    repo: TaskRepository = Depends(Provide[Container.task_repository]),
    revision_repo: RevisionHistoryRepository = Depends(Provide[Container.revision_history_repository])
):
    """Creates a new task associated with a specific contact."""
    task_domain = map_task_create_schema_to_domain(
        task_in,
        authenticated_user_id=user_ctx.user_id
    )
    task_domain.contact_id = verified_contact.id # Ensure contact_id from path is used

    # Check if this is a message task with revision context
    if task_domain.type == "message" and task_in.revision_context:
        logger.info(f"Creating message task with revision history: {task_domain.title}")
        
        # Create task with revision history
        created_task, revision_history = await repo.add_with_revision_history(
            task=task_domain,
            original_message=task_domain.body or "",
            context=task_in.revision_context,
            revision_repo=revision_repo
        )
        
        logger.info(f"✅ Created task with revision history {revision_history.id} for task {created_task.id}")
        return map_task_domain_to_response_schema(created_task)
    else:
        # Create regular task without revision history
        created_task = await repo.add(user_ctx.user_id, str(verified_contact.id), task_domain)
        return map_task_domain_to_response_schema(created_task)

@contact_tasks_router.get(
    "",
    response_model=List[TaskResponseSchema],
    summary="List tasks for a specific contact"
)
@inject
async def list_tasks(
    user_ctx: UserContext = Depends(verify_firebase_token),
    verified_contact: Contact = Depends(verify_contact_ownership),
    repo: TaskRepository = Depends(Provide[Container.task_repository])
):
    """Retrieves all tasks associated with a specific contact."""
    tasks = await repo.get_for_contact(
        user_id=user_ctx.user_id, 
        contact_id=str(verified_contact.id)
    )
    return [map_task_domain_to_response_schema(task) for task in tasks]

@contact_tasks_router.get(
    "/{task_id}",
    response_model=TaskResponseSchema,
    summary="Get a specific task by ID"
)
@inject
async def get_task(
    task_id: uuid.UUID = Path(..., description="The ID of the task to retrieve"),
    user_ctx: UserContext = Depends(verify_firebase_token),
    verified_contact: Contact = Depends(verify_contact_ownership),
    repo: TaskRepository = Depends(Provide[Container.task_repository])
):
    """Retrieves details of a specific task for a contact."""
    # Contact ownership is verified by the dependency
    task = await repo.get_by_id(
        user_id=user_ctx.user_id,
        contact_id=str(verified_contact.id),
        task_id=str(task_id)
    )
    if not task:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    return map_task_domain_to_response_schema(task)

@contact_tasks_router.patch(
    "/{task_id}",
    response_model=TaskResponseSchema,
    summary="Update a task"
)
@inject
async def update_task(
    task_in: TaskUpdateSchema,
    task_id: uuid.UUID = Path(..., description="The ID of the task to update"),
    user_ctx: UserContext = Depends(verify_firebase_token),
    verified_contact: Contact = Depends(verify_contact_ownership),
    repo: TaskRepository = Depends(Provide[Container.task_repository])
):
    """Updates specific fields of a task."""
    update_dict = map_task_update_schema_to_dict(task_in)
    if not update_dict:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No update fields provided")

    # Add updated_by from the authenticated user context
    update_dict['updated_by'] = user_ctx.user_id
    # updated_on should be handled by the model validator or repository

    try:
        # The repo.update method will need user_id for permission checks, 
        # contact_id for scoping, task_id, and the update_data.
        updated_task = await repo.update(
            user_id=user_ctx.user_id, # For permission/scoping in repo
            contact_id=str(verified_contact.id),
            task_id=str(task_id),
            update_data=update_dict
        )
        if not updated_task:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found or update failed")
        return map_task_domain_to_response_schema(updated_task)
    except FileNotFoundError as e:
         raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except PermissionError as e:
         raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(e))
    except Exception as e:
        print(f"Error during task update endpoint: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Error updating task")

@contact_tasks_router.delete(
    "/{task_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a task"
)
@inject
async def delete_task(
    task_id: uuid.UUID = Path(..., description="The ID of the task to delete"),
    user_ctx: UserContext = Depends(verify_firebase_token),
    verified_contact: Contact = Depends(verify_contact_ownership),
    repo: TaskRepository = Depends(Provide[Container.task_repository])
):
    """Deletes a specific task for a contact."""
    # Contact ownership is verified by the dependency
    try:
        deleted = await repo.delete(
            user_id=user_ctx.user_id,
            contact_id=str(verified_contact.id),
            task_id=str(task_id)
        )
        if not deleted:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
        return # Return None for 204
    except FileNotFoundError as e:
         raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
    except PermissionError as e:
         raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(e))
    except Exception as e:
        print(f"Error during task delete endpoint: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Error deleting task")