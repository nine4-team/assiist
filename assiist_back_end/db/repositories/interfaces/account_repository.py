from abc import ABC, abstractmethod
from typing import Optional
from ....models.account_models import AccountDetailsResponse, AccountDetailsUpdateRequest

class AccountRepository(ABC):
    """Repository interface for account-level operations."""
    
    @abstractmethod
    async def get_account_details(self, account_id: str) -> Optional[AccountDetailsResponse]:
        """Get the account's details including business description and type."""
        pass
    
    @abstractmethod
    async def update_account_details(self, account_id: str, details: AccountDetailsUpdateRequest) -> AccountDetailsResponse:
        """Update the account's business description and/or type."""
        pass 