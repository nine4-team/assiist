# Assiist

Assiist is an AI follow-up assistant for relationship-based service businesses. It
turns appointment notes and contact history into specific follow-up tasks and
editable message drafts, while keeping the business owner in control of what is
sent.

This repository is a reviewer-facing snapshot of the application implementation.
Live environment configuration, production data, and internal operational archives
are intentionally excluded.

## Product workflow

1. Sync contacts and calendar appointments.
2. Capture notes, recordings, and attachments after an interaction.
3. Extract useful relationship context from those inputs.
4. Generate structured follow-up tasks and message drafts.
5. Let the user revise, approve, and complete each action.

The product also handles pending contacts, calendar reconciliation, push
notifications, draft revision, feedback collection, and account administration.

## Architecture

The Flutter client uses Firebase Authentication and communicates with a Python
backend. The backend separates API routes, service orchestration, domain models,
and Firestore repositories. Generative-AI providers sit behind service boundaries so
prompting and validation are not coupled to the mobile interface.

```text
Flutter client
      ↓
authenticated FastAPI endpoints
      ↓
application services and AI generation
      ↓
Firestore repositories, calendar APIs, storage, and notifications
```

The codebase includes both the main FastAPI service and focused Firebase Cloud
Functions for event-driven work such as notifications and AI-generation jobs.

## Repository guide

- `assiist_front_end/` — Flutter application, providers, screens, repositories, and services
- `assiist_back_end/api/` — FastAPI routes, request schemas, and authentication boundaries
- `assiist_back_end/services/` — application orchestration and external integrations
- `assiist_back_end/db/` — repository interfaces and Firestore implementations
- `assiist_back_end/cloud_functions/` — Firebase rules and event-driven functions
- `assiist_back_end/testing/` — focused backend tests retained in the public snapshot

## Local setup

### Backend

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r assiist_back_end/requirements.txt
cp assiist_back_end/.env.development.example assiist_back_end/.env.development
uvicorn assiist_back_end.api.main:app --reload
```

Populate only the integrations you plan to exercise. Secrets belong in the local
environment or a managed secret store, never in source control.

### Flutter client

```bash
cd assiist_front_end
cp .env.development.example .env.development
flutter pub get
flutterfire configure
flutter run
```

`flutterfire configure` creates the platform-specific Firebase files omitted from
this public snapshot. A Firebase development project and provider credentials are
required for end-to-end execution.

## Verification

The repository can be checked without production credentials at the source level:

```bash
python3 -m compileall -q assiist_back_end
cd assiist_front_end && flutter pub get
```

End-to-end calendar, notification, contact-sync, and message-generation checks
require configured development services.

## Security and privacy

The application handles contact history, calendar details, message drafts, and OAuth
tokens. The public repository therefore omits live Firebase configuration, API keys,
production records, and internal debugging exports. Backend credentials are loaded
through environment variables and secret stores; mobile access remains subject to
Firebase authentication and server-side authorization.
