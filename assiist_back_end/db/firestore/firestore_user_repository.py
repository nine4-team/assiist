from google.cloud.firestore_v1.async_client import AsyncClient
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from assiist_back_end.db.repositories.interfaces.user_repository import UserRepository
from assiist_back_end.models.user import User
from typing import List, Optional
import logging

logger = logging.getLogger(__name__)

class FirestoreUserRepository(UserRepository):
    def __init__(self, db: AsyncClient):
        self.db = db
    
    async def get_users_by_account(self, account_id: str) -> List[User]:
        """Get all users for a specific account."""
        try:
            query = (self.db.collection("users")
                    .where(filter=FieldFilter("account_id", "==", account_id)))
            
            docs = await query.get()
            users = []
            
            for doc in docs:
                user_data = doc.to_dict()
                user_data['id'] = doc.id  # Add the document ID as id
                user = self._map_to_domain(user_data)
                users.append(user)
            
            logger.info(f"📋 Found {len(users)} users for account {account_id}")
            return users
            
        except Exception as e:
            logger.error(f"❌ Failed to get users for account {account_id}: {e}")
            return []
    
    async def get_by_id(self, user_id: str) -> Optional[User]:
        """Get a user by their ID."""
        try:
            doc_ref = self.db.collection("users").document(user_id)
            doc = await doc_ref.get()
            
            if not doc.exists:
                return None
                
            user_data = doc.to_dict()
            user_data['id'] = doc.id
            return self._map_to_domain(user_data)
            
        except Exception as e:
            logger.error(f"❌ Failed to get user {user_id}: {e}")
            return None
    
    async def get_fcm_tokens(self, user_id: str) -> List[str]:
        """Get FCM tokens for a user from their device_tokens subcollection."""
        try:
            tokens_query = (self.db.collection("users")
                           .document(user_id)
                           .collection("device_tokens"))
            
            docs = [doc async for doc in tokens_query.stream()]

            logger.info(f"📱 device_tokens docs count for user {user_id}: {len(docs)}")
            tokens: List[str] = []

            for doc in docs:
                # Canonical source of truth is the document ID (matches FCM token)
                token = doc.id

                logger.debug(f"📱 Token doc ID (used as token): {token[:25]}…")

                if token:
                    tokens.append(token)
            
            logger.info(f"📱 Found {len(tokens)} FCM tokens for user {user_id}")
            return tokens
            
        except Exception as e:
            logger.error(f"❌ Failed to get FCM tokens for user {user_id}: {e}")
            return []
    
    async def save_fcm_token(self, user_id: str, token: str, platform: str) -> bool:
        """Save an FCM token for a user."""
        try:
            token_ref = (self.db.collection("users")
                        .document(user_id)
                        .collection("device_tokens")
                        .document(token))
            
            await token_ref.set({
                'token': token,
                'created_on': firestore.SERVER_TIMESTAMP,
                'platform': platform,
            }, merge=True)
            
            logger.info(f"📱 Saved FCM token for user {user_id}")
            return True
            
        except Exception as e:
            logger.error(f"❌ Failed to save FCM token for user {user_id}: {e}")
            return False
    
    async def remove_fcm_token(self, user_id: str, token: str) -> bool:
        """Remove an FCM token for a user."""
        try:
            token_ref = (self.db.collection("users")
                        .document(user_id)
                        .collection("device_tokens")
                        .document(token))
            
            await token_ref.delete()
            logger.info(f"📱 Removed FCM token for user {user_id}")
            return True
            
        except Exception as e:
            logger.error(f"❌ Failed to remove FCM token for user {user_id}: {e}")
            return False
    
    def _map_to_domain(self, user_data: dict) -> User:
        """Map Firestore document to User domain model."""
        return User(
            id=user_data.get('id'),
            email=user_data.get('email'),
            first_name=user_data.get('first_name'),
            last_name=user_data.get('last_name'),
            account_id=user_data.get('account_id'),
            created_on=user_data.get('created_on'),
            updated_on=user_data.get('updated_on'),
            timezone=user_data.get('timezone', 'UTC')
        ) 