import os
import uuid
import re
import mimetypes
from assiist_back_end.utils.time import utc_now
from pathlib import Path
from typing import Optional, Set

from google.cloud import storage
from fastapi import UploadFile, HTTPException

from assiist_back_end.db.repositories.interfaces.attachment_repository import AttachmentRepository
from assiist_back_end.models.attachment import Attachment


class AttachmentService:
    """Service for handling file attachments"""
    
    # Configuration constants
    MAX_FILE_SIZE_MB = 10
    MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_MB * 1024 * 1024
    
    ALLOWED_FILE_TYPES: Set[str] = {
        # Images
        "image/jpeg", "image/jpg", "image/png", "image/gif", "image/webp",
        # Documents
        "application/pdf", "text/plain", "text/csv",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.ms-powerpoint",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        # Audio
        "audio/mpeg", "audio/mp3", "audio/mp4", "audio/x-m4a", "audio/wav"
    }
    
    def __init__(self, storage_client: storage.Client, bucket_name: str, attachment_repo: AttachmentRepository, base_url: str = None):
        self.storage_client = storage_client
        self.bucket_name = bucket_name
        self.attachment_repo = attachment_repo
        self.bucket = storage_client.bucket(bucket_name)
        # Get base URL from environment or parameter
        api_url = base_url or os.getenv('API_URL')
        if not api_url:
            raise ValueError("API_URL environment variable is required")
        self.base_url = api_url.replace('/api/v1', '').rstrip('/')
    
    def _sanitize_filename(self, filename: str) -> str:
        """Sanitize filename for safe storage"""
        # Get file extension
        stem = Path(filename).stem
        suffix = Path(filename).suffix
        
        # Remove or replace problematic characters
        safe_stem = re.sub(r'[^a-zA-Z0-9_-]', '_', stem)
        safe_stem = re.sub(r'_+', '_', safe_stem)  # Replace multiple underscores with single
        safe_stem = safe_stem.strip('_')  # Remove leading/trailing underscores
        
        # Ensure it's not empty
        if not safe_stem:
            safe_stem = "file"
        
        # Limit length
        if len(safe_stem) > 50:
            safe_stem = safe_stem[:50]
        
        return f"{safe_stem}{suffix}"
    
    def _validate_file(self, file: UploadFile) -> None:
        """Validate uploaded file"""
        # Check file type
        if file.content_type not in self.ALLOWED_FILE_TYPES:
            raise HTTPException(
                status_code=400,
                detail=f"File type '{file.content_type}' not allowed. Allowed types: {', '.join(self.ALLOWED_FILE_TYPES)}"
            )
        
        # Check file size
        if file.size and file.size > self.MAX_FILE_SIZE_BYTES:
            raise HTTPException(
                status_code=400,
                detail=f"File size ({file.size} bytes) exceeds maximum allowed size ({self.MAX_FILE_SIZE_MB}MB)"
            )
        
        # Check filename
        if not file.filename:
            raise HTTPException(status_code=400, detail="Filename is required")
    
    def _generate_storage_path(self, account_id: str, user_id: str, filename: str) -> str:
        """Generate unique storage path for the file"""
        # Create a path structure: account_id/user_id/year/month/uuid_filename
        now = utc_now()
        year_month = f"{now.year}/{now.month:02d}"
        unique_id = str(uuid.uuid4())
        
        return f"{account_id}/{user_id}/{year_month}/{unique_id}_{filename}"
    
    async def upload_file(
        self, 
        file: UploadFile, 
        user_id: str, 
        account_id: str
    ) -> Attachment:
        """Upload file to cloud storage and create attachment record"""
        
        # Validate file
        self._validate_file(file)
        
        # Sanitize filename
        sanitized_filename = self._sanitize_filename(file.filename)
        
        # Generate storage path
        storage_path = self._generate_storage_path(account_id, user_id, sanitized_filename)
        
        try:
            # Upload to Cloud Storage
            blob = self.bucket.blob(storage_path)
            
            # Read file content
            content = await file.read()
            
            # Upload with metadata
            blob.upload_from_string(
                content,
                content_type=file.content_type
            )
            
            # Note: Bucket is configured with uniform bucket-level access for public reads
            # No need to call blob.make_public() which would fail with uniform access
            
            # Create attachment record
            attachment = Attachment(
                id=str(uuid.uuid4()),
                account_id=account_id,
                user_id=user_id,
                filename=sanitized_filename,
                original_filename=file.filename,
                file_type=file.content_type,
                file_size=len(content),
                gcs_url=blob.public_url,  # Store the full GCS URL for backend redirection
                storage_path=storage_path,
                created_by=user_id,
                updated_by=user_id
            )
            
            # Use direct GCS URL for immediate functionality
            # Keep short URL infrastructure for future enhancement
            attachment.public_url = blob.public_url  # Direct GCS URL
            # Note: short_id is still generated and stored in attachment.__init__()
            
            # Save to database
            created_attachment = await self.attachment_repo.create(attachment)
            
            return created_attachment
            
        except Exception as e:
            # Clean up uploaded file if database save fails
            try:
                blob = self.bucket.blob(storage_path)
                if blob.exists():
                    blob.delete()
            except:
                pass  # Ignore cleanup errors
            
            raise HTTPException(
                status_code=500,
                detail=f"Failed to upload file: {str(e)}"
            )
    
    async def delete_attachment(self, user_id: str, attachment_id: str) -> bool:
        """Delete attachment and associated file"""
        # Get attachment metadata
        attachment = await self.attachment_repo.get_by_id(user_id, attachment_id)
        if not attachment:
            return False
        
        try:
            # Delete from Cloud Storage
            blob = self.bucket.blob(attachment.storage_path)
            if blob.exists():
                blob.delete()
        except Exception as e:
            # Log the error but continue with soft delete
            print(f"Warning: Failed to delete file from storage: {e}")
        
        # Soft delete from database
        return await self.attachment_repo.delete(user_id, attachment_id)
    
    async def get_attachment(self, user_id: str, attachment_id: str) -> Optional[Attachment]:
        """Get attachment metadata"""
        return await self.attachment_repo.get_by_id(user_id, attachment_id)
    
    async def list_user_attachments(self, user_id: str, limit: int = 100) -> list[Attachment]:
        """List all attachments for a user"""
        return await self.attachment_repo.get_by_user(user_id, limit) 