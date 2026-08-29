from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional, Dict, Any
from datetime import datetime

class AudioTranscriptionRepository(ABC):
    """Interface for CRUD operations on audio transcriptions."""

    @abstractmethod
    async def add(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Create a new transcription document and return stored data."""
        raise NotImplementedError

    @abstractmethod
    async def get_by_attachment_id(self, attachment_id: str) -> Optional[Dict[str, Any]]:
        """Retrieve transcription doc by attachment id."""
        raise NotImplementedError

    @abstractmethod
    async def update_status(self, id: str, status: str, update_fields: Dict[str, Any]) -> bool:
        """Update status and fields of a transcription document."""
        raise NotImplementedError 