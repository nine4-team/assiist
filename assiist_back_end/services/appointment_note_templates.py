from datetime import datetime
from typing import List

NEW_APPOINTMENT_TEMPLATE = (
    "This contact and I have an appointment together:\n"
    "- Title: {title}\n"
    "- Date & Time: {start_time}\n"
    "- Contact: {{contact_name}}\n"
    "- Location: {location}\n\n"
    "I need help with 2 things:\n"
    "1. I need to message the contact with a reminder 24 hours before the appointment.\n"
    "2. I need to log my notes about the appointment 15 minutes after it starts (using the following link:\n\n"
    "assiist://log-note?appointment_id={appointment_id}&contact_ids={contact_ids}&prefill_type=post_appointment\n\n"
    "Additional Notes (Add context below):\n"
)

RESCHEDULE_TEMPLATE = (
    "Rescheduled Appointment Details:\n"
    "- Original Time: {original_time}\n"
    "- New Time: {start_time}\n"
    "- Title: {title}\n"
    "- Contact: {{contact_name}}\n"
    "- Location: {location}\n\n"
    "Assistant Actions Required:\n"
    "1. Update existing reminder message for new date\n"
    "2. Update existing reminder action task for new date that contains the link:\n\n"
    "   assiist://log-note?appointment_id={appointment_id}&contact_ids={contact_ids}&prefill_type=post_appointment\n\n"
    "Additional Notes (Add context below):\n"
)

CANCELLATION_TEMPLATE = (
    "The following appointment was cancelled:\n\n"
    "Title: {title}\n"
    "Description: {description}\n"
    "Time: {start_time}\n\n"
    "I need help with:\n"
    "1. Close or update any open tasks related to this appointment.\n"
)

UPDATE_TEMPLATE = (
    "I need to update you on some appointment details that changed:\n\n"
    "Appointment Title: {title}\n"
    "Time: {start_time}\n"
    "Previous Location: {old_location}\n"
    "New Location: {location}\n"
    "Previous Description: {old_description}\n"
    "New Description: {description}\n"
    "Contact: {{contact_name}}\n\n"
    "I need help with:\n"
    "1. Review existing tasks/reminders and update if location or context changes affect them.\n"
)

# ---------------------------------------------------------------------------
# Builder helpers
# ---------------------------------------------------------------------------

def _get(attr_obj, key, default=None):
    if isinstance(attr_obj, dict):
        return attr_obj.get(key, default)
    return getattr(attr_obj, key, default)


def _csv(contact_ids: List[str]) -> str:
    return ",".join(contact_ids)


def build_new_appointment_note(appointment, contact_ids: List[str]):
    title = _get(appointment, "title", "(No title)")
    start_time = _get(appointment, "start_time")
    location = _get(appointment, "location", "(unspecified)")
    start_str = start_time.isoformat() if isinstance(start_time, (str,)) else str(start_time) if start_time else "(unknown)"
    app_id = _get(appointment, "id", "unknown")

    return NEW_APPOINTMENT_TEMPLATE.format(
        title=title,
        start_time=start_str,
        appointment_id=app_id,
        contact_ids=_csv(contact_ids),
        location=location,
    )


def build_reschedule_note(appointment, contact_ids: List[str]):
    title = _get(appointment, "title", "(No title)")
    start_time = _get(appointment, "start_time")
    location = _get(appointment, "location", "(unspecified)")
    start_str = start_time.isoformat() if hasattr(start_time, "isoformat") else str(start_time) if start_time else "(unknown)"
    orig_time = _get(appointment, "original_start_time")
    orig_str = orig_time.isoformat() if hasattr(orig_time, "isoformat") else str(orig_time) if orig_time else "(unknown)"
    app_id = _get(appointment, "id", "unknown")
    reason_block = f"Reason: {_get(appointment, 'reschedule_reason')}\n" if _get(appointment, 'reschedule_reason') else ""

    return RESCHEDULE_TEMPLATE.format(
        title=title,
        original_time=orig_str,
        start_time=start_str,
        appointment_id=app_id,
        contact_ids=_csv(contact_ids),
        location=location,
        reason_block=reason_block,
    )


def build_cancellation_note(appointment, contact_ids: List[str]):
    title = _get(appointment, "title", "(No title)")
    start_time = _get(appointment, "start_time")
    location = _get(appointment, "location", "(unspecified)")
    start_str = start_time.isoformat() if hasattr(start_time, "isoformat") else str(start_time) if start_time else "(unknown)"
    description = _get(appointment, "description", "(none)")

    return CANCELLATION_TEMPLATE.format(
        title=title,
        description=description,
        start_time=start_str,
        location=location,
    )


# ------------------ NEW: update note ---------------------
def build_update_note(appointment, old_appointment, contact_ids: List[str]):
    title = _get(appointment, "title", "(No title)")
    start_time = _get(appointment, "start_time")
    start_str = start_time.isoformat() if hasattr(start_time, "isoformat") else str(start_time)
    location = _get(appointment, "location", "(unspecified)")
    old_location = _get(old_appointment, "location", "(unspecified)")
    description = _get(appointment, "description", "(none)")
    old_description = _get(old_appointment, "description", "(none)")

    return UPDATE_TEMPLATE.format(
        title=title,
        start_time=start_str,
        location=location,
        old_location=old_location,
        description=description,
        old_description=old_description,
    ) 