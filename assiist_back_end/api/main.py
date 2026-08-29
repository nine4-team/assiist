from dotenv import load_dotenv
import os # Import os earlier for path manipulation
import logging # Add this line

# Determine the path to .env.development relative to this file (main.py)
# Assuming main.py is in assiist_back_end/api/ and .env.development is in assiist_back_end/
# So, one level up from api directory, then into .env.development
_main_py_dir = os.path.dirname(os.path.abspath(__file__))
_env_path = os.path.join(os.path.dirname(_main_py_dir), ".env.development")

if os.path.exists(_env_path):
    print(f"Loading environment variables from: {_env_path}")
    load_dotenv(dotenv_path=_env_path, override=True)
else:
    print(f"Warning: .env.development file not found at expected path: {_env_path}. Attempting default .env load.")
    load_dotenv(override=True) # Try default .env if specific one not found, or rely on system env vars

# Configure logging level for google_calendar_service
logging.basicConfig(level=logging.INFO)  # Set root logger to INFO
logging.getLogger('assiist_back_end.services.google_calendar_service').setLevel(logging.INFO) # Add this line

import firebase_admin # Keep import for now maybe?
from fastapi import FastAPI, Depends, Request, Response
from fastapi.staticfiles import StaticFiles
from starlette.middleware.base import BaseHTTPMiddleware
from fastapi.responses import JSONResponse
from dependency_injector.wiring import inject, Provide
# os already imported
from fastapi.middleware.cors import CORSMiddleware
from firebase_admin import credentials, firestore_async # Ensure firestore_async is imported
import json
from typing import Callable
# from dependency_injector import providers # No longer needed for override

# ADDED: UTF-8 Response Middleware
class UTF8ResponseMiddleware(BaseHTTPMiddleware):
    """
    Middleware to ensure all responses are properly encoded as UTF-8.
    This solves encoding issues for external services consuming the API.
    """
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        response = await call_next(request)
        
        # Ensure Content-Type header includes charset=utf-8 for JSON responses
        content_type = response.headers.get("content-type", "")
        
        if content_type.startswith("application/json") and "charset" not in content_type:
            response.headers["content-type"] = "application/json; charset=utf-8"
        elif content_type.startswith("text/") and "charset" not in content_type:
            response.headers["content-type"] = f"{content_type}; charset=utf-8"
            
        return response

# ADDED: Custom JSON Response class that ensures UTF-8 encoding
class UTF8JSONResponse(JSONResponse):
    """
    Custom JSONResponse that ensures proper UTF-8 encoding.
    Use this for any custom JSON responses to guarantee UTF-8 encoding.
    """
    def __init__(self, content, **kwargs):
        # Ensure UTF-8 media type
        if 'media_type' not in kwargs:
            kwargs['media_type'] = 'application/json; charset=utf-8'
        elif 'charset' not in kwargs['media_type']:
            kwargs['media_type'] = f"{kwargs['media_type']}; charset=utf-8"
        
        super().__init__(content, **kwargs)

# Assuming your container is defined in src.containers
from assiist_back_end.containers import Container
# Assume this service initializes Firebase Admin if needed
# from .core.services.firebase_service import FirebaseService # REMOVED

# Remove individual endpoint imports that are part of api_v1_router
# from .api.v1.endpoints import contacts # Now in api_v1_router
# from .api.v1.endpoints import appointments # Now in api_v1_router
# from .api.v1.endpoints import notes # Now in api_v1_router
# Import routers from the tasks module correctly - These are also in api_v1_router
# from .api.v1.endpoints.tasks import (
#     contact_tasks_router, 
#     tasks_router
# )
# Import the new internal routers
# from .api.v1.endpoints import internal_users # Now in api_v1_router
from .endpoints.v1 import accounts  # Updated import for consolidated accounts
from .endpoints.v1 import users  # Updated import for consolidated users
# --- ADD Import for contact_appointments_router --- 
# from .api.v1.endpoints.appointments import contact_appointments_router # Now in api_v1_router

# Import the main v1 router
from .endpoints.v1.api import api_v1_router
# Import the new Google webhook router
from .endpoints.v1 import google_webhook
# Import the new Google Cloud Task Handlers router
from assiist_back_end.api.endpoints.v1 import google_cloud_task_handlers

# Import the dependencies module itself for wiring
from .endpoints.v1 import dependencies

# Import specific endpoint modules needed for wiring
from .endpoints.v1 import contacts, appointments, notes, tasks, genai, feedback

# Import the admin portal router
from assiist_back_end.admin.routes import admin_router, api_router as admin_api_router

# Import other routers if you have them (e.g., users)

