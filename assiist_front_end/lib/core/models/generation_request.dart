import 'package:cloud_firestore/cloud_firestore.dart';

// Enum matching backend schema literal
enum GenerationRequestType {
  quickTask,
  quickDraft;

  // Helper to convert Firestore string to enum
  static GenerationRequestType fromString(String? typeStr) {
    switch (typeStr) {
      case 'quick_task':
        return GenerationRequestType.quickTask;
      case 'quick_draft':
        return GenerationRequestType.quickDraft;
      default:
        print(
          "Warning: Unknown GenerationRequestType string: $typeStr. Defaulting to quickTask.",
        );
        return GenerationRequestType.quickTask; // Default or throw error
    }
  }

  // Convert enum to Firestore string (uses built-in .name)
  // String toJson() => name; // Not needed if using .name directly
}

// Enum matching backend schema literal
enum GenerationRequestStatus {
  pending,
  processing,
  completed,
  failed;

  // Helper to convert Firestore string to enum
  static GenerationRequestStatus fromString(String? statusStr) {
    switch (statusStr) {
      case 'pending':
        return GenerationRequestStatus.pending;
      case 'processing':
        return GenerationRequestStatus.processing;
      case 'completed':
        return GenerationRequestStatus.completed;
      case 'failed':
        return GenerationRequestStatus.failed;
      default:
        print(
          "Warning: Unknown GenerationRequestStatus string: $statusStr. Defaulting to pending.",
        );
        return GenerationRequestStatus.pending; // Default or throw error
    }
  }

  // Convert enum to Firestore string (uses built-in .name)
  // String toJson() => name; // Not needed if using .name directly
}

class GenerationRequest {
  final String id;
  final String userId;
  final String contactId;
  final GenerationRequestType requestType;
  final Map<String, dynamic> requestData;
  final GenerationRequestStatus status;
  final DateTime createdOn;
  final DateTime updatedOn;
  final String? error;

  // REPLACED OLD FIELDS: resultTaskId and resultTaskData
  // WITH UNWRAPPED FIELDS:
  final Map<String, dynamic>? task; // Task data (for task operations)
  final String? llmProvider; // LLM provider info
  final int? processingTimeMs; // Processing time
  final String? timestamp; // Completion timestamp

  // Operation-specific fields (nullable - only populated for relevant operations)
  final Map<String, dynamic>? revision; // For revise_draft only
  final Map<String, dynamic>? note; // For process_note only
  final List<dynamic>? createdTasks; // For update_tasks only
  final List<dynamic>? updatedTasks; // For update_tasks only
  final List<dynamic>? deletedTasks; // For update_tasks only
  final Map<String, dynamic>? contextBefore; // For update_context only
  final Map<String, dynamic>? contextAfter; // For update_context only
  final List<String>? changes; // For update_context only

  GenerationRequest({
    required this.id,
    required this.userId,
    required this.contactId,
    required this.requestType,
    required this.requestData,
    required this.status,
    required this.createdOn,
    required this.updatedOn,
    this.error,
    this.task,
    this.llmProvider,
    this.processingTimeMs,
    this.timestamp,
    this.revision,
    this.note,
    this.createdTasks,
    this.updatedTasks,
    this.deletedTasks,
    this.contextBefore,
    this.contextAfter,
    this.changes,
  });

  // Factory constructor from Firestore DocumentSnapshot
  factory GenerationRequest.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // Helper function to safely convert Timestamp to DateTime
    DateTime _timestampToDateTime(Timestamp? timestamp) {
      return timestamp?.toDate() ?? DateTime.now(); // Provide default if null
    }

