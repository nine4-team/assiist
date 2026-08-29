import 'package:cloud_firestore/cloud_firestore.dart'; // For Timestamp

class PendingContact {
  final String id;
  final String? userId; // User this pending contact belongs to
  final String?
  displayName; // Name to display, might be email if name not available
  final String? email;
  final String? phone;
  final String? sourceEventId; // From which event this was generated
  final String? sourceEventTitle; // ADDED: Title of the source event
  final DateTime? appointmentTime; // ADDED: Current appointment time
  final String? appointmentNotes; // ADDED: Description/notes of the event
  final String status; // e.g., "pending", "created_contact", "ignored"
  final DateTime? createdOn; // ← FIXED: Use *_on suffix instead of createdAt

  // Reschedule related fields
  final bool isRescheduled; // Whether this is from a rescheduled appointment
  final DateTime? originalAppointmentTime; // Original time before reschedule
  final String? rescheduleReason; // Reason for reschedule if available

  PendingContact({
    required this.id,
    this.userId,
    this.displayName,
    this.email,
    this.phone,
    this.sourceEventId,
    this.sourceEventTitle, // ADDED
    this.appointmentTime, // ADDED
    this.appointmentNotes, // ADDED
    required this.status,
    this.createdOn, // ← FIXED: Use *_on suffix
    this.isRescheduled = false,
    this.originalAppointmentTime,
    this.rescheduleReason,
  });

  factory PendingContact.fromJson(Map<String, dynamic> json) {
    return PendingContact(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      displayName: json['display_name'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      sourceEventId: json['source_event_id'] as String?,
      sourceEventTitle: json['source_event_title'] as String?, // ADDED
      appointmentTime:
          json['appointment_time'] != null
              ? (json['appointment_time'] is Timestamp)
                  ? (json['appointment_time'] as Timestamp).toDate()
                  : _parseIsoDateTime(json['appointment_time'])
              : null,
      appointmentNotes: json['appointment_notes'] as String?, // ADDED
      status:
          json['status'] as String? ??
          'pending', // Default to 'pending' if null
      createdOn: // ← FIXED: Use *_on suffix
          json['created_on'] != null
              ? (json['created_on'] is Timestamp
                  ? (json['created_on'] as Timestamp).toDate()
                  : DateTime.tryParse(json['created_on'] as String))
              : null,
      isRescheduled: json['is_rescheduled'] as bool? ?? false,
      originalAppointmentTime:
          json['original_appointment_time'] != null
              ? (json['original_appointment_time'] is Timestamp
                  ? (json['original_appointment_time'] as Timestamp).toDate()
                  : DateTime.tryParse(
                    json['original_appointment_time'] as String,
                  ))
              : null,
      rescheduleReason: json['reschedule_reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'display_name': displayName,
      'email': email,
      'phone': phone,
      'source_event_id': sourceEventId,
      'source_event_title': sourceEventTitle,
      'appointment_time': appointmentTime?.toIso8601String(),
      'appointment_notes': appointmentNotes,
      'status': status,
      'is_rescheduled': isRescheduled,
      'original_appointment_time': originalAppointmentTime?.toIso8601String(),
      'reschedule_reason': rescheduleReason,
    };
  }

  // Helper to parse ISO8601 strings in a tolerant way
  static DateTime? _parseIsoDateTime(dynamic value) {
    if (value == null) return null;
    try {
      if (value is String) {
        return DateTime.parse(value);
      }
    } catch (_) {
      // ignore and fall through
    }
    return null;
  }
}