# --- Firebase Initialization ---
def initialize_firebase():
    cred_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
    project_id = os.getenv("FIREBASE_PROJECT_ID", "assiist-app") # Get project ID from env, default to assiist-app
    app_env = os.getenv("APP_ENV", "development").lower()

    # For production/Cloud Run, use Application Default Credentials
    if app_env == "production" and not cred_path:
        print("Production environment detected. Using Application Default Credentials (service account).")
        try:
            app = firebase_admin.initialize_app(options={
                'projectId': project_id,
            })
            print(f"Firebase Admin SDK Initialized successfully using Application Default Credentials for project: {project_id}")
            return app
        except ValueError as e_val:
            if "already initialized" in str(e_val).lower():
                print(f"Firebase Admin SDK already initialized for project {project_id}. Using existing app.")
                return firebase_admin.get_app()
            else:
                print(f"ValueError initializing Firebase Admin SDK: {e_val}")
                raise SystemExit(f"Firebase initialization failed due to ValueError: {e_val}")
        except Exception as e_other:
            print(f"Unexpected error initializing Firebase Admin SDK: {e_other}")
            raise SystemExit(f"Firebase initialization failed: {e_other}")

    # For development or when credentials file is explicitly provided
    if not cred_path:
        print("FATAL: GOOGLE_APPLICATION_CREDENTIALS environment variable not set. Cannot initialize Firebase.")
        raise SystemExit("Firebase initialization failed: GOOGLE_APPLICATION_CREDENTIALS not set.")

    if not os.path.exists(cred_path):
        print(f"FATAL: Service account key file not found at path specified by GOOGLE_APPLICATION_CREDENTIALS: {cred_path}")
        raise SystemExit(f"Firebase initialization failed: Credentials file not found at {cred_path}")

    try:
        cred = credentials.Certificate(cred_path)
        app = firebase_admin.initialize_app(cred, {
            'projectId': project_id,
        })
        print(f"Firebase Admin SDK Initialized successfully using service account: {cred_path} for project: {project_id}")
        return app
    except ValueError as e_val:
        if "already initialized" in str(e_val).lower():
            print(f"Firebase Admin SDK already initialized for project {project_id}. Using existing app.")
            return firebase_admin.get_app()
        else:
            print(f"ValueError initializing Firebase Admin SDK: {e_val}")
            raise SystemExit(f"Firebase initialization failed due to ValueError: {e_val}")
    except Exception as e_other:
        print(f"Unexpected error initializing Firebase Admin SDK: {e_other}")
        raise SystemExit(f"Firebase initialization failed: {e_other}")

# Initialize Firebase and get the default app instance
default_app = initialize_firebase()

if default_app:
    print(f"Firebase Admin SDK Project ID (from default_app after init function): {default_app.project_id}")
else:
    # This should not be reached if initialize_firebase() raises SystemExit on failure
    print("CRITICAL: Firebase default_app is None after initialization attempt and SystemExit was not raised. This should not happen.")
    raise SystemExit("Firebase initialization resulted in no app instance.")

# --- Dependency Injection Setup ---
def create_container() -> Container:
    """Creates the DI container."""
    container = Container()
    return container

