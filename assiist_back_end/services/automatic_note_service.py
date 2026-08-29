from __future__ import annotations

import asyncio
import logging
import uuid
from datetime import datetime
from typing import Dict, List, Any

from assiist_back_end.containers import Container
from assiist_back_end.services.assistant_service import AssistantService
from google.cloud.firestore_v1.async_client import AsyncClient
from assiist_back_end.services import appointment_note_templates as ant

logger = logging.getLogger(__name__)

class AutomaticNoteService:
    """Utility class for generating and processing system notes through the Update Assistant flow."""

    def __init__(self):
        """Instantiate service with async Firestore client from the IoC container."""
        container = Container()
        self.db: AsyncClient = container.firestore_async_client()
        self.assistant_service: AssistantService = container.assistant_service()

    # ---------------------------------------------------------------------
    # PUBLIC API
    # ---------------------------------------------------------------------
    async def process_new_appointment_notes(self, user_id: str, appointment_data: Dict[str, Any]):
        """Generate notes for a *new* appointment linked to one or more contacts."""
        await self._process_notes_for_contacts(
            user_id=user_id,
            appointment_data=appointment_data,
            template=ant.NEW_APPOINTMENT_TEMPLATE,
        )

    async def process_reschedule_notes(self, user_id: str, appointment_data: Dict[str, Any]):
        """Generate notes for a *rescheduled* appointment linked to one or more contacts."""
        await self._process_notes_for_contacts(
            user_id=user_id,
            appointment_data=appointment_data,
            template=ant.RESCHEDULE_TEMPLATE,
            is_reschedule=True,
        )

    async def process_cancellation_notes(self, user_id: str, appointment_data: Dict[str, Any]):
        """Generate notes for a *cancelled* appointment linked to one or more contacts."""
        await self._process_notes_for_contacts(
            user_id=user_id,
            appointment_data=appointment_data,
            template=ant.CANCELLATION_TEMPLATE,
        )

    # ------------------------------------------------------------------
    # INTERNAL HELPERS
    # ------------------------------------------------------------------
    async def _process_notes_for_contacts(
        self,
        user_id: str,
        appointment_data: Dict[str, Any],
        template: str,
        is_reschedule: bool = False,
    ):
        contact_ids: List[str] = [
            str(cid) if not isinstance(cid, str) else cid for cid in appointment_data.get("assiist_contact_ids", [])
        ]

        if not contact_ids:
            logger.info(
                "AutomaticNoteService → No linked contacts found for appointment %s (user %s). Skipping auto-note.",
                appointment_data.get("id"),
                user_id,
            )
            return

        # Attempt to fetch account_id once (all contacts under same account)
        account_id = await self._get_account_id(user_id)

        # Build placeholders
        title = appointment_data.get("title", "(No title)")
        start_time = appointment_data.get("start_time")
        if isinstance(start_time, str):
            # Expect ISO string
            try:
                start_time = datetime.fromisoformat(start_time)
            except ValueError:
                start_time = None
        start_time_str = start_time.isoformat() if isinstance(start_time, datetime) else str(start_time)

        # For reschedules
        original_time_str = None
        if is_reschedule:
            original_time = appointment_data.get("original_start_time")
            if isinstance(original_time, str):
                try:
                    original_time = datetime.fromisoformat(original_time)
                except ValueError:
                    original_time = None
            original_time_str = original_time.isoformat() if isinstance(original_time, datetime) else str(original_time)

        reschedule_reason = appointment_data.get("reschedule_reason")
        reason_block = f"Reason: {reschedule_reason}" if reschedule_reason else ""

        # ------------------------------------------------------------------
        # Iterate contacts
        # ------------------------------------------------------------------
        for contact_id in contact_ids:
            if is_reschedule:
                note_body = ant.build_reschedule_note(appointment_data, [contact_id])
            else:
                note_body = ant.build_new_appointment_note(appointment_data, [contact_id])

            # Build Update Assistant request
            request_payload = {
                "user_id": user_id,
                "contact_id": contact_id,
                "account_id": account_id,
                "note_content": note_body,
                "context": {
                    "appointment_id": appointment_data.get("id"),
                    "source_event_id": appointment_data.get("external_id"),
                },
                # Generate request IDs for the operations we will actually trigger
                "task_request_id": str(uuid.uuid4()),
                "context_request_id": str(uuid.uuid4()),
                # We are deliberately skipping note processing for system notes
                "note_type": "system",
                "skip_note_processing": True,
            }

            try:
                await self.assistant_service.process_update_assistant_request(request_payload)
                logger.info(
                    "AutomaticNoteService → Submitted Update Assistant request for contact %s (appointment %s)",
                    contact_id,
                    appointment_data.get("id"),
                )
            except Exception as exc:
                logger.error(
                    "AutomaticNoteService ❌ Failed to submit Update Assistant request for contact %s: %s",
                    contact_id,
                    exc,
                )

    async def _get_account_id(self, user_id: str) -> str | None:
        """Fetch the account_id for a given user ID."""
        try:
            user_ref = self.db.collection("users").document(user_id)
            user_snapshot = await user_ref.get()
            if not user_snapshot.exists:
                return None
            user_data = user_snapshot.to_dict()
            return user_data.get("account_id")
        except Exception as exc:
            logger.error("AutomaticNoteService ❌ Failed to fetch account_id for user %s: %s", user_id, exc)
            return None 