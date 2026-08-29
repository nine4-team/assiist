from datetime import datetime
from typing import Optional
import secrets
import string


class Attachment:
    """Domain model for file attachments"""
    
    def __init__(
        self,
        id: Optional[str] = None,
        account_id: Optional[str] = None,
        user_id: Optional[str] = None,
        filename: Optional[str] = None,
        original_filename: Optional[str] = None,
        file_type: Optional[str] = None,
        file_size: Optional[int] = None,
        public_url: Optional[str] = None,
        gcs_url: Optional[str] = None,
        storage_path: Optional[str] = None,
        short_id: Optional[str] = None,
        created_on: Optional[datetime] = None,
        updated_on: Optional[datetime] = None,
        created_by: Optional[str] = None,
        updated_by: Optional[str] = None,
        is_deleted: bool = False
    ):
        self.id = id
        self.account_id = account_id
        self.user_id = user_id
        self.filename = filename
        self.original_filename = original_filename
        self.file_type = file_type
        self.file_size = file_size
        self.public_url = public_url
        self.gcs_url = gcs_url
        self.storage_path = storage_path
        self.short_id = short_id or self._generate_short_id()
        self.created_on = created_on
        self.updated_on = updated_on
        self.created_by = created_by
        self.updated_by = updated_by
        self.is_deleted = is_deleted

    def _generate_short_id(self) -> str:
        """Generate a 6-character random short ID for URLs"""
        alphabet = string.ascii_lowercase + string.digits
        return ''.join(secrets.choice(alphabet) for _ in range(6))
    
    def get_short_url(self, base_url: str) -> str:
        """Generate the short URL for this attachment"""
        return f"{base_url}/f/{self.short_id}"

    def __repr__(self):
        return f"Attachment(id='{self.id}', filename='{self.filename}', file_type='{self.file_type}', short_id='{self.short_id}')" 