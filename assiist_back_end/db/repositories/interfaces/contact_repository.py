from abc import ABC, abstractmethod
from typing import List, Optional, Dict, Any
from datetime import datetime

# Assuming the domain model is in core.models
# Adjust the import path if your structure is different
# from core.models.contact import Contact
from assiist_back_end.models.contact import Contact # Use absolute import

class ContactRepository(ABC):
    """Abstract interface for contact data operations, scoped by account."""

    @abstractmethod
    async def get_contact_by_id(self, account_id: str, contact_id: str) -> Optional[Contact]:
        """Fetches a single contact by its ID, ensuring it belongs to the specified account."""
        pass

    @abstractmethod
    async def get_contact_by_email(self, account_id: str, email: str) -> Optional[Contact]:
        """Fetches a single contact by its email address, ensuring it belongs to the specified account."""
        pass

    @abstractmethod
    async def get_contact_by_phone(self, account_id: str, phone: str) -> Optional[Contact]:
        """Fetches a single contact by its phone number, ensuring it belongs to the specified account."""
        pass

    @abstractmethod
    async def get_contacts_by_account(
        self, account_id: str, limit: int = 50, offset: int = 0
    ) -> List[Contact]:
        """Retrieves a list of contacts belonging to a specific account."""
        pass

    @abstractmethod
    async def get_contacts_changed_since(
        self,
        account_id: str,
        timestamp: datetime,
        limit: int = 500,
    ) -> List[Contact]:
        """Return contacts whose `updated_on` is greater than the supplied timestamp.

        Args:
            account_id: Owner account.
            timestamp: Lower bound (exclusive) for contact `updated_on`.
            limit: Optional safety cap – default 500.
        """
        pass

    @abstractmethod
    async def create_contact(self, contact: Contact) -> Contact:
        """Creates a new contact. Assumes account_id is set on the input contact object."""
        pass

    @abstractmethod
    async def update_contact(self, account_id: str, contact_id: str, updates: Dict[str, Any], updater_user_id: str) -> Optional[Contact]:
        """Updates a contact, ensuring it belongs to the account and logging the updater."""
        pass

    @abstractmethod
    async def delete_contact(self, account_id: str, contact_id: str, deleter_user_id: str, hard_delete: bool = False) -> bool:
        """Deletes a contact, ensuring it belongs to the account and logging the deleter.
        
        Args:
            account_id: The account ID that owns the contact
            contact_id: The ID of the contact to delete
            deleter_user_id: The ID of the user performing the deletion
            hard_delete: If True, permanently deletes the contact.
                        If False (default), performs soft delete by marking as deleted.
        
        Returns:
            bool: True if deletion was successful
        """
        pass

    @abstractmethod
    async def search_contacts_by_account(
        self, 
        account_id: str, 
        search_term: str, 
        limit: int = 50, 
        offset: int = 0,
        search_fields: List[str] = ['first_name', 'last_name', 'email', 'phone_mobile', 'phone_work', 'phone_home', 'business_name', 'addressed_as']
    ) -> List[Contact]:
        """Searches contacts within an account based on a term across specified fields."""
        pass

    # Add other methods as needed, e.g.:
    # @abstractmethod
    # async def search_contacts(self, user_id: str, query: str) -> List[Contact]:
    #     pass

    # @abstractmethod
    # async def get_contacts_by_tag(self, user_id: str, tag: str) -> List[Contact]:
    #     pass 