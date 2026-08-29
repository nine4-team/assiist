import pytest
from datetime import datetime, timedelta
import uuid
from pydantic import ValidationError

from models.revision import RevisionEntry, RevisionHistory

def test_revision_entry_validation():
    """Test that RevisionEntry validation works correctly."""
    # Valid entry
    entry = RevisionEntry(
        revision_instructions="Make it more formal",
        revised_message="Hello, I would like to schedule an appointment."
    )
    assert entry.revised_message == "Hello, I would like to schedule an appointment."
    
    # Empty message should fail
    with pytest.raises(ValidationError):
        RevisionEntry(
            revision_instructions="Make it more formal",
            revised_message=""
        )
        
    # None message should fail
    with pytest.raises(ValidationError):
        RevisionEntry(
            revision_instructions="Make it more formal",
            revised_message=None
        )

def test_revision_history_validation():
    """Test that RevisionHistory validation works correctly."""
    # Valid history
    history = RevisionHistory(
        task_id=uuid.uuid4(),
        original_message="Hey, can we meet up?"
    )
    assert history.original_message == "Hey, can we meet up?"
    assert history.revisions == []
    assert history.is_finalized == False
    assert history.finalized_on is None
    
    # Empty original message should fail
    with pytest.raises(ValidationError):
        RevisionHistory(
            task_id=uuid.uuid4(),
            original_message=""
        )
        
def test_add_revision_to_history():
    """Test adding a revision to the history."""
    # Create history
    history = RevisionHistory(
        task_id=uuid.uuid4(),
        original_message="Hey, can we meet up?"
    )
    
    # Create revision
    revision = RevisionEntry(
        revision_instructions="Make it more formal",
        revised_message="Hello, I would like to meet with you."
    )
    
    # Add revision to history
    history.revisions.append(revision)
    
    # Verify revision was added
    assert len(history.revisions) == 1
    assert history.revisions[0].revision_instructions == "Make it more formal"
    assert history.revisions[0].revised_message == "Hello, I would like to meet with you."
    
def test_finalize_history():
    """Test finalizing a revision history."""
    # Create history
    history = RevisionHistory(
        task_id=uuid.uuid4(),
        original_message="Hey, can we meet up?"
    )
    
    # Finalize history
    history.is_finalized = True
    history.finalized_on = datetime.utcnow()
    
    # Verify history was finalized
    assert history.is_finalized == True
    assert history.finalized_on is not None 