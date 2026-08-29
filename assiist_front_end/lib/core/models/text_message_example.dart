import 'package:cloud_firestore/cloud_firestore.dart';

class TextMessageExample {
  final String id;
  final String exampleText;
  final DateTime createdOn;
  final String userId;

  TextMessageExample({
    required this.id,
    required this.exampleText,
    required this.createdOn,
    required this.userId,
  });

  // API: fromJson
  factory TextMessageExample.fromJson(Map<String, dynamic> json) {
    return TextMessageExample(
      id: json['id'] as String,
      exampleText: json['example_text'] as String,
      createdOn: DateTime.parse(json['created_on'] as String),
      userId: json['user_id'] as String,
    );
  }

  // API: toJson
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'example_text': exampleText,
      'created_on': createdOn.toIso8601String(),
      'user_id': userId,
    };
  }

  // Firestore compatibility
  Map<String, dynamic> toFirestore() {
    return {
      'example_text': exampleText,
      'created_on': Timestamp.fromDate(createdOn),
      'user_id': userId,
    };
  }

  factory TextMessageExample.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TextMessageExample(
      id: doc.id,
      exampleText: data['example_text'] as String,
      createdOn: (data['created_on'] as Timestamp).toDate(),
      userId: data['user_id'] as String,
    );
  }

  // Backward compatibility getter (deprecated)
  @deprecated
  String get text => exampleText;
}
