import uuid
from datetime import datetime
from typing import List, Optional

from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from assiist_back_end.db.repositories.interfaces.attachment_repository import AttachmentRepository
from assiist_back_end.models.attachment import Attachment
from assiist_back_end.utils.time import utc_now


class FirestoreAttachmentRepository(AttachmentRepository):
    """Firestore implementation of attachment repository"""

    def __init__(self, db: firestore.Client):
        self.db = db
        self.collection_name = "attachments"

    def _to_domain(self, doc_data: dict) -> Attachment:
        """Convert Firestore document to domain model"""
        return Attachment(
            id=doc_data.get("id"),
            account_id=doc_data.get("account_id"),
            user_id=doc_data.get("user_id"),
            filename=doc_data.get("filename"),
            original_filename=doc_data.get("original_filename"),
            file_type=doc_data.get("file_type"),
            file_size=doc_data.get("file_size"),
            public_url=doc_data.get("public_url"),
            gcs_url=doc_data.get("gcs_url"),
            storage_path=doc_data.get("storage_path"),
            short_id=doc_data.get("short_id"),
            created_on=doc_data.get("created_on"),
            updated_on=doc_data.get("updated_on"),
            created_by=doc_data.get("created_by"),
            updated_by=doc_data.get("updated_by"),
            is_deleted=doc_data.get("is_deleted", False)
        )

    def _to_dict(self, attachment: Attachment) -> dict:
        """Convert domain model to Firestore document"""
        return {
            "id": attachment.id,
            "account_id": attachment.account_id,
            "user_id": attachment.user_id,
            "filename": attachment.filename,
            "original_filename": attachment.original_filename,
            "file_type": attachment.file_type,
            "file_size": attachment.file_size,
            "public_url": attachment.public_url,
            "gcs_url": attachment.gcs_url,
            "storage_path": attachment.storage_path,
            "short_id": attachment.short_id,
            "created_on": attachment.created_on,
            "updated_on": attachment.updated_on,
            "created_by": attachment.created_by,
            "updated_by": attachment.updated_by,
            "is_deleted": attachment.is_deleted
        }

    async def create(self, attachment: Attachment) -> Attachment:
        """Create a new attachment record"""
        if not attachment.id:
            attachment.id = str(uuid.uuid4())
        
        now = utc_now()
        attachment.created_on = now
        attachment.updated_on = now
        
        doc_ref = self.db.collection(self.collection_name).document(attachment.id)
        await doc_ref.set(self._to_dict(attachment))
        
        return attachment

    async def get_by_id(self, user_id: str, attachment_id: str) -> Optional[Attachment]:
        """Get attachment by ID for a specific user"""
        doc_ref = self.db.collection(self.collection_name).document(attachment_id)
        doc = await doc_ref.get()
        
        if not doc.exists:
            return None
            
        doc_data = doc.to_dict()
        if doc_data.get("user_id") != user_id or doc_data.get("is_deleted", False):
            return None
            
        return self._to_domain(doc_data)

    async def get_by_short_id(self, short_id: str) -> Optional[Attachment]:
        """Get attachment by short ID (public access)"""
        query = (
            self.db.collection(self.collection_name)
            .where(filter=FieldFilter("short_id", "==", short_id))
            .where(filter=FieldFilter("is_deleted", "==", False))
            .limit(1)
        )
        
        docs = await query.get()
        if not docs:
            return None
            
        return self._to_domain(docs[0].to_dict())

    async def get_by_user(self, user_id: str, limit: int = 100) -> List[Attachment]:
        """Get all attachments for a user"""
        query = (
            self.db.collection(self.collection_name)
            .where(filter=FieldFilter("user_id", "==", user_id))
            .where(filter=FieldFilter("is_deleted", "==", False))
            .order_by("created_on", direction=firestore.Query.DESCENDING)
            .limit(limit)
        )
        
        docs = await query.get()
        return [self._to_domain(doc.to_dict()) for doc in docs]

    async def delete(self, user_id: str, attachment_id: str) -> bool:
        """Soft delete an attachment"""
        doc_ref = self.db.collection(self.collection_name).document(attachment_id)
        doc = await doc_ref.get()
        
        if not doc.exists:
            return False
            
        doc_data = doc.to_dict()
        if doc_data.get("user_id") != user_id:
            return False
            
        await doc_ref.update({
            "is_deleted": True,
            "updated_on": utc_now(),
            "updated_by": user_id
        })
        
        return True

    async def update(self, user_id: str, attachment_id: str, update_data: dict) -> Optional[Attachment]:
        """Update attachment metadata"""
        doc_ref = self.db.collection(self.collection_name).document(attachment_id)
        doc = await doc_ref.get()
        
        if not doc.exists:
            return None
            
        doc_data = doc.to_dict()
        if doc_data.get("user_id") != user_id or doc_data.get("is_deleted", False):
            return None
            
        update_data["updated_on"] = utc_now()
        update_data["updated_by"] = user_id
        
        await doc_ref.update(update_data)
        
        # Return updated document
        updated_doc = await doc_ref.get()
        return self._to_domain(updated_doc.to_dict()) 