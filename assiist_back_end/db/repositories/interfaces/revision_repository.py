from abc import ABC, abstractmethod
from typing import Dict, Any, Optional

from assiist_back_end.models.revision import RevisionHistory, RevisionEntry

class RevisionHistoryRepository(ABC):
    @abstractmethod
    async def add(self, revision_history: RevisionHistory) -> RevisionHistory:
        """Add a new revision history document."""
        pass
        
    @abstractmethod
    async def get_by_id(self, revision_history_id: str) -> Optional[RevisionHistory]:
        """Get a revision history by ID."""
        pass
        
    @abstractmethod
    async def get_for_task(self, task_id: str) -> Optional[RevisionHistory]:
        """Get the revision history for a specific task."""
        pass
        
    @abstractmethod
    async def update(self, revision_history_id: str, update_data: Dict[str, Any]) -> Optional[RevisionHistory]:
        """Update a revision history document."""
        pass
        
    @abstractmethod
    async def append_revision(self, revision_history_id: str, revision_entry: RevisionEntry) -> Optional[RevisionHistory]:
        """Append a new revision to the history."""
        pass
        
    @abstractmethod
    async def finalize_revision_history(self, revision_history_id: str) -> Optional[RevisionHistory]:
        """Mark a revision history as finalized."""
        pass 