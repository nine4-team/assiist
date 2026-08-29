import 'package:cloud_firestore/cloud_firestore.dart';

class UserMetrics {
  final String userId;
  final String contactId;
  final int messagesSent;
  final int notesLogged;
  final DateTime lastUpdated;

  UserMetrics({
    required this.userId,
    required this.contactId,
    required this.messagesSent,
    required this.notesLogged,
    required this.lastUpdated,
  });

  factory UserMetrics.fromJson(Map<String, dynamic> json) {
    return UserMetrics(
      userId: json['user_id'] as String,
      contactId: json['contact_id'] as String,
      messagesSent: json['messages_sent'] as int? ?? 0,
      notesLogged: json['notes_logged'] as int? ?? 0,
      lastUpdated:
          json['last_updated'] is Timestamp
              ? (json['last_updated'] as Timestamp).toDate()
              : DateTime.parse(json['last_updated'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'contact_id': contactId,
      'messages_sent': messagesSent,
      'notes_logged': notesLogged,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }

  UserMetrics copyWith({
    String? userId,
    String? contactId,
    int? messagesSent,
    int? notesLogged,
    DateTime? lastUpdated,
  }) {
    return UserMetrics(
      userId: userId ?? this.userId,
      contactId: contactId ?? this.contactId,
      messagesSent: messagesSent ?? this.messagesSent,
      notesLogged: notesLogged ?? this.notesLogged,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
