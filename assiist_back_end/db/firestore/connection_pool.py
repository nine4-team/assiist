import asyncio
import logging
from typing import Optional
from google.cloud.firestore_v1.async_client import AsyncClient
from google.oauth2 import service_account
from google.api_core.exceptions import ServiceUnavailable, Unavailable

logger = logging.getLogger(__name__)

class FirestoreConnectionPool:
    """Manages a pool of Firestore connections with automatic reconnection."""
    
    def __init__(
        self,
        project_id: str,
        database_id: str,
        credentials_path: str,
        pool_size: int = 5,
        max_retries: int = 3,
        retry_delay: float = 1.0,
        connection_timeout: float = 5.0
    ):
        self.project_id = project_id
        self.database_id = database_id
        self.credentials_path = credentials_path
        self.pool_size = pool_size
        self.max_retries = max_retries
        self.retry_delay = retry_delay
        self.connection_timeout = connection_timeout
        
        self._pool: list[AsyncClient] = []
        self._available: asyncio.Queue[AsyncClient] = asyncio.Queue()
        self._lock = asyncio.Lock()
        self._initialized = False
        
    async def initialize(self):
        """Initialize the connection pool."""
        if self._initialized:
            return
            
        async with self._lock:
            if self._initialized:  # Double-check pattern
                return
                
            try:
                credentials = service_account.Credentials.from_service_account_file(
                    self.credentials_path
                )
                
                # Create initial pool of clients
                for _ in range(self.pool_size):
                    client = AsyncClient(
                        project=self.project_id,
                        database=self.database_id,
                        credentials=credentials
                    )
                    self._pool.append(client)
                    await self._available.put(client)
                    
                self._initialized = True
                logger.info(f"Firestore connection pool initialized with {self.pool_size} connections")
                
            except Exception as e:
                logger.error(f"Failed to initialize Firestore connection pool: {e}")
                raise
                
    async def get_client(self) -> AsyncClient:
        """Get a client from the pool with automatic reconnection."""
        if not self._initialized:
            await self.initialize()
            
        for attempt in range(self.max_retries):
            try:
                # Get a client from the pool with timeout
                client = await asyncio.wait_for(
                    self._available.get(),
                    timeout=self.connection_timeout
                )
                
                # Test the connection
                try:
                    async with asyncio.timeout(self.connection_timeout):
                        # Simple test query
                        await client.collection('_test').limit(1).get()
                    return client
                except (asyncio.TimeoutError, ServiceUnavailable, Unavailable):
                    # Connection is bad, try to create a new one
                    logger.warning(f"Bad connection detected, attempting to create new client (attempt {attempt + 1})")
                    await self._create_new_client()
                    continue
                    
            except asyncio.TimeoutError:
                if attempt == self.max_retries - 1:
                    raise TimeoutError("Failed to get a valid Firestore client from the pool")
                await asyncio.sleep(self.retry_delay)
                
        raise RuntimeError("Failed to get a valid Firestore client after all retries")
        
    async def release_client(self, client: AsyncClient):
        """Return a client to the pool."""
        if client in self._pool:
            await self._available.put(client)
            
    async def _create_new_client(self):
        """Create a new client and add it to the pool."""
        try:
            credentials = service_account.Credentials.from_service_account_file(
                self.credentials_path
            )
            
            new_client = AsyncClient(
                project=self.project_id,
                database=self.database_id,
                credentials=credentials
            )
            
            self._pool.append(new_client)
            await self._available.put(new_client)
            logger.info("Created new Firestore client and added to pool")
            
        except Exception as e:
            logger.error(f"Failed to create new Firestore client: {e}")
            raise
            
    async def close(self):
        """Close all clients in the pool."""
        async with self._lock:
            for client in self._pool:
                try:
                    await client.close()
                except Exception as e:
                    logger.error(f"Error closing Firestore client: {e}")
            self._pool.clear()
            self._initialized = False
            logger.info("Firestore connection pool closed") 