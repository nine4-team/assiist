import os
import logging
from typing import Optional
from google.cloud.firestore_v1.async_client import AsyncClient
from google.oauth2 import service_account
from .connection_pool import FirestoreConnectionPool

logger = logging.getLogger(__name__)

# Initialize connection pool
_connection_pool: Optional[FirestoreConnectionPool] = None

def get_connection_pool() -> FirestoreConnectionPool:
    """Get or create the Firestore connection pool."""
    global _connection_pool
    
    if _connection_pool is None:
        project_id = os.getenv("FIRESTORE_PROJECT_ID", "assiist-app")
        database_id = os.getenv("FIRESTORE_DATABASE_ID", "assiist-app")
        credentials_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
        
        if not all([project_id, credentials_path]):
            raise ValueError(
                "Missing required environment variables for Firestore. "
                "Please set FIRESTORE_PROJECT_ID and GOOGLE_APPLICATION_CREDENTIALS."
            )
            
        _connection_pool = FirestoreConnectionPool(
            project_id=project_id,
            database_id=database_id,
            credentials_path=credentials_path,
            pool_size=5,  # Adjust based on your needs
            max_retries=3,
            retry_delay=1.0,
            connection_timeout=5.0
        )
        
    return _connection_pool

async def get_client() -> AsyncClient:
    """Get a Firestore client from the connection pool."""
    pool = get_connection_pool()
    return await pool.get_client()

async def release_client(client: AsyncClient):
    """Return a Firestore client to the connection pool."""
    if _connection_pool is not None:
        await _connection_pool.release_client(client)

async def close_connection_pool():
    """Close the Firestore connection pool."""
    global _connection_pool
    if _connection_pool is not None:
        await _connection_pool.close()
        _connection_pool = None 