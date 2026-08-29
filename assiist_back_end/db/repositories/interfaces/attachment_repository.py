from abc import ABC, abstractmethod
from typing import List, Optional
from assiist_back_end.models.attachment import Attachment


class AttachmentRepository(ABC):
    """Repository interface for attachment operations"""

    @abstractmethod
    async def create(self, attachment: Attachment) -> Attachment:
        """Create a new attachment record"""
        pass

    @abstractmethod
    async def get_by_id(self, user_id: str, attachment_id: str) -> Optional[Attachment]:
        """Get attachment by ID for a specific user"""
        pass

    @abstractmethod
    async def get_by_short_id(self, short_id: str) -> Optional[Attachment]:
        """Get attachment by short ID (public access)"""
        pass

    @abstractmethod
    async def get_by_user(self, user_id: str, limit: int = 100) -> List[Attachment]:
        """Get all attachments for a user"""
        pass

    @abstractmethod
    async def delete(self, user_id: str, attachment_id: str) -> bool:
        """Soft delete an attachment"""
        pass

    @abstractmethod
    async def update(self, user_id: str, attachment_id: str, update_data: dict) -> Optional[Attachment]:
        """Update attachment metadata"""
        pass 