from datetime import datetime
from typing import Dict, Any, Optional, List
import uuid
import logging

from google.cloud.firestore_v1 import AsyncClient, ArrayUnion, SERVER_TIMESTAMP
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import ValidationError

from assiist_back_end.models.revision import RevisionHistory, RevisionEntry
from assiist_back_end.db.repositories.interfaces.revision_repository import RevisionHistoryRepository

logger = logging.getLogger(__name__)

class FirestoreRevisionHistoryRepository(RevisionHistoryRepository):
    def __init__(self, db: AsyncClient):
        self._db = db
        
    def _get_revision_histories_coll(self):
        """Helper to get the reference to the revision_histories collection."""
        return self._db.collection('revision_histories')
        
    async def add(self, revision_history: RevisionHistory) -> RevisionHistory:
        """Add a new revision history document."""
        try:
            # Convert to dict for Firestore
            history_dict = revision_history.dict()
            
            # Convert UUID to string for Firestore
            history_dict['id'] = str(history_dict['id'])
            history_dict['task_id'] = str(history_dict['task_id'])
            
            # Add to Firestore
            doc_ref = self._get_revision_histories_coll().document(history_dict['id'])
            await doc_ref.set(history_dict)
            
            return revision_history
        except Exception as e:
            logger.error(f"Error adding revision history: {e}")
            raise
        
    async def get_by_id(self, revision_history_id: str) -> Optional[RevisionHistory]:
        """Get a revision history by ID."""
        try:
            doc_ref = self._get_revision_histories_coll().document(revision_history_id)
            doc = await doc_ref.get()
            
            if not doc.exists:
                return None
                
            data = doc.to_dict()
            # Convert string IDs back to UUID
            data['id'] = uuid.UUID(data['id'])
            data['task_id'] = uuid.UUID(data['task_id'])
            
            return RevisionHistory(**data)
        except (ValidationError, KeyError, ValueError) as e:
            logger.error(f"Error retrieving revision history by ID: {e}")
            return None
            
    async def get_for_task(self, task_id: str) -> Optional[RevisionHistory]:
        """Get the revision history for a specific task."""
        try:
            query = self._get_revision_histories_coll().where(filter=FieldFilter('task_id', '==', task_id))
            results = await query.get()
            
            if not results:
                return None
                
            # Should only be one match
            doc = results[0]
            
            data = doc.to_dict()
            # Convert string IDs back to UUID
            data['id'] = uuid.UUID(data['id'])
            data['task_id'] = uuid.UUID(data['task_id'])
            
            return RevisionHistory(**data)
        except (ValidationError, KeyError, ValueError) as e:
            logger.error(f"Error retrieving revision history for task: {e}")
            return None
            
    async def update(self, revision_history_id: str, update_data: Dict[str, Any]) -> Optional[RevisionHistory]:
        """Update a revision history document."""
        try:
            doc_ref = self._get_revision_histories_coll().document(revision_history_id)
            await doc_ref.update(update_data)
            
            # Get the updated document
            return await self.get_by_id(revision_history_id)
        except Exception as e:
            logger.error(f"Error updating revision history: {e}")
            return None
            
    async def append_revision(self, revision_history_id: str, revision_entry: RevisionEntry) -> Optional[RevisionHistory]:
        """Append a new revision to the history."""
        try:
            # Get the current history to check if it's finalized
            history = await self.get_by_id(revision_history_id)
            if not history:
                logger.error(f"Revision history not found: {revision_history_id}")
                return None
                
            if history.is_finalized:
                logger.error(f"Cannot append to finalized revision history: {revision_history_id}")
                return None
                
            # Convert the revision entry to dict
            entry_dict = revision_entry.dict()
            
            # Update the document with the new revision
            doc_ref = self._get_revision_histories_coll().document(revision_history_id)
            await doc_ref.update({
                'revisions': ArrayUnion([entry_dict])
            })
            
            # Get the updated history
            return await self.get_by_id(revision_history_id)
        except Exception as e:
            logger.error(f"Error appending revision: {e}")
            return None
            
    async def finalize_revision_history(self, revision_history_id: str) -> Optional[RevisionHistory]:
        """Mark a revision history as finalized."""
        try:
            update_data = {
                'is_finalized': True,
                'finalized_on': SERVER_TIMESTAMP
            }
            
            return await self.update(revision_history_id, update_data)
        except Exception as e:
            logger.error(f"Error finalizing revision history: {e}")
            return None 