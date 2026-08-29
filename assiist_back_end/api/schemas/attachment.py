from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional


class AttachmentUploadResponse(BaseModel):
    """Response schema for file upload"""
    attachment_id: str = Field(..., description="Unique identifier for the attachment")
    public_url: str = Field(..., description="Public URL to access the uploaded file")
    filename: str = Field(..., description="Sanitized filename stored in cloud storage")
    original_filename: str = Field(..., description="Original filename provided by user")
    file_type: str = Field(..., description="MIME type of the file")
    file_size: int = Field(..., description="File size in bytes")
    created_on: datetime = Field(..., description="When the attachment was created")


class AttachmentMetadata(BaseModel):
    """Complete attachment metadata for database storage"""
    id: str = Field(..., description="Unique identifier")
    account_id: str = Field(..., description="Account the attachment belongs to")
    user_id: str = Field(..., description="User who uploaded the attachment")
    filename: str = Field(..., description="Sanitized filename in storage")
    original_filename: str = Field(..., description="Original filename from user")
    file_type: str = Field(..., description="MIME type of the file")
    file_size: int = Field(..., description="Size in bytes")
    public_url: str = Field(..., description="Public URL to access the file")
    storage_path: str = Field(..., description="Path in cloud storage bucket")
    created_on: datetime = Field(..., description="Creation timestamp")
    updated_on: datetime = Field(..., description="Last update timestamp")
    created_by: str = Field(..., description="User ID who created")
    updated_by: str = Field(..., description="User ID who last updated")
    is_deleted: bool = Field(default=False, description="Soft deletion flag")


class AttachmentResponseSchema(BaseModel):
    """Response schema for attachment retrieval"""
    id: str
    filename: str
    original_filename: str
    file_type: str
    file_size: int
    public_url: str
    created_on: datetime 