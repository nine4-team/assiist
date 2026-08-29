from dependency_injector import containers, providers
# Import the specific Async Client from google-cloud-firestore
from google.cloud.firestore_v1.async_client import AsyncClient as GoogleAsyncClient
from google.oauth2 import service_account # For explicit credentials loading
# Keep firebase_admin imports for initialization
import firebase_admin
from firebase_admin import credentials
# from firebase_admin import firestore_async # No longer needed for client instantiation
import logging # ADDED

from assiist_back_end.config import Settings # Import Settings from config - NOW ABSOLUTE

# Import your repository interface and implementation
# Adjust paths if your structure differs
from .db.repositories.interfaces.contact_repository import ContactRepository
from .db.repositories.interfaces.appointment_repository import AppointmentRepository # New
from .db.repositories.interfaces.note_repository import NoteRepository # New
from .db.repositories.interfaces.task_repository import TaskRepository # New
# Import GenAI Request Repository Interface
from .db.repositories.interfaces.generation_request_repository import GenAIRequestRepository
# Import Settings Repository
# from .core.repositories.settings_repository import SettingsRepository
from .db.repositories.interfaces.pending_contact_repository import PendingContactRepository # <<< ADD Import
from .db.repositories.interfaces.text_message_example_repository import TextMessageExampleRepository
from .db.repositories.interfaces.account_repository import AccountRepository # ADDED
from .db.repositories.interfaces.reservation_repository import ReservationRepository # ADDED
from .db.repositories.interfaces.notification_repository import NotificationRepository # NEW: Notification repo interface
from .db.repositories.interfaces.user_repository import UserRepository # NEW: User repository interface
from .db.repositories.interfaces.attachment_repository import AttachmentRepository # NEW: Attachment repository interface
from .db.repositories.interfaces.feedback_repository import FeedbackRepository # NEW: Feedback repository interface
from .db.repositories.interfaces.audio_transcription_repository import AudioTranscriptionRepository

# Data Layer - Implementations (Update this import)
# from core.repositories.firestore_contact_repository import FirestoreContactRepository # Old path
from .db.firestore.firestore_contact_repository import FirestoreContactRepository # New path
from .db.firestore.firestore_appointment_repository import FirestoreAppointmentRepository # New
from .db.firestore.firestore_note_repository import FirestoreNoteRepository # New
from .db.firestore.firestore_task_repository import FirestoreTaskRepository # New
# Import Firestore GenAI Request Repository Implementation
from .db.firestore.firestore_generation_request_repository import GenAIRequestRepository
# Import Firestore implementation for Pending Contacts
from .db.firestore.firestore_pending_contact_repository import FirestorePendingContactRepository # <<< ADD Import
# Import the Firestore implementation for UserMetrics
from .db.firestore.firestore_user_metrics_repository import FirestoreUserMetricsRepository
from .db.firestore.firestore_text_message_example_repository import FirestoreTextMessageExampleRepository
from .db.firestore.firestore_account_repository import FirestoreAccountRepository # ADDED
from .db.firestore.firestore_revision_repository import FirestoreRevisionHistoryRepository
from .db.firestore.firestore_reservation_repository import FirestoreReservationRepository # ADDED
from .db.firestore.firestore_notification_repository import FirestoreNotificationRepository # NEW: Notification repo implementation
from .db.firestore.firestore_user_repository import FirestoreUserRepository # NEW: User repository implementation
from .db.firestore.attachment_repository import FirestoreAttachmentRepository # NEW: Attachment repository implementation
from .db.firestore.firestore_feedback_repository import FirestoreFeedbackRepository # NEW: Feedback repository implementation
from .db.firestore.firestore_audio_transcription_repository import FirestoreAudioTranscriptionRepository

# Import configuration loading if needed
# from core.config import Settings

# REMOVE Infrastructure Layer - Firebase Admin SDK import for firestore_async
# from firebase_admin import firestore_async

# --- CORRECT Algolia Import --- #
# Correct Algolia import path (v4 SDK)
from algoliasearch.search_client import SearchClient
# from algoliasearch.search_client_async import SearchClientAsync # Incorrect for v4

# Import the service
from .services.google_calendar_service import (
    get_valid_google_credentials,
    create_google_watch,
    stop_google_watch,
    perform_initial_sync,
    perform_incremental_sync,
    handle_webhook_notification
    # If GoogleCalendarService becomes a class, import the class itself
)
from .services.notification_service import NotificationService # NEW: Notification service

# Import assistant service
from .services.assistant_service import AssistantService
from .services.genai_service import GenAIUtilities
from .services.attachment_service import AttachmentService # NEW: Attachment service

# Import Google Cloud Storage
from google.cloud import storage

logger = logging.getLogger(__name__) # ADDED

