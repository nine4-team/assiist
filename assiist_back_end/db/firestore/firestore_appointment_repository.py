from typing import List, Optional, Dict, Any
import uuid
from datetime import datetime

# Firestore Admin SDK
from firebase_admin import firestore
from google.cloud.firestore_v1 import AsyncClient, SERVER_TIMESTAMP
from google.cloud.firestore_v1.base_query import FieldFilter

# Core components
from assiist_back_end.db.repositories.interfaces.appointment_repository import AppointmentRepository
from assiist_back_end.models.appointment import Appointment

# Assume mappers exist in the same directory
from .mappers import firestore_to_appointment, appointment_to_firestore

class FirestoreAppointmentRepository(AppointmentRepository):
    """Firestore implementation for user-centric appointment/calendar event data operations."""

    COLLECTION_NAME = "appointments" # Store appointments directly under user

    def __init__(self, db: AsyncClient):
        self._db = db

    def _get_events_coll(self, user_id: str):
        """Helper to get the reference to a user's appointments subcollection."""
        # TODO: Validate/Sanitize user_id if necessary
        return self._db.collection('users').document(user_id).collection(self.COLLECTION_NAME)

    async def add(self, user_id: str, appointment: Appointment) -> Appointment:
        """Adds a new appointment using its generated UUID as the document ID."""
        if appointment.user_id != user_id:
             raise ValueError("User ID mismatch between context and appointment model.")
             
        coll_ref = self._get_events_coll(user_id)
        doc_ref = coll_ref.document(str(appointment.id)) # Use model's UUID

        # Map domain model to Firestore dictionary
        firestore_data = appointment_to_firestore(appointment)
        firestore_data.pop('id', None) # Remove ID, it's the doc key

        # Ensure timestamps are server-generated for internal tracking
        firestore_data['created_on'] = SERVER_TIMESTAMP 
        firestore_data['updated_on'] = SERVER_TIMESTAMP 
        # created_by/updated_by should be set on the model if needed

        await doc_ref.set(firestore_data)
        # Return the original object (lacks server timestamps)
        # Consider fetching again if timestamps are needed immediately
        return appointment 

    async def get_by_id(self, user_id: str, appointment_id: str) -> Optional[Appointment]:
        """Gets a specific appointment by its ID for a user."""
        coll_ref = self._get_events_coll(user_id)
        doc_ref = coll_ref.document(appointment_id)
        snapshot = await doc_ref.get()

        if not snapshot.exists:
            return None

        firestore_data = snapshot.to_dict()
        if firestore_data is None:
             return None 

        # Add document ID back before mapping
        firestore_data['id'] = snapshot.id
        return firestore_to_appointment(firestore_data)

    async def get_by_external_id(self, user_id: str, external_event_id: str) -> Optional[Appointment]:
        """Gets a specific appointment by its external provider ID for a user."""
        coll_ref = self._get_events_coll(user_id)
        query = coll_ref.where(filter=FieldFilter('external_id', '==', external_event_id)).limit(1)
        
        snapshot = None
        async for doc in query.stream(): # Iterate to get the first (and ideally only) doc
            snapshot = doc
            break # We only expect one, so break after the first

        if not snapshot or not snapshot.exists:
            return None

        firestore_data = snapshot.to_dict()
        if firestore_data is None:
            return None

        firestore_data['id'] = snapshot.id # Add Firestore document ID to the data
        return firestore_to_appointment(firestore_data)

    async def get_for_user(self, user_id: str, start_date: Optional[datetime] = None, end_date: Optional[datetime] = None) -> List[Appointment]:
        """Gets all appointments for a specific user, optionally filtered by date range."""
        coll_ref = self._get_events_coll(user_id)
        query = coll_ref # Start with base collection reference

        # Apply date filters - requires 'start_time' to be indexed in Firestore
        if start_date:
            query = query.where(filter=FieldFilter('start_time', '>=', start_date))
        if end_date:
             # Firestore range filters require ordering on the same field
             query = query.where(filter=FieldFilter('start_time', '<', end_date)).order_by("start_time", direction=firestore.Query.ASCENDING)
        else:
             # If only start_date or no dates, still need an order for consistency/pagination later
             query = query.order_by("start_time", direction=firestore.Query.ASCENDING)

        appointments = []
        async for snapshot in query.stream():
            if snapshot.exists:
                firestore_data = snapshot.to_dict()
                if firestore_data:
                    firestore_data['id'] = snapshot.id
                    appointment = firestore_to_appointment(firestore_data)
                    if appointment:
                        appointments.append(appointment)
        return appointments

    async def get_pending_contact_creation(self, user_id: str) -> List[Appointment]:
        """Gets appointments flagged as needing contact creation prompts for the user."""
        coll_ref = self._get_events_coll(user_id)
        # Requires 'needs_contact_creation_prompt' to be indexed if you have many events
        query = coll_ref.where(filter=FieldFilter('needs_contact_creation_prompt', '==', True)).order_by("start_time", direction=firestore.Query.ASCENDING) 

        appointments = []
        async for snapshot in query.stream():
            if snapshot.exists:
                firestore_data = snapshot.to_dict()
                if firestore_data:
                    firestore_data['id'] = snapshot.id
                    appointment = firestore_to_appointment(firestore_data)
                    if appointment:
                        appointments.append(appointment)
        return appointments

    async def update(self, user_id: str, appointment_id: str, update_data: Dict[str, Any]) -> Optional[Appointment]:
        """Updates an existing appointment for a user, raising specific errors."""
        coll_ref = self._get_events_coll(user_id)
        doc_ref = coll_ref.document(appointment_id)

        # Check existence first
        doc_snapshot = await doc_ref.get()
        if not doc_snapshot.exists:
            raise FileNotFoundError(f"Appointment {appointment_id} not found for user {user_id}")

        update_payload = update_data.copy()
        update_payload.pop('id', None)
        update_payload.pop('created_on', None) # This now correctly refers to the internal field if it was somehow in update_data
        update_payload.pop('updated_on', None) # Keep this in case old data has it.
        update_payload.pop('created_by', None)
        update_payload.pop('user_id', None)
        update_payload['updated_on'] = SERVER_TIMESTAMP # Set internal update timestamp

        try:
            # Perform the update (no transaction used here, add if needed)
            await doc_ref.update(update_payload)
            
            # Fetch and return the updated appointment
            updated_appointment = await self.get_by_id(user_id, appointment_id)
            if not updated_appointment: # Should exist after successful update, but check defensively
                 print(f"Warning: Could not fetch appointment {appointment_id} after update.")
                 raise Exception("Failed to fetch appointment after update")
            return updated_appointment
        except Exception as e:
             print(f"Error during appointment update commit for {appointment_id}: {e}")
             # Raise a more generic error or re-raise specific Firestore errors if identifiable
             raise Exception(f"Database update failed for appointment {appointment_id}: {e}")

    async def delete(self, user_id: str, appointment_id: str) -> bool:
        """Deletes an appointment for a user (hard delete), raising specific errors."""
        coll_ref = self._get_events_coll(user_id)
        doc_ref = coll_ref.document(appointment_id)

        # Check existence before delete to provide 404 feedback
        doc_snapshot = await doc_ref.get()
        if not doc_snapshot.exists:
            raise FileNotFoundError(f"Appointment {appointment_id} not found for user {user_id}")

        try:
            await doc_ref.delete()
            return True
        except Exception as e:
            print(f"Error deleting appointment {appointment_id} for user {user_id}: {e}")
            # Re-raise as a generic exception
            raise Exception(f"Database delete failed for appointment {appointment_id}: {e}")

    async def delete_by_external_id(self, user_id: str, connection_email: str, external_event_id: str) -> int:
        """Deletes an appointment by external ID and returns count of deleted appointments."""
        # First find the appointment by external ID
        appointment = await self.get_by_external_id(user_id, external_event_id)
        if not appointment:
            return 0  # No appointment found to delete
        
        # Delete using the found appointment's ID
        try:
            await self.delete(user_id, str(appointment.id))
            return 1  # Successfully deleted one appointment
        except Exception as e:
            print(f"Error deleting appointment by external ID {external_event_id} for user {user_id}: {e}")
            raise e

    # TODO: Implement batch/upsert methods if needed for sync efficiency 

    async def get_for_contact(self, user_id: str, contact_id: str) -> List[Appointment]:
        """Gets all appointments for a specific contact using array-contains."""
        coll_ref = self._get_events_coll(user_id)
        # Query where the 'assiist_contact_ids' array contains the contact_id
        # Note: Firestore expects the string version of the UUID for array_contains
        query = (
            coll_ref.where(filter=FieldFilter('assiist_contact_ids', 'array_contains', contact_id))
                    .order_by("start_time", direction=firestore.Query.ASCENDING)
        )

        appointments = []
        async for doc in query.stream():
            firestore_data = doc.to_dict()
            if firestore_data:
                firestore_data['id'] = doc.id # Add document ID
                appointment = firestore_to_appointment(firestore_data)
                if appointment:
                    appointments.append(appointment)
        return appointments 