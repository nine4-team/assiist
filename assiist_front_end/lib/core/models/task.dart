import 'package:cloud_firestore/cloud_firestore.dart'; // Import for Timestamp
import './contact.dart'; // Assuming Contact model is in the same directory
import 'dart:convert'; // Import for utf8
import 'package:assiist_front_end/utils/text_encoding_utils.dart'; // Import the universal text encoding utils

// --- REMOVED TaskType Enum and helpers ---

class Task {
  final String id;
  final String title;
  final Contact? contact; // Convenience object, not directly mapped to JSON
  final String? contactId; // Mapped to/from contact_id
  final String? contactDisplayName; // NEW: Denormalized contact display name
  final String? body; // REPLACES description and messageBody
  final String type; // REPLACES taskType enum ('message' or 'action')
  final DateTime? dueDate; // Mapped to/from due_date
  final DateTime? actionableDate; // NEW: Mapped to/from actionable_date
  final String
  status; // REPLACES isCompleted ('pending', 'completed', 'deleted')
  final String? assignedUser; // NEW: Mapped to/from assigned_user
  final String
  userId; // Mapped to/from user_id - Made non-nullable based on backend schema
  final String
  createdBy; // Mapped to/from created_by - Made non-nullable based on backend schema
  final DateTime
  createdOn; // Mapped to/from created_on - Made non-nullable based on backend schema
  final String? updatedBy; // NEW: Mapped to/from updated_by
  final DateTime? updatedOn; // NEW: Mapped to/from updated_on
  final String? description; // <<< Add optional description field
  final DateTime? completedOn; // <<< ADD completedOn field
  final String? sms_url; // URL for sending the message via SMS
  final String? assistant_message; // AI assistant message for task display
  final String? llm_provider; // LLM provider used for generation
  final String? accountId; // Account ID for multi-tenant isolation

  // REMOVED: isCompleted, description, messageBody, completedAt

  Task({
    required this.id,
    required this.title,
    this.contact,
    this.contactId,
    this.contactDisplayName, // NEW
    this.body,
    required this.type,
    this.dueDate,
    this.actionableDate, // NEW
    required this.status,
    this.assignedUser, // NEW
    required this.userId, // UPDATED: required
    required this.createdBy, // UPDATED: required
    required this.createdOn, // UPDATED: required
    this.updatedBy, // NEW
    this.updatedOn, // NEW
    this.description, // <<< Add optional description field
    this.completedOn, // <<< Add to constructor
    this.sms_url, // Add SMS URL field
    this.assistant_message, // Updated field name
    this.llm_provider, // Add LLM provider field
    this.accountId, // Add account ID field
  });

