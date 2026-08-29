from typing import List, Optional, Dict, Any, Tuple
import uuid
from datetime import datetime # Ensure datetime is imported directly for utcnow if needed elsewhere

# Firestore Admin SDK
from firebase_admin import firestore
from google.cloud.firestore_v1 import AsyncClient, SERVER_TIMESTAMP, DocumentSnapshot
from google.cloud.firestore_v1.base_query import FieldFilter # Added import

# Core components
from assiist_back_end.db.repositories.interfaces.task_repository import TaskRepository # ADJUSTED PATH
from assiist_back_end.db.repositories.interfaces.revision_repository import RevisionHistoryRepository # Added import for repository interface
from assiist_back_end.models.task import Task, TaskStatus # Task model now has user_id, created_by, updated_by - ADJUSTED PATH
from assiist_back_end.models.revision import RevisionHistory # Fixed import path for RevisionHistory

# Assume mappers exist in the same directory
from .mappers import firestore_to_task, task_to_firestore # task_to_firestore needs to handle the new model structure

class FirestoreTaskRepository(TaskRepository):
    """Firestore implementation for task data operations."""

    def __init__(self, db: AsyncClient):
        self._db = db

    def _get_tasks_coll(self, contact_id: str):
        """Helper to get the reference to a contact's tasks subcollection under the top-level contacts collection."""
        # Ensure contact_id is a string for document path
        return self._db.collection('contacts').document(str(contact_id)).collection('tasks')

    def _get_user_tasks_coll_group(self):
        """Helper to get the reference to the 'tasks' collection group for user-wide queries."""
        return self._db.collection_group('tasks')

    async def add(self, user_id: str, contact_id: str, task: Task) -> Task:
        """Adds a new task using its generated UUID as the document ID.
           The incoming task object is assumed to have user_id, created_by, updated_by already set.
           user_id and contact_id parameters are used for authorization and validation.
        """
        if task.contact_id is None:
            raise ValueError("Task must have a contact_id to be added.")
        
        # Validate that the task's contact_id matches the provided contact_id
        if str(task.contact_id) != str(contact_id):
            raise ValueError(f"Task contact_id {task.contact_id} does not match provided contact_id {contact_id}")
        
        # Validate that the task's user_id matches the provided user_id
        if task.user_id != user_id:
            raise ValueError(f"Task user_id {task.user_id} does not match provided user_id {user_id}")
        
        coll_ref = self._get_tasks_coll(str(contact_id))
        doc_ref = coll_ref.document(str(task.id))

        firestore_data = task_to_firestore(task) # This should dump all fields from Task model
        firestore_data.pop('id', None) # ID is used as doc_ref.id
        
        # Denormalize contact_display_name (existing logic)
        task.contact_display_name = None 
        contact_doc_ref = self._db.collection('contacts').document(str(task.contact_id))
        contact_snapshot: DocumentSnapshot = await contact_doc_ref.get()
        if contact_snapshot.exists:
            contact_data_dict = contact_snapshot.to_dict() or {}
            first_name = contact_data_dict.get('first_name', '')
            last_name = contact_data_dict.get('last_name', '')
            business_name = contact_data_dict.get('business_name', '')
            display_name_parts = []
            if first_name: display_name_parts.append(first_name)
            if last_name: display_name_parts.append(last_name)
            calculated_display_name = " ".join(display_name_parts).strip()
            if not calculated_display_name and business_name: 
                calculated_display_name = business_name
            if calculated_display_name:
                firestore_data['contact_display_name'] = calculated_display_name
                task.contact_display_name = calculated_display_name 
            else:
                firestore_data['contact_display_name'] = None
        else:
            firestore_data['contact_display_name'] = None

        # Ensure timestamps are server timestamps for consistency
        firestore_data['created_on'] = SERVER_TIMESTAMP
        firestore_data['updated_on'] = SERVER_TIMESTAMP # Also set updated_on for new tasks
        # user_id, created_by, updated_by are already in firestore_data via task_to_firestore(task)

        await doc_ref.set(firestore_data)
        # Fetch the document to get server-generated timestamps and confirm write
        # However, returning the input `task` (now with contact_display_name) is usually sufficient for CQRS
        # and matches previous behavior. If server timestamps are critical for immediate response, a get() is needed.
        return task 

    async def get_by_id(self, user_id: str, contact_id: str, task_id: str) -> Optional[Task]:
        """Gets a specific task by its ID."""
        coll_ref = self._get_tasks_coll(contact_id)
        doc_ref = coll_ref.document(task_id)
        snapshot = await doc_ref.get()

        if not snapshot.exists or snapshot.to_dict().get('user_id') != user_id:
            return None

        firestore_data = snapshot.to_dict()
        if firestore_data is None:
             return None 

        firestore_data['id'] = snapshot.id
        return firestore_to_task(firestore_data)

    async def get_for_contact(self, user_id: str, contact_id: str) -> List[Task]:
        """Gets all tasks for a specific contact, filtered by user_id and ordered by due date then creation."""
        coll_ref = self._get_tasks_coll(contact_id)
        # MODIFIED query to filter by user_id at Firestore level using FieldFilter
        query = coll_ref.where(filter=FieldFilter("user_id", "==", user_id))\
                        .order_by("due_date", direction=firestore.Query.ASCENDING)\
                        .order_by("created_on", direction=firestore.Query.DESCENDING)
        
        tasks_result = []
        async for snapshot in query.stream():
            if snapshot.exists:
                firestore_data = snapshot.to_dict()
                if firestore_data: # snapshot.exists should mean firestore_data is not None
                    firestore_data['id'] = snapshot.id
                    task = firestore_to_task(firestore_data)
                    # user_id is already guaranteed by the Firestore query's where clause.
                    if task:
                        tasks_result.append(task)
        return tasks_result

    async def get_all_for_user(self, user_id: str) -> List[Task]:
        """Gets all tasks for a user across all contacts using a collection group query.

        This implementation now filters out any task whose **parent contact** either
        does not exist (hard-deleted) **or** is marked with `is_deleted = True` (soft-deleted).
        A small in-memory cache is used so each distinct contact_id is read from
        Firestore at most once per request.
        """
        tasks_group_ref = self._get_user_tasks_coll_group()
        # Query for tasks belonging to the user, order by due date then creation
        query = (
            tasks_group_ref
            .where(filter=FieldFilter("user_id", "==", user_id))
            .order_by("due_date", direction=firestore.Query.ASCENDING)
            .order_by("created_on", direction=firestore.Query.DESCENDING)
        )

        tasks: List[Task] = []
        contact_cache: Dict[str, bool] = {}  # contact_id -> contact_is_active

        try:
            async for snapshot in query.stream():
                if not snapshot.exists:
                    continue  # Defensive – shouldn't happen

                data = snapshot.to_dict()
                if not data:
                    continue

                contact_id_value = data.get("contact_id")
                if not contact_id_value:
                    # Task without a parent contact id is considered orphaned → skip
                    continue

                contact_id = str(contact_id_value)

                # Check cache or load contact doc once per unique id
                if contact_id not in contact_cache:
                    contact_doc_ref = self._db.collection("contacts").document(contact_id)
                    contact_snapshot = await contact_doc_ref.get()
                    contact_dict = contact_snapshot.to_dict() if contact_snapshot.exists else None
                    contact_is_active = (
                        contact_snapshot.exists and contact_dict is not None and not contact_dict.get("is_deleted", False)
                    )
                    contact_cache[contact_id] = contact_is_active

                if not contact_cache[contact_id]:
                    # Parent contact is deleted or missing → skip task
                    continue

                # Parent contact is active – include this task
                data["id"] = snapshot.id
                try:
                    task = firestore_to_task(data)
                    if task:
                        tasks.append(task)
                except Exception as e:
                    # Log and skip malformed tasks rather than failing whole request
                    print(f"Error converting task {snapshot.id} to domain model: {e}")
                    continue
        except Exception as e:
            print(f"Error executing get_all_for_user query for user {user_id}: {e}")
            raise e

        return tasks

    async def update(self, user_id: str, contact_id: str, task_id: str, update_data: Dict[str, Any]) -> Optional[Task]:
        """Updates an existing task, raising specific errors."""
        coll_ref = self._get_tasks_coll(contact_id)
        doc_ref = coll_ref.document(task_id)

        doc_snapshot = await doc_ref.get()
        if not doc_snapshot.exists or doc_snapshot.to_dict().get('user_id') != user_id:
            raise FileNotFoundError(f"Task {task_id} not found for contact {contact_id} or permission denied")

        current_task_data = doc_snapshot.to_dict() or {}
        
        update_payload = update_data.copy()
        # Fields that should not be updatable or are handled differently
        update_payload.pop('id', None) 
        update_payload.pop('created_on', None)
        update_payload.pop('created_by', None) # creator should not change
        update_payload.pop('user_id', None) # owner should not change
        update_payload.pop('contact_id', None) # contact association should not change this way
        update_payload.pop('contact_display_name', None) 

        # Remove any revision-related fields that might be passed in
        update_payload.pop('revision_instructions', None)
        update_payload.pop('revision_llm_provider', None)
        update_payload.pop('revision_context', None)
        
        # Ensure updated_on is set to server timestamp. updated_by is already in update_data from endpoint.
        update_payload['updated_on'] = SERVER_TIMESTAMP
        
        try:
            # Update the task document
            await doc_ref.update(update_payload)
            updated_task_snapshot = await doc_ref.get() # Fetch after update to get server timestamps
            if not updated_task_snapshot.exists:
                 print(f"Warning: Could not fetch task {task_id} after update.")
                 # This case should ideally not happen if update didn't error and doc existed.
                 return None 
            
            firestore_doc_data = updated_task_snapshot.to_dict()
            if firestore_doc_data is None:
                return None
            firestore_doc_data['id'] = updated_task_snapshot.id
            return firestore_to_task(firestore_doc_data)
        except Exception as e:
            print(f"Error during task update commit for {task_id}: {e}")
            raise Exception(f"Database update failed for task {task_id}: {e}")

    async def delete(self, user_id: str, contact_id: str, task_id: str) -> bool:
        """Deletes a task (hard delete), raising specific errors."""
        coll_ref = self._get_tasks_coll(contact_id)
        doc_ref = coll_ref.document(task_id)

        # Check existence before delete
        doc_snapshot = await doc_ref.get()
        if not doc_snapshot.exists or doc_snapshot.to_dict().get('user_id') != user_id:
            raise FileNotFoundError(f"Task {task_id} not found for contact {contact_id} or permission denied")
            
        try:
            await doc_ref.delete()
            return True
        except Exception as e:
            print(f"Error deleting task {task_id} for contact {contact_id}: {e}")
            raise Exception(f"Database delete failed for task {task_id}: {e}") 

    async def add_with_revision_history(
        self, 
        task: Task, 
        original_message: str,
        context: Dict[str, Any],
        revision_repo: RevisionHistoryRepository
    ) -> Tuple[Task, RevisionHistory]:
        """Creates a task along with its revision history atomically."""
        # Create the task first
        created_task = await self.add(task.user_id, str(task.contact_id), task)
        
        # Create the revision history
        revision_history = RevisionHistory(
            task_id=created_task.id,
            user_id=task.user_id,  # Include user_id for security rules
            original_message=original_message,
            context=context
        )
        
        # Save the revision history
        saved_history = await revision_repo.add(revision_history)
        
        # Update the task with the revision history ID
        update_data = {
            'revision_history_id': str(saved_history.id),
            'updated_by': task.user_id,
            'updated_on': SERVER_TIMESTAMP
        }
        
        updated_task = await self.update(
            user_id=task.user_id,
            contact_id=str(task.contact_id),
            task_id=str(task.id),
            update_data=update_data
        )
        
        return (updated_task, saved_history) 