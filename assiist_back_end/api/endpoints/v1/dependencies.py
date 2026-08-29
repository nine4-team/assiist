from fastapi import Depends, HTTPException, status, Header, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from dataclasses import dataclass
import firebase_admin
from firebase_admin import auth, firestore_async
from firebase_admin.auth import InvalidIdTokenError, ExpiredIdTokenError
from google.cloud.firestore_v1.async_client import AsyncClient # Import AsyncClient
import secrets
import logging
import time # For timing calculations
from typing import Optional

# --- ADDED: Setup logger if not already configured elsewhere ---
# (Consider moving to a central logging configuration if you have one)
logger = logging.getLogger(__name__)
# Basic configuration if no handlers are present
if not logger.handlers:
    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    logger.setLevel(logging.INFO) # Or DEBUG for more verbosity
# --- END ADDED ---

# Define the UserContext (can be shared or redefined here)
@dataclass
class UserContext:
    """Minimal user context passed through request cycle."""
    user_id: str
    account_id: str
    timezone: str = "UTC"

# Define the Bearer scheme for extracting the token
bearer_scheme = HTTPBearer()

# Ensure Firebase Admin is initialized (assuming it's done in main.py or similar entry point)
# If not already initialized, this will raise an error, which is intended.

# --- Add dependency injection imports ---
from dependency_injector.wiring import inject, Provide, Provider
from assiist_back_end.containers import Container # ADJUSTED PATH to absolute
from assiist_back_end.config import Settings # ADJUSTED PATH to absolute
from assiist_back_end.db.repositories.interfaces.contact_repository import ContactRepository # ADJUSTED PATH to absolute
import uuid # Add this import
from assiist_back_end.models.contact import Contact # ADJUSTED PATH to absolute

# --- Add Internal API Key Verification Dependency ---

# Note: Define ASSIIST_API_KEY in your Settings/Configuration source (e.g., .env)

# --- Cache for UserContext ---
_user_context_cache = {} # Token hash -> (UserContext, timestamp)
_USER_CONTEXT_CACHE_TTL_SECONDS = 5 # Cache UserContext for 5 seconds
# --- End Cache --- 

@inject
async def verify_internal_secret(
    request: Request, # Use Request object to access headers
    settings: Settings = Depends(Provide[Container.config]) # Inject settings
) -> bool:
    """
    Verifies a secret key provided in the 'X-Internal-API-Key' header
    against the configured ASSIIST_API_KEY.
    Used to protect internal-only endpoints.
    """
    provided_key = request.headers.get("X-Internal-API-Key") # Or your chosen header name

    # Check if the setting itself exists and has a value
    if not settings.ASSIIST_API_KEY or not settings.ASSIIST_API_KEY.get_secret_value():
        logger.error("FATAL: ASSIIST_API_KEY is not configured in settings.")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal API Key security is not configured on the server."
        )

    expected_key = settings.ASSIIST_API_KEY.get_secret_value()

    if not provided_key:
        logger.warning("Missing X-Internal-API-Key header in request.")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing internal API key header."
        )

    # Use a constant-time comparison to mitigate timing attacks
    is_valid = secrets.compare_digest(provided_key, expected_key)

    if not is_valid:
        logger.warning("Invalid internal API key provided.")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect internal API key."
        )

    # logger.debug("Internal API Key verified.") # Optional: Debug logging
    return True

# --- ADDED: Dependency to get the application settings instance --- 
@inject
def get_settings(
    # This will inject the actual Settings instance provided by Container.config
    settings_instance: Settings = Depends(Provide[Container.config]) 
) -> Settings:
    """FastAPI dependency to provide the application settings instance."""
    return settings_instance # Return the already resolved Settings instance
# --- END ADDED ---

# --- ADDED: Dependency to get the Firestore async client instance --- 
@inject
async def get_firestore_async_client(
    client: AsyncClient = Depends(Provide[Container.firestore_async_client]),
) -> AsyncClient:
    """FastAPI dependency to provide the Firestore async client instance."""
    return client
# --- END ADDED ---

