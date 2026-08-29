from functools import lru_cache
from dependency_injector.wiring import inject, Provide
from assiist_back_end.db.repositories.interfaces.reservation_repository import ReservationRepository
from assiist_back_end.db.firestore.firestore_reservation_repository import FirestoreReservationRepository
from assiist_back_end.containers import Container

@lru_cache()
@inject
def get_reservation_repository(
    firestore_client = Provide[Container.firestore_async_client]
) -> ReservationRepository:
    return FirestoreReservationRepository(firestore_client) 