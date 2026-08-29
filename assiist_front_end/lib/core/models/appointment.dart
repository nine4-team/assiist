import 'package:cloud_firestore/cloud_firestore.dart'; // For Timestamp

// Basic Appointment Model - Add fields as needed based on API response
class Appointment {
  final String id;
  final String userId;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime? endTime;
  final String? location;
  final List<String>? assiistContactIds; // List of contact IDs associated

  // Reschedule tracking fields
  final bool isRescheduled;
  final DateTime? originalStartTime;
  final DateTime? originalEndTime;
  final String? rescheduleReason;
  final int rescheduleCount;

  Appointment({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    required this.startTime,
    this.endTime,
    this.location,
    this.assiistContactIds,
    this.isRescheduled = false,
    this.originalStartTime,
    this.originalEndTime,
    this.rescheduleReason,
    this.rescheduleCount = 0,
  });

  // Helper function to safely convert dynamic data to DateTime
  static DateTime? _dynamicToDateTime(dynamic timestamp) {
    if (timestamp == null) return null;
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    } else if (timestamp is String) {
      return DateTime.tryParse(timestamp)?.toLocal();
    } else if (timestamp is int) {
      // Assume milliseconds since epoch if it's an int
      return DateTime.fromMillisecondsSinceEpoch(
        timestamp,
        isUtc: true,
      ).toLocal();
    }
    print("Warning: Could not parse DateTime from backend: $timestamp");
    return null;
  }

  factory Appointment.fromJson(Map<String, dynamic> json, String id) {
    return Appointment(
      id: id,
      userId: json['user_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled Appointment',
      description: json['description'] as String?,
      startTime: _dynamicToDateTime(json['start_time']) ?? DateTime.now(),
      endTime: _dynamicToDateTime(json['end_time']),
      location: json['location'] as String?,
      assiistContactIds:
          (json['assiist_contact_ids'] as List<dynamic>?)
              ?.map((e) => e.toString()) // Ensure IDs are strings
              .toList(),
      isRescheduled: json['is_rescheduled'] as bool? ?? false,
      originalStartTime: _dynamicToDateTime(json['original_start_time']),
      originalEndTime: _dynamicToDateTime(json['original_end_time']),
      rescheduleReason: json['reschedule_reason'] as String?,
      rescheduleCount: json['reschedule_count'] as int? ?? 0,
    );
  }

  // copyWith method to create a new instance with updated fields
  Appointment copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    DateTime? startTime,
    DateTime? endTime,
    String? location,
    List<String>? assiistContactIds,
    bool? isRescheduled,
    DateTime? originalStartTime,
    DateTime? originalEndTime,
    String? rescheduleReason,
    int? rescheduleCount,
  }) {
    return Appointment(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      location: location ?? this.location,
      assiistContactIds: assiistContactIds ?? this.assiistContactIds,
      isRescheduled: isRescheduled ?? this.isRescheduled,
      originalStartTime: originalStartTime ?? this.originalStartTime,
      originalEndTime: originalEndTime ?? this.originalEndTime,
      rescheduleReason: rescheduleReason ?? this.rescheduleReason,
      rescheduleCount: rescheduleCount ?? this.rescheduleCount,
    );
  }
}
