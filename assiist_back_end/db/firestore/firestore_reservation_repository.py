from datetime import datetime
from typing import List, Optional, Dict, Any
from google.cloud.firestore_v1 import AsyncClient, SERVER_TIMESTAMP
from google.cloud.firestore_v1.base_query import FieldFilter
from assiist_back_end.db.repositories.interfaces.reservation_repository import ReservationRepository
from assiist_back_end.models.reservation import Reservation

class FirestoreReservationRepository(ReservationRepository):
    def __init__(self, db: AsyncClient):
        self._db = db
        self._collection = db.collection('reservations')

    async def create(self, reservation: Reservation) -> Reservation:
        doc_ref = self._collection.document(reservation.id)
        data = reservation.model_dump(exclude={'id'})
        data['created_on'] = SERVER_TIMESTAMP
        data['updated_on'] = SERVER_TIMESTAMP
        await doc_ref.set(data)
        return reservation

    async def get_by_id(self, reservation_id: str) -> Optional[Reservation]:
        doc_ref = self._collection.document(reservation_id)
        doc = await doc_ref.get()
        if not doc.exists:
            return None
        data = doc.to_dict()
        data['id'] = doc.id
        return Reservation(**data)

    async def get_by_account(self, account_id: str, filters: Dict[str, Any] = None) -> List[Reservation]:
        query = self._collection.where(filter=FieldFilter('account_id', '==', account_id))
        
        if filters:
            if 'user_id' in filters:
                query = query.where(filter=FieldFilter('user_id', '==', filters['user_id']))
            if 'contact_id' in filters:
                query = query.where(filter=FieldFilter('contact_id', '==', filters['contact_id']))

        docs = await query.get()
        reservations = []
        for doc in docs:
            data = doc.to_dict()
            data['id'] = doc.id
            reservations.append(Reservation(**data))
        return reservations

    async def update(self, reservation_id: str, update_data: Dict[str, Any]) -> Reservation:
        doc_ref = self._collection.document(reservation_id)
        doc = await doc_ref.get()
        if not doc.exists:
            return None
        
        # Add server timestamp for updated_on
        update_data['updated_on'] = SERVER_TIMESTAMP
        
        # Update the document
        await doc_ref.update(update_data)
        
        # Get the updated document
        updated_doc = await doc_ref.get()
        data = updated_doc.to_dict()
        data['id'] = updated_doc.id
        return Reservation(**data)

    async def delete(self, reservation_id: str) -> bool:
        doc_ref = self._collection.document(reservation_id)
        doc = await doc_ref.get()
        if not doc.exists:
            return False
        await doc_ref.delete()
        return True

    async def exists(self, contact_id: str, account_id: str) -> bool:
        query = self._collection.where(filter=FieldFilter('contact_id', '==', contact_id)).where(filter=FieldFilter('account_id', '==', account_id))
        docs = await query.limit(1).get()
        return len(docs) > 0 