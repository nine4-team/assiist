from abc import ABC, abstractmethod
from typing import List, Optional, Dict, Any
from assiist_back_end.models.reservation import Reservation

class ReservationRepository(ABC):
    @abstractmethod
    async def create(self, reservation: Reservation) -> Reservation:
        """Creates a new reservation."""
        pass

    @abstractmethod
    async def get_by_id(self, reservation_id: str) -> Optional[Reservation]:
        """Gets a specific reservation by ID."""
        pass

    @abstractmethod
    async def get_by_account(self, account_id: str, filters: Dict[str, Any] = None) -> List[Reservation]:
        """Gets reservations for an account with optional filters."""
        pass

    @abstractmethod
    async def update(self, reservation_id: str, update_data: Dict[str, Any]) -> Reservation:
        """Updates a reservation with the given data."""
        pass

    @abstractmethod
    async def delete(self, reservation_id: str) -> bool:
        """Deletes a reservation."""
        pass

    @abstractmethod
    async def exists(self, contact_id: str, account_id: str) -> bool:
        """Checks if a reservation already exists for the given contact and account."""
        pass 