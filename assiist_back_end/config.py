from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import SecretStr, Field
import os
from typing import Optional, List
# Remove Optional, List imports from typing if they were only added for the fix
# from typing import Optional, List

# Determine the project root directory (where the .env file should be)
# This assumes your script runs from somewhere within the project structure
# or that the CWD is the project root. Adjust if necessary.
# For Uvicorn running `assiist_back_end.src.main:app` from the root `app/` dir,
# the CWD should be correct.
# PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))) # src -> assiist_back_end -> app
# env_file_path = os.path.join(PROJECT_ROOT, '.env')

# Determine the environment based on an environment variable (e.g., APP_ENV)
# Default to 'development' if not set
APP_ENV = os.getenv("APP_ENV", "development")

# Construct an absolute path to the .env file
# This ensures the .env file is found reliably, regardless of the current working directory.
# __file__ is the path to the current config.py file.
# os.path.dirname(os.path.abspath(__file__)) is the directory containing config.py (i.e., assiist_back_end).
CONFIG_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_FILENAME = f".env.{APP_ENV}"
ENV_FILE_PATH_RESOLVED = os.path.join(CONFIG_DIR, ENV_FILENAME)

# --- Temporary Debugging Prints ---
# print(f"DEBUG: [config.py] APP_ENV from os.getenv: '{APP_ENV}'")
# print(f"DEBUG: [config.py] Attempting to load .env file from: '{ENV_FILE_PATH_RESOLVED}'")
# print(f"DEBUG: [config.py] Does .env file exist at that path? {os.path.exists(ENV_FILE_PATH_RESOLVED)}")
# --- End Temporary Debugging Prints ---

class Settings(BaseSettings):
    """
    Application settings loaded from environment variables or .env file.
    """
    # Default values can be provided, but it's often better to require them
    # via the environment or .env file.

    APP_ENV: str = "development"
    PROJECT_NAME: str = "Assiist Backend API"
    API_V1_STR: str = "/api/v1"
    API_URL: Optional[str] = None # To load from .env

    # Firebase Settings (using the standard environment variable)
    GOOGLE_APPLICATION_CREDENTIALS: str | None = None # Renamed from FIREBASE_SERVICE_ACCOUNT_KEY_PATH

    # CORS Settings
    BACKEND_CORS_ORIGINS: list[str] = ["http://localhost:3000", "http://localhost:8080", "http://localhost:5173", "app://localhost"]

    # Database settings
    FIRESTORE_DATABASE_ID: str = "assiist-app" # Explicitly define the database ID
    FIRESTORE_PROJECT_ID: str = "assiist-app" # Re-hardcode Project ID

    # Firebase Settings (Used for Admin SDK initialization if needed)
    FIREBASE_PROJECT_ID: str | None = None
    # Optional: Path to service account key for local dev, not recommended for prod
    # FIREBASE_SERVICE_ACCOUNT_KEY_PATH: Optional[str] = None

    # Internal API Key (for securing specific internal endpoints)
    # TODO: Replace with a strong, randomly generated secret key
    ASSIIST_API_KEY: SecretStr | None = None # RENAMED and made optional

    # --- NEW: Algolia Settings --- #
    ALGOLIA_APP_ID: str | None = None
    ALGOLIA_API_KEY: SecretStr | None = None # Use SecretStr for the API key
    ALGOLIA_INDEX_NAME: str | None = None # e.g., 'contacts' or 'contacts_dev'
    # --- END Algolia Settings --- #

    # --- AI API Keys --- #
    ANTHROPIC_API_KEY: SecretStr | None = None
    GEMINI_API_KEY: SecretStr | None = None
    
    # --- AI Model Configuration --- #
    ANTHROPIC_MODEL: str = "claude-sonnet-4-20250514"
    GEMINI_MODEL: str = "gemini-2.5-pro-preview-03-25"
    
    # --- Google OAuth Settings (for Calendar Sync & other Google APIs) --- #
    GOOGLE_CLIENT_ID: Optional[str] = None # Populated from .env
    GOOGLE_CLIENT_SECRET: Optional[SecretStr] = None # Populated from .env
    GOOGLE_TOKEN_URI: str = "https://oauth2.googleapis.com/token"
    GOOGLE_AUTH_URI: str = "https://accounts.google.com/o/oauth2/auth"
    # Example, adjust if you manage redirect URIs centrally in config
    # GOOGLE_REDIRECT_URIS: List[str] = ["http://localhost:8000/api/v1/auth/google/callback"]
    GOOGLE_CALENDAR_WEBHOOK_URL: Optional[str] = None # <<< ADDED: Full URL for Google to send notifications
    # --- END Google OAuth --- #



    # --- Google Calendar Sync Specific --- #
    GOOGLE_CALENDAR_SYNC_DAYS_PAST: int = 30 # Default: Sync events from the last 30 days
    GOOGLE_CALENDAR_SYNC_DAYS_FUTURE: int = 90 # Default: Sync events for the next 90 days
    GOOGLE_CHANNEL_RENEWAL_THRESHOLD_DAYS: int = 1 # Renew channel if it expires within this many days (e.g., 1 day)
    GOOGLE_CHANNEL_CHECK_INTERVAL_HOURS: int = 6 # How often the scheduled task runs the channel check
    GOOGLE_CALENDAR_PERIODIC_FULL_SYNC_DAYS: int = 7 # Perform a full resync every X days, 0 to disable
    # --- END Google Calendar Sync Specific --- #

    # --- NEW: Google Cloud Tasks Settings --- #
    GOOGLE_CLOUD_TASKS_PROJECT_ID: Optional[str] = None
    GOOGLE_CLOUD_TASKS_LOCATION: Optional[str] = None # e.g., "us-central1"
    GOOGLE_CLOUD_TASKS_QUEUE_ID: Optional[str] = None # The name of your Cloud Tasks queue
    GOOGLE_CLOUD_TASKS_HANDLER_SA_EMAIL: Optional[str] = None # Service account email for OIDC token to call the handler
    # --- END Google Cloud Tasks Settings --- #

    # --- NEW: Firebase Auth Clock Skew Settings ---
    FIREBASE_AUTH_CLOCK_SKEW_SECONDS: int = Field(default=30, description="Clock skew tolerance in seconds for Firebase ID token verification. Use non-zero only for local development if clock sync issues persist.")
    # --- END Firebase Auth Clock Skew Settings ---

    # --- NEW: Google Cloud Storage Settings (for file attachments) ---
    GOOGLE_CLOUD_STORAGE_BUCKET: str | None = None # Bucket name for file uploads
    MAX_ATTACHMENT_SIZE_MB: int = 10 # Maximum file size in MB
    # --- END Google Cloud Storage Settings ---

    # Configure Pydantic-Settings
    # Load environment variables from a .env file if it exists
    # The .env file should typically be in the project root directory
    # (the one containing assiist_back_end)
    model_config = SettingsConfigDict(
        env_file=ENV_FILE_PATH_RESOLVED, # Use the resolved absolute path
        env_file_encoding='utf-8',
        extra='ignore', # Ignore extra fields found in the environment/dotenv file
        case_sensitive=True # Allow loading variables directly from the environment as well
    )

# Instantiate settings once to be used across the application
settings = Settings() 

# Optional: Print loaded settings for verification (remove in production)
# print(f"Loading settings from: {ENV_FILE_PATH_RESOLVED}")
# print(settings.model_dump()) 