# Modify verify_firebase_token to inject the client
@inject
async def verify_firebase_token(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: AsyncClient = Depends(Provide[Container.firestore_async_client]),
    settings: Settings = Depends(Provide[Container.config]) # Inject Settings
) -> UserContext:
    # start_time_dependency = time.monotonic() # Start timer for the whole dependency

    if credentials.scheme != "Bearer":
        logger.warning("Invalid authentication scheme. Expected Bearer.") # ADDED: Logger
        print('DEBUG: 403 - Invalid authentication scheme', flush=True)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid authentication scheme.",
            headers={"WWW-Authenticate": "Bearer"},
        )
        
    token = credentials.credentials
    uid = None # Initialize uid
    
    try:
        # --- Firebase ID Token Verification --- 
        decoded_token = firebase_admin.auth.verify_id_token(
            token,
            clock_skew_seconds=settings.FIREBASE_AUTH_CLOCK_SKEW_SECONDS
        )
        uid = decoded_token['uid']
        # --- End Firebase ID Token Verification ---

        # --- Cache Check ---
        # Use a combination of token and uid for cache key to handle token refresh scenarios correctly, though token itself is better.
        # However, if tokens are very short-lived and frequently refreshed, uid might be more stable for a short cache.
        # For simplicity with a short TTL, uid might be sufficient. Let's use token for better cache specificity.
        # Using a hash of the token as the key as tokens can be long.
        token_hash = hash(token)
        if token_hash in _user_context_cache:
            cached_user_context, timestamp = _user_context_cache[token_hash]
            if time.monotonic() - timestamp < _USER_CONTEXT_CACHE_TTL_SECONDS:
                # Ensure the UID from the current token matches the cached context's UID
                if cached_user_context.user_id == uid: # uid is now populated from decoded_token
                    # dependency_duration = time.monotonic() - start_time_dependency
                    # logger.info(f"UserContext (cached) for UID: {uid}. Total time in dependency: {dependency_duration:.4f} seconds.")
                    return cached_user_context
                else:
                    logger.warning(f"Cache hit for token hash but UID mismatch. Current UID: {uid}, Cached UID: {cached_user_context.user_id}. Invalidating cache entry.")
                    del _user_context_cache[token_hash] # Stale/bad entry

        # --- Cache Miss or Expired: Fetch user profile from Firestore ---
        user_ref = db.collection("users").document(uid) 
        
        # start_firestore_lookup_time = time.monotonic()
        user_doc = await user_ref.get()
        # end_firestore_lookup_time = time.monotonic()
        # logger.info(f"Firestore user lookup for UID: {uid} took {end_firestore_lookup_time - start_firestore_lookup_time:.4f} seconds.")

        if not user_doc.exists:
             logger.error(f"Firestore user document not found for UID: {uid}") # ADDED
             print('DEBUG: 404 - User profile not found', flush=True)
             raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, 
                detail="User profile not found.",
                headers={"WWW-Authenticate": "Bearer"},
            )

        user_data = user_doc.to_dict()
        account_id = user_data.get("account_id")

        if not account_id:
            logger.error(f"account_id not found in Firestore user document for UID: {uid}") # ADDED
            print('DEBUG: 403 - User account configuration error', flush=True)
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, 
                detail="User account configuration error.", 
                headers={"WWW-Authenticate": "Bearer"},
            )
        
        timezone_pref = user_data.get("timezone", "UTC")
        user_context = UserContext(user_id=uid, account_id=account_id, timezone=timezone_pref)
        # Store in cache
        _user_context_cache[token_hash] = (user_context, time.monotonic())

        # dependency_duration = time.monotonic() - start_time_dependency
        # logger.info(f"UserContext creation for UID: {uid} successful. Total time in dependency: {dependency_duration:.4f} seconds.")
        return user_context

    except (InvalidIdTokenError, ExpiredIdTokenError) as e:
        # dependency_duration = time.monotonic() - start_time_dependency
        logger.error(f"Token verification failed for UID: {uid if uid else 'unknown'}. Error: {e}.")
        # logger.error(f"Token verification failed for UID: {uid if uid else 'unknown'}. Error: {e}. Total time in dependency: {dependency_duration:.4f} seconds.")
        print('DEBUG: 403 - Invalid or expired token', flush=True)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid or expired token: {e}",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except HTTPException as e: # Re-raise HTTP exceptions from profile lookup
        # dependency_duration = time.monotonic() - start_time_dependency
        logger.warning(f"HTTPException during auth for UID: {uid if uid else 'unknown'}. Detail: {e.detail}.")
        # logger.warning(f"HTTPException during auth for UID: {uid if uid else 'unknown'}. Detail: {e.detail}. Total time in dependency: {dependency_duration:.4f} seconds.")
        print(f'DEBUG: HTTPException during auth: {e.detail}', flush=True)
        raise e
    except Exception as e:
        # dependency_duration = time.monotonic() - start_time_dependency
        logger.critical(f"Unexpected error during token verification/user lookup for UID: {uid if uid else 'unknown'}. Error: {e}.", exc_info=True)
        # logger.critical(f"Unexpected error during token verification/user lookup for UID: {uid if uid else 'unknown'}. Error: {e}. Total time in dependency: {dependency_duration:.4f} seconds.", exc_info=True)
        print(f'DEBUG: 500 - Internal server error during authentication: {e}', flush=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Internal server error during authentication: {e}",
            headers={"WWW-Authenticate": "Bearer"},
        )

# --- Helper Dependency for Contact Verification ---
# Moved from notes.py/tasks.py
@inject
async def verify_contact_ownership(
    contact_id: uuid.UUID, # Use UUID directly if path param is UUID
    user_ctx: UserContext = Depends(verify_firebase_token),
    contact_repo: ContactRepository = Depends(Provide[Container.contact_repository])
) -> Contact: # Return the contact object upon success
    """Verifies the current user's account owns the contact and returns the contact."""
    # start_time_contact_ownership = time.monotonic()
    # logger.info(f"Verifying ownership for contact_id: {contact_id}, account_id: {user_ctx.account_id}")
    contact = await contact_repo.get_contact_by_id(
        account_id=user_ctx.account_id, 
        contact_id=str(contact_id) # Repository expects string ID
    )
    if not contact:
        logger.warning(f"Contact {contact_id} not found for account {user_ctx.account_id}") # MODIFIED
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Contact not found")
    
    # This check might be redundant if get_contact_by_id already filters by account_id,
    # but it's a good safeguard.
    if contact.account_id != user_ctx.account_id:
         logger.warning(f"Contact {contact_id} account {contact.account_id} mismatch for user account {user_ctx.account_id}") # MODIFIED
         raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="User does not have access to this contact")
         
    # end_time_contact_ownership = time.monotonic()
    # logger.info(f"Ownership verified for contact {contact_id}. Took {end_time_contact_ownership - start_time_contact_ownership:.4f} seconds (excluding auth token verification).")
    return contact # Return contact if needed by endpoint
# --- End Helper ---