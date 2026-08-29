from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import RedirectResponse
from dependency_injector.wiring import inject, Provide
from assiist_back_end.containers import Container
from assiist_back_end.db.repositories.interfaces.attachment_repository import AttachmentRepository

router = APIRouter()

@router.get("/{short_id}")
@inject
async def get_file_by_short_id(
    short_id: str,
    attachment_repo: AttachmentRepository = Depends(Provide[Container.attachment_repository])
):
    """
    Public endpoint to redirect to files using short IDs.
    No authentication required - short IDs act as access tokens.
    URL format: /f/{short_id} (e.g., /f/a3k9m2)
    """
    try:
        # Get attachment by short ID (no user context needed for public access)
        attachment = await attachment_repo.get_by_short_id(short_id)
        
        if not attachment:
            raise HTTPException(status_code=404, detail="File not found")
        
        # Redirect to the actual GCS URL (use gcs_url if available, fallback to public_url)
        redirect_url = attachment.gcs_url or attachment.public_url
        return RedirectResponse(url=redirect_url, status_code=302)
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error accessing file: {str(e)}") 