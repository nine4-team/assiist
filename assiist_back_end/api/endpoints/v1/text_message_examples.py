import uuid
from typing import List
from fastapi import APIRouter, Depends, HTTPException, status, Path
from dependency_injector.wiring import inject, Provide

from assiist_back_end.containers import Container
from assiist_back_end.api.schemas.text_message_example import (
    TextMessageExampleCreateSchema,
    TextMessageExampleUpdateSchema,
    TextMessageExampleResponseSchema
)
from assiist_back_end.models.text_message_example import TextMessageExample
from assiist_back_end.db.repositories.interfaces.text_message_example_repository import TextMessageExampleRepository
from assiist_back_end.api.endpoints.v1.dependencies import verify_firebase_token, UserContext

router = APIRouter(
    prefix="/text-message-examples",
    tags=["TextMessageExamples"]
)

print('DEBUG: text_message_examples.py loaded', flush=True)

@router.get(
    "",
    response_model=List[TextMessageExampleResponseSchema],
    summary="List all text message examples for the user"
)
@inject
async def list_examples(
    user_ctx: UserContext = Depends(verify_firebase_token),
    repo: TextMessageExampleRepository = Depends(Provide[Container.text_message_example_repository])
):
    print('DEBUG: list_examples endpoint called', flush=True)
    print(f"DEBUG: user_id from token: '{user_ctx.user_id}'", flush=True)
    return await repo.get_for_user(user_id=user_ctx.user_id)

@router.post(
    "",
    response_model=TextMessageExampleResponseSchema,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new text message example"
)
@inject
async def create_example(
    example_in: TextMessageExampleCreateSchema,
    user_ctx: UserContext = Depends(verify_firebase_token),
    repo: TextMessageExampleRepository = Depends(Provide[Container.text_message_example_repository])
):
    example = TextMessageExample(user_id=user_ctx.user_id, example_text=example_in.example_text)
    return await repo.add(user_id=user_ctx.user_id, example=example)

@router.patch(
    "/{example_id}",
    response_model=TextMessageExampleResponseSchema,
    summary="Update a text message example"
)
@inject
async def update_example(
    example_id: uuid.UUID,
    update_in: TextMessageExampleUpdateSchema,
    user_ctx: UserContext = Depends(verify_firebase_token),
    repo: TextMessageExampleRepository = Depends(Provide[Container.text_message_example_repository])
):
    update_data = update_in.dict(exclude_unset=True)
    updated = await repo.update(user_id=user_ctx.user_id, example_id=str(example_id), update_data=update_data)
    if not updated:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Example not found or update failed")
    return updated

@router.delete(
    "/{example_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a text message example"
)
@inject
async def delete_example(
    example_id: uuid.UUID,
    user_ctx: UserContext = Depends(verify_firebase_token),
    repo: TextMessageExampleRepository = Depends(Provide[Container.text_message_example_repository])
):
    deleted = await repo.delete(user_id=user_ctx.user_id, example_id=str(example_id))
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Example not found")
    return 