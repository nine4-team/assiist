from abc import ABC, abstractmethod
from typing import List, Optional
import uuid

from assiist_back_end.models.note import Note

class NoteRepository(ABC):
    """Interface for data operations related to Notes."""

    @abstractmethod
    async def add(self, user_id: str, contact_id: str, note: Note) -> Note:
        """Adds a new note to a contact's subcollection."""
        pass

    @abstractmethod
    async def get_by_id(self, user_id: str, contact_id: str, note_id: str) -> Optional[Note]:
        """Gets a specific note by its ID."""
        pass

    @abstractmethod
    async def get_for_contact(self, user_id: str, contact_id: str) -> List[Note]:
        """Gets all notes for a specific contact."""
        pass

    @abstractmethod
    async def update(self, user_id: str, contact_id: str, note_id: str, update_data: dict) -> Optional[Note]:
        """Updates an existing note."""
        pass

    @abstractmethod
    async def delete(self, user_id: str, contact_id: str, note_id: str) -> bool:
        """Deletes a note."""
        pass 