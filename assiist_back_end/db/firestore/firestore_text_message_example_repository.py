from typing import List, Optional, Dict, Any
import uuid
from firebase_admin import firestore
from google.cloud.firestore_v1 import AsyncClient, SERVER_TIMESTAMP
from assiist_back_end.db.repositories.interfaces.text_message_example_repository import TextMessageExampleRepository
from assiist_back_end.models.text_message_example import TextMessageExample
# Assume mappers exist or use direct dict conversion

class FirestoreTextMessageExampleRepository(TextMessageExampleRepository):
    """Firestore implementation for text message example data operations."""

    def __init__(self, db: AsyncClient):
        self._db = db

    def _get_examples_coll(self, user_id: str):
        return self._db.collection('users').document(user_id).collection('text_message_examples')

    async def add(self, user_id: str, example: TextMessageExample) -> TextMessageExample:
        coll_ref = self._get_examples_coll(user_id)
        doc_ref = coll_ref.document(str(example.id))
        firestore_data = example.dict(exclude={'id'})
        firestore_data['created_on'] = SERVER_TIMESTAMP
        await doc_ref.set(firestore_data)
        return example

    async def get_for_user(self, user_id: str) -> List[TextMessageExample]:
        coll_ref = self._get_examples_coll(user_id)
        query = coll_ref.order_by("created_on", direction=firestore.Query.DESCENDING)
        examples = []
        async for snapshot in query.stream():
            if snapshot.exists:
                data = snapshot.to_dict()
                if data:
                    data['id'] = snapshot.id
                    examples.append(TextMessageExample(**data))
        return examples

    async def get_by_id(self, user_id: str, example_id: str) -> Optional[TextMessageExample]:
        coll_ref = self._get_examples_coll(user_id)
        doc_ref = coll_ref.document(example_id)
        snapshot = await doc_ref.get()
        if not snapshot.exists:
            return None
        data = snapshot.to_dict()
        if data is None:
            return None
        data['id'] = snapshot.id
        return TextMessageExample(**data)

    async def update(self, user_id: str, example_id: str, update_data: Dict[str, Any]) -> Optional[TextMessageExample]:
        coll_ref = self._get_examples_coll(user_id)
        doc_ref = coll_ref.document(example_id)
        doc_snapshot = await doc_ref.get()
        if not doc_snapshot.exists:
            return None
        update_payload = update_data.copy()
        update_payload.pop('id', None)
        update_payload.pop('user_id', None)
        update_payload.pop('created_on', None)
        update_payload['updated_on'] = SERVER_TIMESTAMP
        try:
            await doc_ref.update(update_payload)
            updated = await self.get_by_id(user_id, example_id)
            return updated
        except Exception as e:
            print(f"Error updating text message example {example_id}: {e}")
            return None

    async def delete(self, user_id: str, example_id: str) -> bool:
        coll_ref = self._get_examples_coll(user_id)
        doc_ref = coll_ref.document(example_id)
        doc_snapshot = await doc_ref.get()
        if not doc_snapshot.exists:
            return False
        try:
            await doc_ref.delete()
            return True
        except Exception as e:
            print(f"Error deleting text message example {example_id}: {e}")
            return False 