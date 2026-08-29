from abc import ABC, abstractmethod
from typing import List, Optional, Dict, Any, Tuple
import uuid

from assiist_back_end.models.task import Task
from assiist_back_end.models.revision import RevisionHistory
from assiist_back_end.db.repositories.interfaces.revision_repository import RevisionHistoryRepository

class TaskRepository(ABC):
    """Interface for data operations related to Tasks."""

    @abstractmethod
    async def add(self, user_id: str, contact_id: str, task: Task) -> Task:
        """Adds a new task to a contact's subcollection."""
        pass

    @abstractmethod
    async def get_by_id(self, user_id: str, contact_id: str, task_id: str) -> Optional[Task]:
        """Gets a specific task by its ID."""
        pass

    @abstractmethod
    async def get_for_contact(self, user_id: str, contact_id: str) -> List[Task]:
        """Gets all tasks for a specific contact."""
        pass

    @abstractmethod
    async def update(self, user_id: str, contact_id: str, task_id: str, update_data: Dict[str, Any]) -> Optional[Task]:
        """Updates an existing task."""
        pass

    @abstractmethod
    async def delete(self, user_id: str, contact_id: str, task_id: str) -> bool:
        """Deletes a specific task, ensuring it belongs to the contact/user."""
        pass

    @abstractmethod
    async def get_all_for_user(self, user_id: str) -> List[Task]:
        """Retrieves all tasks associated with a specific user across all contacts."""
        pass

    @abstractmethod
    async def add_with_revision_history(
        self, 
        task: Task, 
        original_message: str,
        context: Dict[str, Any],
        revision_repo: RevisionHistoryRepository
    ) -> Tuple[Task, RevisionHistory]:
        """Creates a task along with its revision history atomically."""
        pass

    # Potentially add methods for querying tasks by status, assignee, etc. 