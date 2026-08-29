import 'package:intl/intl.dart';
import 'package:assiist_front_end/core/models/task.dart';

/// A single place for all pre-filled note templates used across the app.
///
/// 1. Appointment-related templates (new / reschedule) – previously in
///    `appointment_note_templates.dart`.
/// 2. Task-related templates (completed / deleted).
/// 3. Message-draft templates (manual send / deleted draft).
///
/// The goal is to keep copy consistent and make future edits trivial.
class NoteTemplates {
  // ---------------------------------------------------------------------------
  // Appointment templates
  // ---------------------------------------------------------------------------
  static String newAppointment({
    required String appointmentTitle,
    required String email,
    DateTime? appointmentTime,
    String? appointmentNotes,
    String? appointmentId, // optional – placeholder filled by backend if null
  }) {
    final fmt = DateFormat('EEEE, MMM d, yyyy h:mm a');
    final sb =
        StringBuffer()
          ..writeln('This contact and I have an appointment together:')
          ..writeln('- Title: $appointmentTitle');

    if (appointmentTime != null) {
      sb.writeln('- Date & Time: ${fmt.format(appointmentTime.toLocal())}');
    }
    if (appointmentNotes != null && appointmentNotes.isNotEmpty) {
      sb.writeln('- Notes: $appointmentNotes');
    }

    sb
      ..writeln('- Email from Calendar Invite: $email')
      ..writeln()
      ..writeln('I need help with 2 things:')
      ..writeln(
        '1. I need to message the contact with a reminder 24 hours before the appointment.',
      )
      ..writeln(
        '2. I need to log my notes about the appointment 15 minutes after it starts using the following link:',
      )
      ..writeln();
    final idParam = appointmentId ?? '{appointment_id}';
    sb.writeln(
      'assiist://log-note?appointment_id=$idParam&contact_ids={contact_ids}&prefill_type=post_appointment',
    );

    sb
      ..writeln()
      ..writeln('Additional Notes (Add context below):');
    return sb.toString();
  }

  static String rescheduledAppointment({
    required String appointmentTitle,
    required String email,
    required DateTime originalTime,
    required DateTime newTime,
    String? reason,
    String? appointmentNotes,
    String? appointmentId,
  }) {
    final fmt = DateFormat('EEEE, MMM d, yyyy h:mm a');
    final sb =
        StringBuffer()
          ..writeln('Rescheduled Appointment Details:')
          ..writeln('- Original Time: ${fmt.format(originalTime.toLocal())}')
          ..writeln('- New Time: ${fmt.format(newTime.toLocal())}')
          ..writeln('- Title: $appointmentTitle');

    if (appointmentNotes != null && appointmentNotes.isNotEmpty) {
      sb.writeln('- Notes: $appointmentNotes');
    }
    sb.writeln('- Email from Calendar Invite: $email');
    if (reason != null && reason.isNotEmpty) {
      sb.writeln('- Reason: $reason');
    }

    sb
      ..writeln()
      ..writeln('Assistant Actions Required:')
      ..writeln('1. Update existing reminder message for new date')
      ..writeln(
        '2. Update existing reminder action task for new date that contains the link:',
      );

    final idParam = appointmentId ?? '{appointment_id}';
    sb.writeln(
      '   assiist://log-note?appointment_id=$idParam&contact_ids={contact_ids}&prefill_type=post_appointment',
    );

    sb
      ..writeln()
      ..writeln('Additional Notes (Add context below):');
    return sb.toString();
  }

  // Template for post-appointment note logging (called from deep links)
  static String postAppointmentTemplate({
    required String appointmentTitle,
    required DateTime startTime,
    required DateTime endTime,
    String? appointmentDescription,
  }) {
    final fmt = DateFormat('EEEE, MMM d, yyyy h:mm a');
    final timezone = startTime.timeZoneName;

    final sb =
        StringBuffer()
          ..writeln('Here are my notes for the following appointment:')
          ..writeln()
          ..writeln('Title:        $appointmentTitle')
          ..writeln(
            'Date / Time:  ${fmt.format(startTime.toLocal())} – ${DateFormat('h:mm a').format(endTime.toLocal())} ($timezone)',
          )
          ..writeln(
            'Description:  ${appointmentDescription?.isNotEmpty == true ? appointmentDescription : "(none)"}',
          )
          ..writeln()
          ..writeln('Notes:')
          ..writeln();

    return sb.toString();
  }

  // ---------------------------------------------------------------------------
  // Task templates
  // ---------------------------------------------------------------------------
  static String completedTask(Task task) {
    return 'I\'ve just completed the following task:\n\n'
        'Task Title: ${task.title}\n'
        '${_maybeBodyLine(task)}'
        '\nHere\'s some more context about how it went and what the outcome was. '
        'Please use this to determine the best next steps (e.g., drafting a message, creating follow-up tasks, etc.):\n\n'
        'Outcome & Additional Context:\n';
  }

  static String deletedTask(Task task) {
    return 'I\'ve just deleted the following task:\n\n'
        'Task Title: ${task.title}\n'
        '${_maybeBodyLine(task)}'
        '\nHere\'s some more context.  Please use it to determine if any other actions are needed (e.g., cleaning up related tasks, etc.):\n\n'
        'Additional Context (Optional):\n';
  }

  // ---------------------------------------------------------------------------
  // Message-draft templates (message tasks)
  // ---------------------------------------------------------------------------
  static String manualSendMessage(Task messageDraftTask) {
    return 'I\'ve just manually sent the following message:\n\n'
        'Title: ${messageDraftTask.title}\n'
        'Body:\n${messageDraftTask.body ?? "(No message body)"}\n\n'
        'This message was sent via the SMS app. Please use this information to determine any appropriate next steps.';
  }

  static String deletedMessageDraft(Task messageDraftTask) {
    return 'I\'ve just deleted the following message draft:\n\n'
        'Title: ${messageDraftTask.title}\n'
        'Body:\n${messageDraftTask.body ?? "(No message body)"}\n\n'
        'Here\'s some more context.  Please use it to determine if any other actions are needed (e.g., cleaning up related tasks, etc.):\n\n'
        'Additional Context (Optional):\n';
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  static String _maybeBodyLine(Task task) {
    if (task.body != null && task.body!.isNotEmpty) {
      return 'Task Body: ${task.body}\n';
    }
    return '';
  }
}
