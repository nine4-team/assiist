from abc import ABC, abstractmethod
from typing import List, Optional
import uuid
from assiist_back_end.models.text_message_example import TextMessageExample

class TextMessageExampleRepository(ABC):
    """Interface for data operations related to TextMessageExamples."""

    @abstractmethod
    async def add(self, user_id: str, example: TextMessageExample) -> TextMessageExample:
        pass

    @abstractmethod
    async def get_for_user(self, user_id: str) -> List[TextMessageExample]:
        pass

    @abstractmethod
    async def get_by_id(self, user_id: str, example_id: str) -> Optional[TextMessageExample]:
        pass

    @abstractmethod
    async def update(self, user_id: str, example_id: str, update_data: dict) -> Optional[TextMessageExample]:
        pass

    @abstractmethod
    async def delete(self, user_id: str, example_id: str) -> bool:
        pass 