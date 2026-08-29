from typing import List, Dict, Any, Optional
import httpx
import asyncio
import os
import logging

logger = logging.getLogger(__name__)

class AdminPortalService:
    def __init__(self):
        from assiist_back_end.config import settings
        
        api_url = os.environ.get("API_URL")
        if not api_url:
            raise ValueError("API_URL environment variable is required")
        self.base_url = api_url
        
        self.internal_key = settings.ASSIIST_API_KEY.get_secret_value() if settings.ASSIIST_API_KEY else None
        if not self.internal_key:
            raise ValueError("ASSIIST_API_KEY environment variable is required")
        
        self.headers = {
            "X-Internal-API-Key": self.internal_key,
            "Content-Type": "application/json"
        }
    
    async def create_account_only(self, account_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create account without owner user"""
        async with httpx.AsyncClient() as client:
            try:
                logger.info(f"Creating account with data: {account_data}")
                response = await client.post(
                    f"{self.base_url}/internal/accounts/",
                    json=account_data,
                    headers=self.headers,
                    timeout=30.0
                )
                logger.info(f"Account creation response status: {response.status_code}")
                
                if not response.is_success:
                    error_detail = None
                    try:
                        error_detail = response.json()
                        logger.error(f"Account creation failed with error details: {error_detail}")
                    except:
                        error_detail = response.text
                        logger.error(f"Account creation failed with error text: {error_detail}")
                
                response.raise_for_status()
                result = response.json()
                logger.info(f"Account created successfully: {result.get('id')}")
                return result
            except httpx.HTTPError as e:
                logger.error(f"Account creation failed: {e}")
                raise
    
    async def create_account_with_owner(self, account_data: Dict[str, Any], 
                                      owner_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create account and owner user in single operation"""
        async with httpx.AsyncClient() as client:
            try:
                # Create account first
                logger.info(f"Creating account with data: {account_data}")
                account_response = await client.post(
                    f"{self.base_url}/internal/accounts/",
                    json=account_data,
                    headers=self.headers,
                    timeout=30.0
                )
                logger.info(f"Account creation response status: {account_response.status_code}")
                
                if not account_response.is_success:
                    error_detail = None
                    try:
                        error_detail = account_response.json()
                        logger.error(f"Account creation failed with error details: {error_detail}")
                    except:
                        error_detail = account_response.text
                        logger.error(f"Account creation failed with error text: {error_detail}")
                
                account_response.raise_for_status()
                account = account_response.json()
                
                # Add account_id to owner data - API returns 'id' not 'account_id'
                owner_data["account_id"] = account["id"]
                logger.info(f"Creating owner user with data: {owner_data}")
                
                # Create owner user
                user_response = await client.post(
                    f"{self.base_url}/internal/users/",
                    json=owner_data,
                    headers=self.headers,
                    timeout=30.0
                )
                logger.info(f"User creation response status: {user_response.status_code}")
                
                if not user_response.is_success:
                    error_detail = None
                    try:
                        error_detail = user_response.json()
                        logger.error(f"User creation failed with error details: {error_detail}")
                    except:
                        error_detail = user_response.text
                        logger.error(f"User creation failed with error text: {error_detail}")
                
                user_response.raise_for_status()
                user = user_response.json()
                
                logger.info(f"Account and owner created: account={account.get('id')}, user={user.get('id')}")
                
                return {
                    "account": account,
                    "owner_user": user,
                    "success": True
                }
            except httpx.HTTPError as e:
                logger.error(f"Account + owner creation failed: {e}")
                raise
    
    async def create_user(self, user_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create user in existing account"""
        async with httpx.AsyncClient() as client:
            try:
                response = await client.post(
                    f"{self.base_url}/internal/users/",
                    json=user_data,
                    headers=self.headers,
                    timeout=30.0
                )
                response.raise_for_status()
                result = response.json()
                logger.info(f"User created successfully: {result.get('id')}")
                return result
            except httpx.HTTPError as e:
                logger.error(f"User creation failed: {e}")
                raise
    
    async def get_all_accounts(self) -> List[Dict[str, Any]]:
        """Get all accounts using internal API"""
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(
                    f"{self.base_url}/internal/accounts/",
                    headers=self.headers,
                    timeout=30.0
                )
                response.raise_for_status()
                result = response.json()
                logger.info(f"Retrieved {len(result)} accounts")
                return result
            except httpx.HTTPError as e:
                logger.error(f"Failed to fetch accounts: {e}")
                raise
    
    async def get_all_users(self) -> List[Dict[str, Any]]:
        """Get all users using internal API"""
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(
                    f"{self.base_url}/internal/users/",
                    headers=self.headers,
                    timeout=30.0
                )
                response.raise_for_status()
                result = response.json()
                logger.info(f"Retrieved {len(result)} users")
                return result
            except httpx.HTTPError as e:
                logger.error(f"Failed to fetch users: {e}")
                raise
    
    async def get_account_by_id(self, account_id: str) -> Optional[Dict[str, Any]]:
        """Get single account by ID"""
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(
                    f"{self.base_url}/internal/accounts/{account_id}",
                    headers=self.headers,
                    timeout=30.0
                )
                if response.status_code == 404:
                    return None
                response.raise_for_status()
                return response.json()
            except httpx.HTTPError as e:
                logger.error(f"Failed to fetch account {account_id}: {e}")
                raise
    
    async def soft_delete_account(self, account_id: str, deleter_user_id: str) -> Dict[str, Any]:
        """Soft delete account by ID following repository pattern"""
        async with httpx.AsyncClient() as client:
            try:
                # Call internal API with soft delete data
                delete_data = {
                    "deleter_user_id": deleter_user_id,
                    "soft_delete": True
                }
                response = await client.delete(
                    f"{self.base_url}/internal/accounts/{account_id}",
                    json=delete_data,
                    headers=self.headers,
                    timeout=30.0
                )
                if response.status_code == 404:
                    raise httpx.HTTPError(f"Account {account_id} not found")
                response.raise_for_status()
                logger.info(f"Account soft deleted successfully: {account_id} by user {deleter_user_id}")
                return {"success": True, "message": f"Account {account_id} marked as deleted"}
            except httpx.HTTPError as e:
                logger.error(f"Account soft deletion failed: {e}")
                raise
    
    async def soft_delete_user(self, user_id: str, deleter_user_id: str) -> Dict[str, Any]:
        """Soft delete user by ID following repository pattern"""
        async with httpx.AsyncClient() as client:
            try:
                # Call internal API with soft delete data
                delete_data = {
                    "deleter_user_id": deleter_user_id,
                    "soft_delete": True
                }
                response = await client.delete(
                    f"{self.base_url}/internal/users/{user_id}",
                    json=delete_data,
                    headers=self.headers,
                    timeout=30.0
                )
                if response.status_code == 404:
                    raise httpx.HTTPError(f"User {user_id} not found")
                response.raise_for_status()
                logger.info(f"User soft deleted successfully: {user_id} by user {deleter_user_id}")
                return {"success": True, "message": f"User {user_id} marked as deleted"}
            except httpx.HTTPError as e:
                logger.error(f"User soft deletion failed: {e}")
                raise

    async def get_genai_requests(
        self,
        request_type: Optional[str] = None,
        request_status: Optional[str] = None,
        search: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Get GenAI requests with optional filters"""
        async with httpx.AsyncClient(follow_redirects=True) as client:
            try:
                # Build query parameters
                params = {}
                if request_type:
                    params['request_type'] = request_type
                if request_status:
                    params['request_status'] = request_status  # Changed to use request_status consistently
                if search:
                    params['search'] = search

                logger.info(f"Fetching GenAI requests with params: {params}")
                response = await client.get(
                    f"{self.base_url}/genai/requests",
                    headers=self.headers,
                    params=params,
                    timeout=30.0
                )
                response.raise_for_status()
                result = response.json()
                logger.info(f"Retrieved {len(result)} GenAI requests")
                return result
            except httpx.HTTPError as e:
                logger.error(f"Failed to fetch GenAI requests: {e}")
                raise

    async def get_genai_request_by_id(self, request_id: str) -> Optional[Dict[str, Any]]:
        """Get single GenAI request by ID"""
        async with httpx.AsyncClient(follow_redirects=True) as client:
            try:
                response = await client.get(
                    f"{self.base_url}/genai/requests/{request_id}",
                    headers=self.headers,
                    timeout=30.0
                )
                if response.status_code == 404:
                    return None
                response.raise_for_status()
                return response.json()
            except httpx.HTTPError as e:
                logger.error(f"Failed to fetch GenAI request {request_id}: {e}")
                raise 