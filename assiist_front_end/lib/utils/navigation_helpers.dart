import 'package:flutter/cupertino.dart';
import 'package:assiist_front_end/screens/log_note_screen.dart';
import 'package:assiist_front_end/core/models/contact.dart';
import 'package:assiist_front_end/core/models/task.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:assiist_front_end/core/templates/note_templates.dart'; // renamed generic templates

class NavigationHelpers {
  static Future<T?> navigateToLogNoteScreen<T extends Object?>(
    BuildContext context, {
    Contact? initialContact,
    String? potentialContactEmail,
    String? appointmentTitle,
    String? appointmentNotes,
    DateTime? appointmentTime,
    String? completedTaskNotes,
    bool? isRescheduled,
    DateTime? originalAppointmentTime,
    String? rescheduleReason,
    // Add other LogNoteScreen params if any in the future
  }) {
    return Navigator.of(context).push<T>(
      CupertinoPageRoute(
        builder:
            (context) => LogNoteScreen(
              initialContact: initialContact,
              potentialContactEmail: potentialContactEmail,
              appointmentTitle: appointmentTitle,
              appointmentNotes: appointmentNotes,
              appointmentTime: appointmentTime,
              completedTaskNotes: completedTaskNotes,
              isRescheduled: isRescheduled ?? false,
              originalAppointmentTime: originalAppointmentTime,
              rescheduleReason: rescheduleReason,
            ),
      ),
    );
  }

  static String buildCompletedTaskNotes(Task task) {
    return NoteTemplates.completedTask(task);
  }

  static String buildNewAppointmentNotes(
    String appointmentTitle,
    String email, {
    DateTime? appointmentTime,
    String? appointmentNotes,
    String?
    appointmentId, // Forwarded to template so deep link can be filled when available
  }) {
    return NoteTemplates.newAppointment(
      appointmentTitle: appointmentTitle,
      email: email,
      appointmentTime: appointmentTime,
      appointmentNotes: appointmentNotes,
      appointmentId: appointmentId,
    );
  }

  static String buildRescheduledAppointmentNotes(
    String appointmentTitle,
    String email,
    DateTime originalTime,
    DateTime newTime,
    String? reason,
    String? appointmentNotes, {
    String? appointmentId,
  }) {
    return NoteTemplates.rescheduledAppointment(
      appointmentTitle: appointmentTitle,
      email: email,
      originalTime: originalTime,
      newTime: newTime,
      reason: reason,
      appointmentNotes: appointmentNotes,
      appointmentId: appointmentId,
    );
  }

  static Future<void> navigateToLogNoteForCompletedTask(
    BuildContext context,
    Task completedTask,
  ) {
    return navigateToLogNoteScreen<void>(
      context,
      initialContact: completedTask.contact,
      completedTaskNotes: buildCompletedTaskNotes(completedTask),
    );
  }

  static Contact? createMinimalContactFromTask(Task task) {
    if (task.contactId == null) return null;

    return Contact(
      id: task.contactId!,
      first_name: task.contactDisplayName?.split(' ').first,
      last_name:
          task.contactDisplayName != null &&
                  task.contactDisplayName!.contains(' ')
              ? task.contactDisplayName!.substring(
                task.contactDisplayName!.indexOf(' ') + 1,
              )
              : null,
      is_deleted: false,
    );
  }
}
