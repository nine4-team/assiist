from abc import ABC, abstractmethod
from typing import Dict, Optional

from assiist_back_end.models.user_metrics import UserMetrics

class UserMetricsRepository(ABC):
    """Abstract interface for user metrics data operations."""

    @abstractmethod
    async def get_metrics_for_contact(self, user_id: str, contact_id: str) -> Optional[UserMetrics]:
        """Gets metrics for a specific contact, creating initial metrics if they don't exist."""
        pass

    @abstractmethod
    async def increment_messages_sent(self, user_id: str, contact_id: str, idempotency_key: str) -> None:
        """Increments the messages sent counter for a contact, idempotently using the provided key."""
        pass

    @abstractmethod
    async def increment_notes_logged(self, user_id: str, contact_id: str) -> None:
        """Increments the notes logged counter for a contact. (Not idempotent, unlike messages_sent)"""
        pass

    @abstractmethod
    async def get_metrics_for_user(self, user_id: str) -> Dict[str, int]:
        """Gets total metrics across all contacts for a user."""
        pass 