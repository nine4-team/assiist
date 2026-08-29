from fastapi import APIRouter, Request, Depends, HTTPException, status
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, JSONResponse
from .services import AdminPortalService
from .models import CreateAccountRequest, CreateUserRequest, CreateOwnerUserRequest
from typing import Dict, Any, Optional
import logging

logger = logging.getLogger(__name__)

# Initialize templates
templates = Jinja2Templates(directory="assiist_back_end/admin/templates")

# Create routers
admin_router = APIRouter(prefix="/admin", tags=["Admin Portal"])
api_router = APIRouter(prefix="/admin/api", tags=["Admin Portal API"])

# Initialize service
admin_service = AdminPortalService()

# HTML Pages
@admin_router.get("/", response_class=HTMLResponse)
async def portal_home(request: Request):
    """Admin portal home page"""
    return templates.TemplateResponse("layout.html", {"request": request})

@admin_router.get("/accounts", response_class=HTMLResponse) 
async def accounts_page(request: Request):
    """Accounts management page"""
    return templates.TemplateResponse("accounts/list.html", {"request": request})

@admin_router.get("/accounts/create", response_class=HTMLResponse)
async def create_account_page(request: Request):
    """Account creation form"""
    return templates.TemplateResponse("accounts/create.html", {"request": request})

@admin_router.get("/users", response_class=HTMLResponse)
async def users_page(request: Request):
    """Users management page"""  
    return templates.TemplateResponse("users/list.html", {"request": request})

@admin_router.get("/users/create", response_class=HTMLResponse)
async def create_user_page(request: Request):
    """User creation form"""
    return templates.TemplateResponse("users/create.html", {"request": request})

@admin_router.get("/genai-requests", response_class=HTMLResponse)
async def genai_requests_page(request: Request):
    """GenAI requests management page"""
    return templates.TemplateResponse("genai_requests/list.html", {"request": request})

# API Endpoints for AJAX calls
@api_router.post("/accounts")
async def create_account_only(account_data: CreateAccountRequest):
    """Create account without owner user"""
    try:
        result = await admin_service.create_account_only(account_data.dict())
        return JSONResponse(
            status_code=status.HTTP_201_CREATED,
            content={"success": True, "data": result}
        )
    except Exception as e:
        logger.error(f"Account creation failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Account creation failed: {str(e)}"
        )

@api_router.post("/accounts/with-owner")
async def create_account_with_owner(request: dict):
    """Create account and owner user in single operation"""
    try:
        account_data = request.get("account_data", {})
        owner_data = request.get("owner_data", {})
        
        result = await admin_service.create_account_with_owner(
            account_data,
            owner_data
        )
        return JSONResponse(
            status_code=status.HTTP_201_CREATED,
            content={"success": True, "data": result}
        )
    except Exception as e:
        logger.error(f"Account + owner creation failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Account and owner creation failed: {str(e)}"
        )

@api_router.post("/users")
async def create_user(user_data: CreateUserRequest):
    """Create user in existing account"""
    try:
        result = await admin_service.create_user(user_data.dict())
        return JSONResponse(
            status_code=status.HTTP_201_CREATED,
            content={"success": True, "data": result}
        )
    except Exception as e:
        logger.error(f"User creation failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"User creation failed: {str(e)}"
        )

@api_router.get("/accounts")
async def get_all_accounts():
    """Get all accounts"""
    try:
        accounts = await admin_service.get_all_accounts()
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={"success": True, "data": accounts}
        )
    except Exception as e:
        logger.error(f"Failed to fetch accounts: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch accounts: {str(e)}"
        )

@api_router.get("/users")
async def get_all_users():
    """Get all users"""
    try:
        users = await admin_service.get_all_users()
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={"success": True, "data": users}
        )
    except Exception as e:
        logger.error(f"Failed to fetch users: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch users: {str(e)}"
        )

@api_router.get("/accounts/{account_id}")
async def get_account_by_id(account_id: str):
    """Get single account by ID"""
    try:
        account = await admin_service.get_account_by_id(account_id)
        if account is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Account not found"
            )
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={"success": True, "data": account}
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to fetch account {account_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch account: {str(e)}"
        )

@api_router.delete("/accounts/{account_id}")
async def soft_delete_account(account_id: str, request: dict):
    """Soft delete account by ID"""
    try:
        deleter_user_id = request.get("deleter_user_id")
        if not deleter_user_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="deleter_user_id is required"
            )
        
        result = await admin_service.soft_delete_account(account_id, deleter_user_id)
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={"success": True, "data": result}
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to delete account {account_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to delete account: {str(e)}"
        )

@api_router.delete("/users/{user_id}")
async def soft_delete_user(user_id: str, request: dict):
    """Soft delete user by ID"""
    try:
        deleter_user_id = request.get("deleter_user_id")
        if not deleter_user_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="deleter_user_id is required"
            )
        
        result = await admin_service.soft_delete_user(user_id, deleter_user_id)
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={"success": True, "data": result}
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to delete user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to delete user: {str(e)}"
        )

# API Endpoints for GenAI Requests
@api_router.get("/genai-requests")
async def get_genai_requests(
    request_type: Optional[str] = None,
    request_status: Optional[str] = None,
    search: Optional[str] = None
):
    """Get all GenAI requests with optional filters"""
    try:
        requests = await admin_service.get_genai_requests(
            request_type=request_type,
            request_status=request_status,
            search=search
        )
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={"success": True, "data": requests}
        )
    except Exception as e:
        logger.error(f"Failed to fetch GenAI requests: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch GenAI requests"
        )

@api_router.get("/genai-requests/{request_id}")
async def get_genai_request_by_id(request_id: str):
    """Get single GenAI request by ID"""
    try:
        request = await admin_service.get_genai_request_by_id(request_id)
        if not request:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="GenAI request not found"
            )
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={"success": True, "data": request}
        )
    except Exception as e:
        logger.error(f"Failed to fetch GenAI request {request_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch GenAI request: {str(e)}"
        ) 