  // Helper function to safely convert Firestore Timestamp or ISO String to DateTime
  static DateTime? _timestampToDateTime(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    } else if (timestamp is String) {
      // Handle potential timezone info if present in ISO string
      return DateTime.tryParse(timestamp)?.toLocal();
    }
    return null;
  }

  // Helper needed for non-nullable createdOn
  static DateTime _timestampToDateTimeRequired(dynamic timestamp) {
    DateTime? dt = _timestampToDateTime(timestamp);
    if (dt == null) {
      // Fallback or throw error - using current time as fallback here
      print(
        "Warning: Could not parse required DateTime from backend: $timestamp. Using current time.",
      );
      return DateTime.now();
    }
    return dt;
  }

  // Helper function to fix UTF-8 encoding issues
  static String? _fixUtf8String(dynamic rawString) {
    if (rawString is! String || rawString.isEmpty) return rawString;

    try {
      // Convert the incorrectly decoded string back to bytes, then properly decode as UTF-8
      final bytes = rawString.codeUnits.map((unit) => unit & 0xFF).toList();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      // If UTF-8 fix fails, return the original string
      return rawString;
    }
  }

  // fromJson factory
  factory Task.fromJson(Map<String, dynamic> json, String docId) {
    // DISABLED: UTF-8 fixing since backend now sends proper UTF-8
    // final fixedJson = TextEncodingUtils.fixUtf8InJson(json) as Map<String, dynamic>;
    final fixedJson =
        json; // Use original JSON since backend UTF-8 is now correct

    // Note: Contact object needs to be fetched separately if needed beyond contactId
    return Task(
      id: docId,
      title:
          fixedJson['title'] as String? ??
          '', // Provide default value if needed
      body: fixedJson['body'] as String?, // UPDATED: Use 'body'
      type:
          fixedJson['type'] as String? ??
          'action', // UPDATED: Use 'type', default if needed
      dueDate: _timestampToDateTime(fixedJson['due_date']),
      actionableDate: _timestampToDateTime(fixedJson['actionable_date']), // NEW
      status:
          fixedJson['status'] as String? ??
          'pending', // UPDATED: Use 'status', default if needed
      assignedUser: fixedJson['assigned_user'] as String?, // NEW
      contactId:
          fixedJson['contact_id'] as String?, // Ensure contact_id is parsed
      contactDisplayName: fixedJson['contact_display_name'] as String?, // NEW
      userId:
          fixedJson['user_id'] as String? ??
          '', // UPDATED: Parse user_id, provide default if backend might omit
      createdBy:
          fixedJson['created_by'] as String? ??
          '', // UPDATED: Parse created_by, provide default
      createdOn: _timestampToDateTimeRequired(
        fixedJson['created_on'],
      ), // UPDATED: Parse created_on, ensure non-null
      updatedBy: fixedJson['updated_by'] as String?, // NEW
      updatedOn: _timestampToDateTime(fixedJson['updated_on']), // NEW
      contact: null, // Contact object is not in the JSON response
      description:
          fixedJson['description']
              as String?, // <<< Add optional description field
      completedOn: _timestampToDateTime(
        fixedJson['completed_on'],
      ), // <<< Parse completed_on
      sms_url: fixedJson['sms_url'] as String?, // Parse SMS URL
      assistant_message:
          fixedJson['assistant_message'] as String?, // Updated field name
      llm_provider: fixedJson['llm_provider'] as String?, // Parse LLM provider
      accountId: fixedJson['account_id'] as String?, // Parse account ID
    );
  }

  // toJson method - Used for sending data *to* backend (Create/Update)
  Map<String, dynamic> toJson() {
    // TODO: Refine Task.toJson(): Decide if contactDisplayName should truly be part of toJson().
    // Typically, denormalized fields that are copies from another record are read-only
    // from the client's perspective and managed by the backend.
    // Consider removing it from toJson() unless there's a specific use case for the client to send it.
    // For now, it is included, matching its presence in fromJson and copyWith.
    return {
      'title': title,
      'body': body,
      'type': type,
      'due_date': dueDate?.toUtc().toIso8601String(),
      'actionable_date': actionableDate?.toUtc().toIso8601String(),
      'status': status,
      'assigned_user': assignedUser,
      'contact_id': contactId,
      'contact_display_name': contactDisplayName,
      'description': description,
      'sms_url': sms_url,
      'assistant_message': assistant_message,
      'llm_provider': llm_provider,
      'account_id': accountId,
    }..removeWhere((key, value) => value == null);
  }

  // copyWith method
  Task copyWith({
    String? id,
    String? title,
    Contact? contact, // Keep for frontend convenience
    String? contactId,
    String? contactDisplayName, // NEW
    String? body, // UPDATED
    String? type, // UPDATED
    DateTime? dueDate,
    DateTime? actionableDate, // NEW
    String? status, // UPDATED
    String? assignedUser, // NEW
    String? userId, // UPDATED (allow update?)
    String? createdBy, // UPDATED (allow update?)
    DateTime? createdOn, // UPDATED (allow update?)
    String? updatedBy, // NEW
    DateTime? updatedOn, // NEW
    // Flags to explicitly set nullable fields to null if needed
    bool setBodyNull = false,
    bool setDueDateNull = false,
    bool setActionableDateNull = false,
    bool setAssignedUserNull = false,
    bool setContactIdNull = false,
    bool setContactDisplayNameNull = false, // NEW
    bool setUpdatedByNull = false,
    bool setUpdatedOnNull = false,
    String? description, // <<< Add optional description field
    DateTime? completedOn, // <<< Add completedOn param
    bool setCompletedOnNull = false, // <<< Add flag
    String? sms_url, // Add SMS URL parameter
    bool setSmsUrlNull = false, // Add flag for SMS URL
    String? assistant_message, // Updated parameter name
    bool setAssistantMessageNull = false, // Add flag for assistant message
    String? llm_provider, // Add LLM provider parameter
    bool setLlmProviderNull = false, // Add flag for LLM provider
    String? accountId, // Add account ID parameter
    bool setAccountIdNull = false, // Add flag for account ID
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      contact: contact ?? this.contact,
      contactId: setContactIdNull ? null : (contactId ?? this.contactId),
      contactDisplayName:
          setContactDisplayNameNull
              ? null
              : (contactDisplayName ?? this.contactDisplayName), // NEW
      body: setBodyNull ? null : (body ?? this.body), // UPDATED
      type: type ?? this.type, // UPDATED
      dueDate: setDueDateNull ? null : (dueDate ?? this.dueDate),
      actionableDate:
          setActionableDateNull
              ? null
              : (actionableDate ?? this.actionableDate), // NEW
      status: status ?? this.status, // UPDATED
      assignedUser:
          setAssignedUserNull
              ? null
              : (assignedUser ?? this.assignedUser), // NEW
      userId: userId ?? this.userId, // UPDATED
      createdBy: createdBy ?? this.createdBy, // UPDATED
      createdOn: createdOn ?? this.createdOn, // UPDATED
      updatedBy: setUpdatedByNull ? null : (updatedBy ?? this.updatedBy), // NEW
      updatedOn: setUpdatedOnNull ? null : (updatedOn ?? this.updatedOn), // NEW
      description:
          description ?? this.description, // <<< Add optional description field
      completedOn:
          setCompletedOnNull
              ? null
              : (completedOn ?? this.completedOn), // <<< Handle completedOn
      sms_url:
          setSmsUrlNull ? null : (sms_url ?? this.sms_url), // Handle SMS URL
      assistant_message:
          setAssistantMessageNull
              ? null
              : (assistant_message ??
                  this.assistant_message), // Handle assistant message
      llm_provider:
          setLlmProviderNull
              ? null
              : (llm_provider ?? this.llm_provider), // Handle LLM provider
      accountId:
          setAccountIdNull
              ? null
              : (accountId ?? this.accountId), // Handle account ID
    );
  }
}