class Container(containers.DeclarativeContainer):

    # Configuration
    config = providers.Singleton(Settings)

    # --- Helper function for conditional credentials ---
    def _get_firebase_credential(config):
        """Get Firebase credential - use file if available, otherwise Application Default"""
        creds_path = config.GOOGLE_APPLICATION_CREDENTIALS
        if creds_path:
            return credentials.Certificate(creds_path)
        else:
            return credentials.ApplicationDefault()
    
    def _get_google_credentials(config):
        """Get Google credentials - use file if available, otherwise None for Application Default"""
        creds_path = config.GOOGLE_APPLICATION_CREDENTIALS  
        if creds_path:
            return service_account.Credentials.from_service_account_file(creds_path)
        else:
            return None  # Let GoogleAsyncClient use Application Default Credentials

    # --- Firebase Initialization (Still needed for auth, etc.) --- #
    firebase_app = providers.Singleton(
        firebase_admin.initialize_app,
        credential=providers.Factory(
            _get_firebase_credential,
            config=config,
        ),
        name='assiist-backend-default'
    )

    # --- Direct Google Cloud Firestore Async Client Initialization --- # 
    
    # Provider for Google Credentials - conditional based on environment
    google_credentials = providers.Factory(
        _get_google_credentials,
        config=config,
    )

    # Provider for the Firestore Async Client using google-cloud-firestore
    firestore_async_client = providers.Singleton(
        GoogleAsyncClient,
        project=config.provided.FIRESTORE_PROJECT_ID,
        database=config.provided.FIRESTORE_DATABASE_ID,
        credentials=google_credentials,
    )

    # --- CORRECTED Algolia Client Initialization --- #
    # Create Algolia client with resolved config values (avoid passing bound methods)
    algolia_search_client = providers.Singleton(
        lambda settings: SearchClient.create(
            settings.ALGOLIA_APP_ID,
            settings.ALGOLIA_API_KEY.get_secret_value().strip(),
        ),
        config,
    )

    # Repository Providers
    # These will now correctly receive the client instance from the factory.
    contact_repository = providers.Factory(
        FirestoreContactRepository,
        firestore_async_client=firestore_async_client,
        settings=config,
        algolia_client=algolia_search_client,
    )

    appointment_repository = providers.Factory(
        FirestoreAppointmentRepository,
        db=firestore_async_client, # Match constructor param name
    )
    
    note_repository = providers.Factory(
        FirestoreNoteRepository,
        db=firestore_async_client, # Inject Firestore client
    )

    task_repository = providers.Factory(
        FirestoreTaskRepository,
        db=firestore_async_client, # Inject Firestore client
    )

    # GenAI Request Repository Provider
    genai_request_repository = providers.Factory(
        GenAIRequestRepository,
        db=firestore_async_client
    )



    # Add PendingContact Repository Provider
    pending_contact_repository = providers.Factory(
        FirestorePendingContactRepository,
        db=firestore_async_client
    ) # <<< ADD Provider

    # Add UserMetrics Repository Provider
    user_metrics_repository = providers.Factory(
        FirestoreUserMetricsRepository,
        db=firestore_async_client
    )

    # Add TextMessageExample Repository Provider
    text_message_example_repository = providers.Factory(
        FirestoreTextMessageExampleRepository,
        db=firestore_async_client
    )

    # ADDED: Account Repository Provider
    account_repository = providers.Factory(
        FirestoreAccountRepository,
        db=firestore_async_client # Inject Firestore client
    )

    # Add revision repository
    revision_history_repository = providers.Factory(
        FirestoreRevisionHistoryRepository,
        db=firestore_async_client
    )

    # ADDED: Reservation Repository Provider
    reservation_repository = providers.Factory(
        FirestoreReservationRepository,
        db=firestore_async_client
    )

    # ADDED: Notification Repository Provider
    notification_repository = providers.Factory(
        FirestoreNotificationRepository,
        db=firestore_async_client
    )

    # ADDED: User Repository Provider
    user_repository = providers.Factory(
        FirestoreUserRepository,
        db=firestore_async_client
    )

    # ADDED: Attachment Repository Provider
    attachment_repository = providers.Factory(
        FirestoreAttachmentRepository,
        db=firestore_async_client
    )

    # ADDED: Feedback Repository Provider
    feedback_repository = providers.Factory(
        FirestoreFeedbackRepository,
        db=firestore_async_client
    )

    # ADDED: Audio Transcription Repository Provider
    audio_transcription_repository = providers.Factory(
        FirestoreAudioTranscriptionRepository,
        db=firestore_async_client,
    )

    # Google Cloud Storage Client
    storage_client = providers.Singleton(
        storage.Client,
        credentials=google_credentials,
        project=config.provided.FIRESTORE_PROJECT_ID
    )

    # Service Providers
    notification_service = providers.Factory(
        NotificationService,
        notification_repo=notification_repository,
        user_repo=user_repository
    )

    # ADDED: Attachment Service Provider
    attachment_service = providers.Factory(
        AttachmentService,
        storage_client=storage_client,
        bucket_name=config.provided.GOOGLE_CLOUD_STORAGE_BUCKET,
        attachment_repo=attachment_repository,
        base_url=config.provided.API_URL
    )

    # Update Assistant Service Providers
    genai_utilities = providers.Factory(
        GenAIUtilities,
        db=firestore_async_client
    )

    # Assistant Service (formerly update_assistant_service) - handles ALL AI operations
    assistant_service = providers.Factory(
        AssistantService,
        db=firestore_async_client,
        task_repo=task_repository,
        contact_repo=contact_repository,
        note_repo=note_repository,
        genai_request_repo=genai_request_repository,  # NEW: Single unified repository
        revision_repo=revision_history_repository,  # EXISTING - for actual revision history
        genai_utils=genai_utilities,  # NEW: Inject GenAI utilities for context retrieval
        audio_transcription_repo=audio_transcription_repository,  # Inject audio transcription repository
        base_url=config.provided.API_URL  # Use environment variable for API URL
    )

# ... potentially other container configurations ... 