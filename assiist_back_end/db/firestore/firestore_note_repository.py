from typing import List, Optional, Dict, Any
import uuid

# Firestore Admin SDK
from firebase_admin import firestore
from google.cloud.firestore_v1 import AsyncClient, SERVER_TIMESTAMP

# Core components
from assiist_back_end.db.repositories.interfaces.note_repository import NoteRepository
from assiist_back_end.models.note import Note

# Assume mappers exist in the same directory
from .mappers import firestore_to_note, note_to_firestore

class FirestoreNoteRepository(NoteRepository):
    """Firestore implementation for note data operations."""

    def __init__(self, db: AsyncClient):
        self._db = db

    def _get_notes_coll(self, contact_id: str):
        """Helper to get the reference to a contact's notes subcollection under the top-level contacts collection."""
        return self._db.collection('contacts').document(contact_id).collection('notes')

    async def add(self, user_id: str, contact_id: str, note: Note) -> Note:
        """Adds a new note using its generated UUID as the document ID."""
        coll_ref = self._get_notes_coll(contact_id)
        doc_ref = coll_ref.document(str(note.id)) # Use model's UUID

        # Map domain model to Firestore dictionary
        firestore_data = note_to_firestore(note)
        firestore_data.pop('id', None)
        
        # Ensure parent IDs are set correctly if not handled by mapper
        firestore_data['user_id'] = user_id
        firestore_data['contact_id'] = contact_id
        
        # Ensure created_on is set (should be defaulted by model, but enforce server time)
        firestore_data['created_on'] = SERVER_TIMESTAMP
        # created_by should be set on the model before calling add

        await doc_ref.set(firestore_data)
        return note # Return original object

    async def get_by_id(self, user_id: str, contact_id: str, note_id: str) -> Optional[Note]:
        """Gets a specific note by its ID."""
        coll_ref = self._get_notes_coll(contact_id)
        doc_ref = coll_ref.document(note_id)
        snapshot = await doc_ref.get()

        if not snapshot.exists:
            return None

        firestore_data = snapshot.to_dict()
        if firestore_data is None:
             return None 

        firestore_data['id'] = snapshot.id
        return firestore_to_note(firestore_data)

    async def get_for_contact(self, user_id: str, contact_id: str) -> List[Note]:
        """Gets all notes for a specific contact, ordered by creation time."""
        coll_ref = self._get_notes_coll(contact_id)
        query = coll_ref.order_by("created_on", direction=firestore.Query.DESCENDING) # Newest first
        
        notes = []
        async for snapshot in query.stream():
            if snapshot.exists:
                firestore_data = snapshot.to_dict()
                if firestore_data:
                    firestore_data['id'] = snapshot.id
                    note = firestore_to_note(firestore_data)
                    if note:
                        notes.append(note)
        return notes

    async def update(self, user_id: str, contact_id: str, note_id: str, update_data: Dict[str, Any]) -> Optional[Note]:
        """Updates an existing note, raising specific errors."""
        coll_ref = self._get_notes_coll(contact_id)
        doc_ref = coll_ref.document(note_id)

        # Check existence first
        doc_snapshot = await doc_ref.get()
        if not doc_snapshot.exists:
            raise FileNotFoundError(f"Note {note_id} not found for contact {contact_id}")

        update_payload = update_data.copy()
        update_payload.pop('id', None) 
        update_payload.pop('created_on', None)
        update_payload.pop('created_by', None)
        update_payload.pop('user_id', None)
        update_payload.pop('contact_id', None)

        # Add updated_on/updated_by if tracking them
        update_payload['updated_on'] = SERVER_TIMESTAMP
        # update_payload['updated_by'] = updater_user_id # Need updater_user_id passed in

        try:
            # Perform update (no transaction currently)
            await doc_ref.update(update_payload)
            
            # Fetch and return the updated note
            updated_note = await self.get_by_id(user_id, contact_id, note_id)
            if not updated_note:
                 print(f"Warning: Could not fetch note {note_id} after update.")
                 raise Exception("Failed to fetch note after update")
            return updated_note
        except Exception as e:
            print(f"Error during note update commit for {note_id}: {e}")
            raise Exception(f"Database update failed for note {note_id}: {e}")

    async def delete(self, user_id: str, contact_id: str, note_id: str) -> bool:
        """Deletes a note (hard delete), raising specific errors."""
        coll_ref = self._get_notes_coll(contact_id)
        doc_ref = coll_ref.document(note_id)

        # Check existence before delete
        doc_snapshot = await doc_ref.get()
        if not doc_snapshot.exists:
            raise FileNotFoundError(f"Note {note_id} not found for contact {contact_id}")
            
        try:
            await doc_ref.delete()
            return True
        except Exception as e:
            print(f"Error deleting note {note_id} for contact {contact_id}: {e}")
            raise Exception(f"Database delete failed for note {note_id}: {e}") 