    return GenerationRequest(
      id: doc.id,
      userId: data['user_id'] as String? ?? '', // Add null check and default
      contactId:
          data['contact_id'] as String? ?? '', // Add null check and default
      requestType: GenerationRequestType.fromString(
        data['request_type'] as String?,
      ),
      requestData: Map<String, dynamic>.from(data['request_data'] ?? {}),
      status: GenerationRequestStatus.fromString(data['status'] as String?),
      createdOn: _timestampToDateTime(data['created_on'] as Timestamp?),
      updatedOn: _timestampToDateTime(data['updated_on'] as Timestamp?),
      error: data['error'] as String?, // Cast as nullable String
      // UNWRAPPED RESULT FIELDS:
      task: data['task'] as Map<String, dynamic>?,
      llmProvider: data['llm_provider'] as String?,
      processingTimeMs: data['processing_time_ms'] as int?,
      timestamp: data['timestamp'] as String?,

      // Operation-specific fields
      revision: data['revision'] as Map<String, dynamic>?,
      note: data['note'] as Map<String, dynamic>?,
      createdTasks: data['created_tasks'] as List<dynamic>?,
      updatedTasks: data['updated_tasks'] as List<dynamic>?,
      deletedTasks: data['deleted_tasks'] as List<dynamic>?,
      contextBefore: data['context_before'] as Map<String, dynamic>?,
      contextAfter: data['context_after'] as Map<String, dynamic>?,
      changes: (data['changes'] as List<dynamic>?)?.cast<String>(),
    );
  }

  // Method to convert to Firestore map (optional, useful for creating/updating)
  Map<String, dynamic> toFirestore() {
    return {
      'user_id': userId,
      'contact_id': contactId,
      'request_type': requestType.name, // Use enum .name for string conversion
      'request_data': requestData,
      'status': status.name, // Use enum .name for string conversion
      // Use FieldValue for server timestamp on create/update if preferred
      'created_on': Timestamp.fromDate(createdOn),
      'updated_on': Timestamp.fromDate(updatedOn),
      'error': error,

      // UNWRAPPED RESULT FIELDS:
      'task': task,
      'llm_provider': llmProvider,
      'processing_time_ms': processingTimeMs,
      'timestamp': timestamp,

      // Operation-specific fields
      'revision': revision,
      'note': note,
      'created_tasks': createdTasks,
      'updated_tasks': updatedTasks,
      'deleted_tasks': deletedTasks,
      'context_before': contextBefore,
      'context_after': contextAfter,
      'changes': changes,
    };
  }

  // Factory constructor from API JSON
  factory GenerationRequest.fromJson(Map<String, dynamic> json) {
    return GenerationRequest(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      contactId: json['contact_id'] as String? ?? '',
      requestType: GenerationRequestType.fromString(
        json['request_type'] as String?,
      ),
      requestData: Map<String, dynamic>.from(json['request_data'] ?? {}),
      status: GenerationRequestStatus.fromString(json['status'] as String?),
      createdOn: DateTime.parse(
        json['requested_on'] ??
            json['created_on'] ??
            DateTime.now().toIso8601String(),
      ),
      updatedOn: DateTime.parse(
        json['processed_on'] ??
            json['updated_on'] ??
            DateTime.now().toIso8601String(),
      ),
      error: json['error_message'] as String? ?? json['error'] as String?,

      // UNWRAPPED RESULT FIELDS:
      task: json['task'] as Map<String, dynamic>?,
      llmProvider: json['llm_provider'] as String?,
      processingTimeMs: json['processing_time_ms'] as int?,
      timestamp: json['timestamp'] as String?,

      // Operation-specific fields
      revision: json['revision'] as Map<String, dynamic>?,
      note: json['note'] as Map<String, dynamic>?,
      createdTasks: json['created_tasks'] as List<dynamic>?,
      updatedTasks: json['updated_tasks'] as List<dynamic>?,
      deletedTasks: json['deleted_tasks'] as List<dynamic>?,
      contextBefore: json['context_before'] as Map<String, dynamic>?,
      contextAfter: json['context_after'] as Map<String, dynamic>?,
      changes: (json['changes'] as List<dynamic>?)?.cast<String>(),
    );
  }
}
