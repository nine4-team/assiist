from typing import Dict, Optional
from google.cloud.firestore_v1 import AsyncClient, SERVER_TIMESTAMP

from assiist_back_end.db.repositories.interfaces.user_metrics_repository import UserMetricsRepository
from assiist_back_end.models.user_metrics import UserMetrics

class FirestoreUserMetricsRepository(UserMetricsRepository):
    """Firestore implementation for user metrics data operations."""

    def __init__(self, db: AsyncClient):
        self._db = db

    async def get_metrics_for_contact(self, user_id: str, contact_id: str) -> Optional[UserMetrics]:
        """Gets metrics for a specific contact, creating initial metrics if they don't exist."""
        doc_ref = self._db.collection('users').document(user_id).collection('metrics').document(contact_id)
        doc = await doc_ref.get()

        if not doc.exists:
            # Create initial metrics object, last_updated will be datetime.utcnow() from model's default_factory
            metrics_to_return = UserMetrics(
                user_id=user_id,
                contact_id=contact_id,
                messages_sent=0,
                notes_logged=0
                # last_updated will be set by Pydantic's default_factory
            )
            # Prepare data for Firestore, explicitly using SERVER_TIMESTAMP
            # Remove user_id since it's implicit in the document path
            data_for_firestore = metrics_to_return.model_dump()
            data_for_firestore['last_updated'] = SERVER_TIMESTAMP
            del data_for_firestore['user_id']  # user_id is implicit in the path

            await doc_ref.set(data_for_firestore)
            # Return the Pydantic-valid object (with datetime for last_updated)
            return metrics_to_return

        # Add user_id back to the data since it's needed for the UserMetrics model
        doc_data = doc.to_dict()
        doc_data['user_id'] = user_id
        return UserMetrics.model_validate(doc_data)

    async def increment_messages_sent(self, user_id: str, contact_id: str, idempotency_key: str) -> None:
        """
        Increments the messages sent counter for a contact, idempotently using the provided key.
        Uses a Firestore transaction to ensure atomicity and prevent lost updates under concurrency.
        Also ensures the idempotency key and counter update are written together.
        """
        doc_ref = self._db.collection('users').document(user_id).collection('metrics').document(contact_id)
        idempotency_ref = doc_ref.collection('idempotency_keys').document(idempotency_key)

        transaction = self._db.transaction()
        # Check if idempotency key exists (outside transaction for performance)
        idempotency_doc = await idempotency_ref.get()
        if idempotency_doc.exists:
            return

        # Mark this key as used and increment in transaction
        transaction.set(idempotency_ref, {'used': True, 'timestamp': SERVER_TIMESTAMP})
        doc = await doc_ref.get()
        if not doc.exists:
            initial_metrics = UserMetrics(
                user_id=user_id,
                contact_id=contact_id,
                messages_sent=1,
                notes_logged=0
            )
            data = initial_metrics.model_dump()
            data['last_updated'] = SERVER_TIMESTAMP
            del data['user_id']  # user_id is implicit in the path
            transaction.set(doc_ref, data)
        else:
            current_data = doc.to_dict()
            current_count = current_data.get('messages_sent', 0)
            transaction.update(doc_ref, {
                'messages_sent': current_count + 1,
                'last_updated': SERVER_TIMESTAMP
            })
        await transaction.commit()

    async def increment_notes_logged(self, user_id: str, contact_id: str) -> None:
        """
        Increments the notes logged counter for a contact.
        Uses a Firestore transaction to ensure atomicity and prevent lost updates under concurrency.
        """
        doc_ref = self._db.collection('users').document(user_id).collection('metrics').document(contact_id)
        transaction = self._db.transaction()
        doc = await doc_ref.get()
        if not doc.exists:
            initial_metrics = UserMetrics(
                user_id=user_id,
                contact_id=contact_id,
                messages_sent=0,
                notes_logged=1
            )
            data = initial_metrics.model_dump()
            data['last_updated'] = SERVER_TIMESTAMP
            del data['user_id']  # user_id is implicit in the path
            transaction.set(doc_ref, data)
        else:
            current_data = doc.to_dict()
            current_count = current_data.get('notes_logged', 0)
            transaction.update(doc_ref, {
                'notes_logged': current_count + 1,
                'last_updated': SERVER_TIMESTAMP
            })
        await transaction.commit()

    async def get_metrics_for_user(self, user_id: str) -> Dict[str, int]:
        """Gets total metrics across all contacts for a user."""
        query = self._db.collection('users').document(user_id).collection('metrics')
        snapshot = await query.get()

        total_messages = 0
        total_notes = 0

        for doc in snapshot:
            data = doc.to_dict()
            total_messages += data.get('messages_sent', 0)
            total_notes += data.get('notes_logged', 0)

        return {
            'messages_sent': total_messages,
            'notes_logged': total_notes,
        } 