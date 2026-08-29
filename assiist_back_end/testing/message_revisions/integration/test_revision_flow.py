import pytest
from datetime import datetime
import uuid
from unittest.mock import AsyncMock, patch, MagicMock

from models.task import Task
from models.revision import RevisionHistory, RevisionEntry
from db.firestore.firestore_task_repository import FirestoreTaskRepository
from db.firestore.firestore_revision_repository import FirestoreRevisionHistoryRepository
# Note: This test file may need to be updated to use proper dependency injection
# from services.repositories import get_task_repository, get_revision_history_repository  # REMOVED: File no longer exists

@pytest.fixture
def mock_firestore_client():
    client = AsyncMock()
    return client

@pytest.fixture
def task_repo(mock_firestore_client):
    return FirestoreTaskRepository(mock_firestore_client)

@pytest.fixture
def revision_repo(mock_firestore_client):
    return FirestoreRevisionHistoryRepository(mock_firestore_client)

@pytest.mark.asyncio
async def test_create_task_with_revision_history(task_repo, revision_repo, mock_firestore_client):
    """Test creating a task with an associated revision history."""
    # Setup
    task = Task(
        id=uuid.uuid4(),
        user_id="test_user",
        contact_id=uuid.uuid4(),
        title="Test Task",
        body="Hello, this is a test message.",
        type="message"
    )
    
    # Configure mock for task creation
    task_ref = AsyncMock()
    collection_mock = AsyncMock()
    doc_mock = AsyncMock()
    task_collection_mock = AsyncMock()
    
    # Setup the chain of mocks
    mock_firestore_client.collection.return_value = collection_mock
    collection_mock.document.return_value = doc_mock
    doc_mock.collection.return_value = task_collection_mock
    task_collection_mock.document.return_value = task_ref
    
    # Task get after creation
    task_snapshot = AsyncMock()
    task_snapshot.exists = True
    task_snapshot.to_dict.return_value = task.dict()
    task_snapshot.id = str(task.id)
    task_ref.get.return_value = task_snapshot
    
    # Configure mock for revision history creation
    history_ref = AsyncMock()
    mock_firestore_client.collection.return_value.document.return_value = history_ref
    
    # Execute
    created_task, history = await task_repo.add_with_revision_history(
        task=task,
        original_message=task.body,
        context={"original_instructions": "Create a greeting message"},
        revision_repo=revision_repo
    )
    
    # Assert
    assert created_task is not None
    assert history is not None
    assert history.task_id == task.id
    assert history.original_message == task.body
    assert "original_instructions" in history.context

@pytest.mark.asyncio
async def test_revise_message_flow(task_repo, revision_repo, mock_firestore_client):
    """Test the complete flow of revising a message."""
    # Setup task
    task_id = uuid.uuid4()
    contact_id = uuid.uuid4()
    user_id = "test_user"
    
    # Setup revision history
    history_id = uuid.uuid4()
    history = RevisionHistory(
        id=history_id,
        task_id=task_id,
        original_message="Hello, this is a test.",
        context={"original_instructions": "Create a greeting message"}
    )
    
    # Configure mocks for task retrieval
    task_collection_mock = AsyncMock()
    task_document_mock = AsyncMock()
    contact_collection_mock = AsyncMock()
    contact_document_mock = AsyncMock()
    
    mock_firestore_client.collection.return_value = contact_collection_mock
    contact_collection_mock.document.return_value = contact_document_mock
    contact_document_mock.collection.return_value = task_collection_mock
    task_collection_mock.document.return_value = task_document_mock
    
    task_snapshot = AsyncMock()
    task_snapshot.exists = True
    task_snapshot.to_dict.return_value = {
        "id": str(task_id),
        "body": "Hello, this is a test.",
        "user_id": user_id,
        "revision_history_id": str(history_id)
    }
    task_document_mock.get.return_value = task_snapshot
    
    # Configure mocks for history retrieval
    history_collection_mock = AsyncMock()
    history_document_mock = AsyncMock()
    query_mock = AsyncMock()
    
    # For direct history document access
    mock_firestore_client.collection.side_effect = [contact_collection_mock, history_collection_mock]
    history_collection_mock.document.return_value = history_document_mock
    
    history_snapshot = AsyncMock()
    history_snapshot.exists = True
    history_snapshot.to_dict.return_value = {
        "id": str(history_id),
        "task_id": str(task_id),
        "original_message": "Hello, this is a test.",
        "revisions": [],
        "context": {"original_instructions": "Create a greeting message"},
        "is_finalized": False,
        "created_on": datetime.utcnow()
    }
    history_document_mock.get.return_value = history_snapshot
    
    # For task query by ID
    mock_firestore_client.collection.return_value.where.return_value = query_mock
    query_results = [history_snapshot]
    query_mock.get.return_value = query_results
    
    # Execute
    # 1. Get task
    task = await task_repo.get_by_id(user_id=user_id, contact_id=str(contact_id), task_id=str(task_id))
    
    # Reconfigure collection side effect for get_for_task
    mock_firestore_client.collection.side_effect = [history_collection_mock]
    mock_firestore_client.collection.return_value.where.return_value = query_mock
    
    # 2. Get revision history
    revision_history = await revision_repo.get_for_task(str(task_id))
    
    # 3. Create new revision
    new_revision = RevisionEntry(
        revision_instructions="Make it more formal",
        revised_message="Hello, I would like to inquire about your services."
    )
    
    # 4. Append revision to history
    mock_firestore_client.collection.return_value.document.return_value.update.return_value = None
    updated_history = await revision_repo.append_revision(
        revision_history_id=str(history_id),
        revision_entry=new_revision
    )
    
    # 5. Update task with new message
    update_data = {
        'body': new_revision.revised_message,
        'updated_by': user_id
    }
    
    # Reset collection side effect for task update
    mock_firestore_client.collection.side_effect = [contact_collection_mock]
    
    await task_repo.update(
        user_id=user_id,
        contact_id=str(contact_id),
        task_id=str(task_id),
        update_data=update_data
    )
    
    # Assert firestore operations were called
    # For revision append
    history_collection_mock.document.assert_called()
    # For task update
    task_collection_mock.document.assert_called_with(str(task_id))
    task_document_mock.update.assert_called()

@pytest.mark.asyncio
async def test_finalize_revision_history(revision_repo, mock_firestore_client):
    """Test finalizing a revision history."""
    # Setup
    history_id = uuid.uuid4()
    
    # Configure mocks
    history_collection_mock = AsyncMock()
    history_document_mock = AsyncMock()
    
    mock_firestore_client.collection.return_value = history_collection_mock
    history_collection_mock.document.return_value = history_document_mock
    
    history_snapshot = AsyncMock()
    history_snapshot.exists = True
    history_snapshot.to_dict.return_value = {
        "id": str(history_id),
        "task_id": str(uuid.uuid4()),
        "original_message": "Hello, this is a test.",
        "revisions": [],
        "context": {"original_instructions": "Create a greeting message"},
        "is_finalized": False,
        "created_on": datetime.utcnow()
    }
    history_document_mock.get.return_value = history_snapshot
    
    # Execute
    await revision_repo.finalize_revision_history(str(history_id))
    
    # Assert
    history_document_mock.update.assert_called_once()
    # Check that the update data contains is_finalized=True
    call_args = history_document_mock.update.call_args[0][0]
    assert call_args["is_finalized"] is True
    assert "finalized_on" in call_args 