# --- FastAPI Application Setup --- 
def create_app(container: Container) -> FastAPI:
    app = FastAPI(
        title="Assiist Backend API",
        description="API for AssistAI backend services.",
        version="0.1.0",
        default_response_class=UTF8JSONResponse,  # RE-ENABLED: Now that cloud functions use proper UTF-8
    )
    # --- CORS Middleware --- 
    def get_cors_origins():
        """Get CORS origins from environment and base origins."""
        base_origins = [
            "http://localhost",
            "http://localhost:8080", 
            "http://localhost:3000",
        ]
        
        # Add API_URL origin if it exists (for development tunneling)
        api_url = os.getenv("API_URL")
        if api_url:
            # Extract origin from API_URL (remove /api/v1 suffix if present)
            api_origin = api_url.replace("/api/v1", "").rstrip("/")
            if api_origin not in base_origins:
                base_origins.append(api_origin)
                
        return base_origins
    
    origins = get_cors_origins()
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    
    # ADDED: UTF-8 Response Middleware (add after CORS)
    app.add_middleware(UTF8ResponseMiddleware)  # RE-ENABLED: Now that cloud functions use proper UTF-8
    # --- Mount Static Files ---
    # Mount admin portal static files
    app.mount("/admin/static", StaticFiles(directory="assiist_back_end/admin/static"), name="admin_static")
    
    # --- Include routers --- 
    # Remove individual router inclusions handled by api_v1_router
    # app.include_router(contacts.router, prefix="/api/v1/contacts", tags=["Contacts"])
    # app.include_router(appointments.router, prefix="/api/v1", tags=["Appointments"])
    # app.include_router(contact_appointments_router, prefix="/api/v1", tags=["Appointments"])
    # app.include_router(notes.router, prefix="/api/v1")
    # Include the task routers - handled by api_v1_router
    # app.include_router(contact_tasks_router, prefix="/api/v1", tags=["Tasks"])
    # app.include_router(tasks_router, prefix="/api/v1", tags=["Tasks"])

    # Include the main v1 router - prefixes are handled within api.py and endpoint files
    app.include_router(api_v1_router)
    
    # Include the files router at root level for short URLs
    from assiist_back_end.api.endpoints.v1 import files
    app.include_router(files.router, prefix="/f", tags=["Files"]) 

    # Include the Google Calendar webhook router
    app.include_router(
        google_webhook.router, 
        prefix="/api/v1/webhooks/google/calendar", # Define the prefix for this router
        tags=["Google Calendar Webhook"]
    )

    # Keep routers not included in api_v1_router if necessary
    # app.include_router(accounts.router, prefix="/api/v1/accounts", tags=["Accounts"]) # REMOVED as it's in api_v1_router
    app.include_router(accounts.internal_router, prefix="/api/v1", tags=["Accounts"])
    # app.include_router(users.router, prefix="/api/v1/users", tags=["Users"]) # REMOVED as it's in api_v1_router
    app.include_router(users.internal_router, prefix="/api/v1", tags=["Users"])

    # Include the Google Cloud Task Handlers router
    app.include_router(google_cloud_task_handlers.router)
    
    # GenAI router now consolidated into api_v1_router following implementation guide

    # Include the Admin Portal routers
    app.include_router(admin_router)
    app.include_router(admin_api_router)

    @app.get("/health", tags=["Health"])
    async def health_check():
        return {"status": "ok"}

    @app.get("/", tags=["Root"])
    async def read_root():
        # Access APP_ENV safely AFTER it's defined
        app_env = os.getenv("APP_ENV", "production").lower()
        return {"message": f"Welcome to AssistAI API ({app_env} mode)"}

    return app

# --- Create Instances & Wire ---
# Create the DI container instance
container = create_container()

# REMOVE the Firestore client provider override
# print(f"Overriding container.firestore_async_client...")
# container.firestore_async_client.override(providers.Object(db_client))

# Wire the container
print(f"Wiring the container modules...")
container.wire(modules=[
    __name__,
    # Use module references for wiring - corrected to new structure
    'assiist_back_end.api.endpoints.v1.contacts',
    'assiist_back_end.api.endpoints.v1.appointments',
    'assiist_back_end.api.endpoints.v1.notes',
    'assiist_back_end.api.endpoints.v1.tasks',
    'assiist_back_end.api.endpoints.v1.debug',
    'assiist_back_end.api.endpoints.v1.metrics',
    'assiist_back_end.api.endpoints.v1.text_message_examples',
    'assiist_back_end.api.endpoints.v1.accounts',  # Updated to use consolidated accounts
    'assiist_back_end.api.endpoints.v1.users',     # Updated to use consolidated users
    'assiist_back_end.api.endpoints.v1.dependencies',
    'assiist_back_end.api.endpoints.v1.genai',
    'assiist_back_end.api.endpoints.v1.google_webhook',
    'assiist_back_end.api.endpoints.v1.oauth_google',
    'assiist_back_end.api.endpoints.v1.reservations',  # NEW: Wire reservations
    'assiist_back_end.api.endpoints.v1.notifications',  # NEW: Wire notifications
    'assiist_back_end.api.endpoints.v1.assistant',  # NEW: Wire consolidated assistant endpoints
    'assiist_back_end.api.endpoints.v1.files',  # NEW: Wire files for short URL redirection
    'assiist_back_end.api.endpoints.v1.feedback',  # NEW: Wire feedback endpoints
    'assiist_back_end.api.endpoints.v1.transcription',  # NEW: Wire transcription endpoints for call recording feature
])
print(f"Container wiring complete.")

# Create the FastAPI app instance, passing the container
app = create_app(container)

# --- Environment Configuration ---
APP_ENV = os.getenv("APP_ENV", "production").lower()
print(f"INFO:     FastAPI application configured for {APP_ENV} environment.")

# === Add logging after Firebase init ===
# try:
#     # Ensure we are checking the default app
#     app_check = firebase_admin.get_app()
#     print(f"DEBUG: Firebase Admin App Project ID: {app_check.project_id}")
# except Exception as e:
#     print(f"DEBUG: Could not get Firebase Admin App details: {e}")
# === REMOVE End Add logging === 