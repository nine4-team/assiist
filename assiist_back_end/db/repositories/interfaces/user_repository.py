from abc import ABC, abstractmethod
from typing import List, Optional, Dict
from assiist_back_end.models.user import User

class UserRepository(ABC):
    """Repository interface for user operations."""
    
    @abstractmethod
    async def get_users_by_account(self, account_id: str) -> List[User]:
        """Get all users for a specific account."""
        pass
    
    @abstractmethod
    async def get_by_id(self, user_id: str) -> Optional[User]:
        """Get a user by their ID."""
        pass
    
    @abstractmethod
    async def get_fcm_tokens(self, user_id: str) -> List[str]:
        """Get FCM tokens for a user."""
        pass
    
    @abstractmethod
    async def save_fcm_token(self, user_id: str, token: str, platform: str) -> bool:
        """Save an FCM token for a user."""
        pass
    
    @abstractmethod
    async def remove_fcm_token(self, user_id: str, token: str) -> bool:
        """Remove an FCM token for a user."""
        pass 