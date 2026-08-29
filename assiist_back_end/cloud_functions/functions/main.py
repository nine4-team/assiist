# main.py - Entry point for Firebase Cloud Functions
# This file imports all the decorated functions so Firebase can discover them

# Import GenAI functions
from genai.revise_draft import revise_message_draft
from genai.get_quick_draft import get_quick_draft  
from genai.get_processed_note import get_processed_note
from genai.update_context import update_context
from genai.update_tasks import update_tasks
from genai.extract_call_insights import extract_call_insights
from genai.transcribe_audio import transcribe_audio

# Import notification functions (if they exist)
try:
    from notifications.task_notifications import *
    from notifications.send_notification import *
except ImportError:
    pass

# Import appointment functions (if they exist)  
try:
    from appointments.detect_reschedule import *
except ImportError:
    pass

# All functions are now available for Firebase deployment
# The @https_fn.on_request and other decorators in the imported modules
# register the functions with Firebase automatically 