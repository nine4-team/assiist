from abc import ABC, abstractmethod
from typing import List, Optional
from datetime import datetime
from google.cloud.firestore_v1.async_client import AsyncClient

from assiist_back_end.models.appointment import Appointment

class AppointmentRepository(ABC):
    """Interface for data operations related to user Appointments/Calendar Events."""

    @abstractmethod
    async def add(self, user_id: str, appointment: Appointment) -> Appointment:
        """Adds a new appointment to the user's collection."""
        pass

    @abstractmethod
    async def get_by_id(self, user_id: str, appointment_id: str) -> Optional[Appointment]:
        """Gets a specific appointment by its ID for a user."""
        pass

    @abstractmethod
    async def get_by_external_id(self, user_id: str, external_event_id: str) -> Optional[Appointment]:
        """Gets a specific appointment by its external provider ID (e.g., Google event ID) for a user."""
        pass

    @abstractmethod
    async def get_for_user(self, user_id: str, start_date: Optional[datetime] = None, end_date: Optional[datetime] = None) -> List[Appointment]:
        """Gets all appointments for a specific user, optionally filtered by date range."""
        pass

    @abstractmethod
    async def get_pending_contact_creation(self, user_id: str) -> List[Appointment]:
        """Gets appointments flagged as needing contact creation prompts for the user."""
        pass

    @abstractmethod
    async def update(self, user_id: str, appointment_id: str, update_data: dict) -> Optional[Appointment]:
        """Updates an existing appointment for a user."""
        pass

    @abstractmethod
    async def delete(self, user_id: str, appointment_id: str) -> bool:
        """Deletes an appointment for a user."""
        pass

    @abstractmethod
    async def get_for_contact(self, user_id: str, contact_id: str) -> List[Appointment]:
        """Gets all appointments associated with a specific contact ID."""
        pass

    # Consider adding batch methods for sync operations
    # @abstractmethod
    # async def add_batch(self, user_id: str, appointments: List[Appointment]) -> bool:
    #     pass
    # @abstractmethod
    # async def upsert_batch(self, user_id: str, appointments: List[Appointment]) -> bool:
    #     pass