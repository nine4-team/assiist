from abc import ABC, abstractmethod
from typing import List, Optional

from assiist_back_end.models.pending_contact import PendingContact

class PendingContactRepository(ABC):
    """Interface for accessing pending contact data."""

    @abstractmethod
    async def add(self, pending_contact: PendingContact) -> PendingContact:
        """Creates a new pending contact record.
           Assumes user_id is set on the input pending_contact object.
        """
        pass

    @abstractmethod
    async def get_by_email(self, user_id: str, email: str) -> Optional[PendingContact]:
        """Fetches a pending contact by email for a specific user."""
        pass

    @abstractmethod
    async def get_pending_contacts(
        self, user_id: str, status: Optional[str] = None
    ) -> List[PendingContact]:
        """Fetches pending contacts for a user, optionally filtered by status."""
        pass

    @abstractmethod
    async def update_status(self, user_id: str, pending_contact_id: str, status: str) -> Optional[PendingContact]:
        """Updates the status of a specific pending contact record for a user. 
           Returns the updated PendingContact on success, None otherwise.
        """
        pass

    @abstractmethod
    async def get_by_id(self, user_id: str, pending_contact_id: str) -> Optional[PendingContact]:
        """Fetches a pending contact by its ID for a specific user."""
        pass

    # Optional: Add other methods if needed, e.g., get_by_id 