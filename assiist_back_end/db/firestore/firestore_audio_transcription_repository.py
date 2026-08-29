from __future__ import annotations

import logging
from typing import Optional, Dict, Any
from datetime import datetime

from google.cloud.firestore_v1 import AsyncClient
from firebase_admin import firestore

from assiist_back_end.db.repositories.interfaces.audio_transcription_repository import AudioTranscriptionRepository

logger = logging.getLogger(__name__)

COLLECTION_NAME = "audio_transcriptions"

class FirestoreAudioTranscriptionRepository(AudioTranscriptionRepository):
    """Firestore implementation storing full transcript & metadata."""

    def __init__(self, db: AsyncClient):
        self._db = db

    async def add(self, data: Dict[str, Any]) -> Dict[str, Any]:
        doc_id = data.get("id")
        if not doc_id:
            raise ValueError("'id' field required in transcription data")

        data.setdefault("created_on", firestore.SERVER_TIMESTAMP)
        doc_ref = self._db.collection(COLLECTION_NAME).document(doc_id)
        await doc_ref.set(data)
        logger.info("Created audio transcription %s", doc_id)
        return data

    async def get_by_attachment_id(self, attachment_id: str) -> Optional[Dict[str, Any]]:
        query = (
            self._db.collection(COLLECTION_NAME)
            .where(filter=firestore.FieldFilter("attachment_id", "==", attachment_id))
            .limit(1)
        )
        docs = await query.get()
        if not docs:
            return None
        doc = docs[0]
        data = doc.to_dict()
        data["id"] = doc.id
        return data

    async def update_status(self, id: str, status: str, update_fields: Dict[str, Any]) -> bool:
        doc_ref = self._db.collection(COLLECTION_NAME).document(id)
        update_data = {
            "status": status,
            "updated_on": firestore.SERVER_TIMESTAMP,
            **update_fields,
        }
        await doc_ref.update(update_data)
        return True 