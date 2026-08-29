import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:assiist_front_end/core/models/generation_request.dart';
import 'package:assiist_front_end/utils/generation_request_utils.dart';
import 'package:assiist_front_end/services/auth_service.dart';

/// Service layer for all generation request operations
/// Handles both API calls to backend and real-time Firestore monitoring
class GenerationRequestService {
  static final GenerationRequestService _instance =
      GenerationRequestService._internal();
  factory GenerationRequestService() => _instance;
  GenerationRequestService._internal();

  final AuthService _authService = AuthService();

  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'assiist-app',
  );

  // Active subscriptions for cleanup
  final Map<String, StreamSubscription> _activeSubscriptions = {};

  // Base URL for API calls - now loaded from environment
  static String get _apiBaseUrl {
    final String? apiUrl = dotenv.env['API_URL'];
    if (apiUrl == null || apiUrl.isEmpty) {
      throw Exception(
        "API_URL not found in environment. Please ensure it is set in your .env file.",
      );
    }
    return apiUrl;
  }

  // ============================================================================
  // API CALLS (Create Requests)
  // ============================================================================

  /// Create a quick draft request
  Future<GenerationRequestResult> createQuickDraft({
    required String contactId,
    required String instructions,
    String language = 'english',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/v1/assistant/quick-actions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getAuthToken()}',
        },
        body: jsonEncode({
          'contact_id': contactId,
          'request_type': 'quick_draft',
          'message_instructions': instructions,
          'message_language': language,
        }),
      );

      if (response.statusCode == 202) {
        final data = jsonDecode(response.body);
        return GenerationRequestResult.success(
          requestId: data['id'],
          message: data['message'] ?? 'Quick draft request created',
        );
      } else {
        return GenerationRequestResult.error(
          'Failed to create quick draft: ${response.statusCode}',
        );
      }
    } catch (e) {
      return GenerationRequestResult.error('Network error: $e');
    }
  }

  /// Create a revision request
  Future<GenerationRequestResult> createRevision({
    required String taskId,
    required String revisionInstructions,
    String language = 'english',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/v1/assistant/quick-actions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getAuthToken()}',
        },
        body: jsonEncode({
          'request_type': 'revise_draft',
          'task_id': taskId,
          'revision_instructions': revisionInstructions,
          'message_language': language,
        }),
      );

      if (response.statusCode == 202) {
        final data = jsonDecode(response.body);
        return GenerationRequestResult.success(
          requestId: data['id'],
          message: data['message'] ?? 'Revision request created successfully',
        );
      } else {
        return GenerationRequestResult.error(
          'Failed to create revision request: ${response.statusCode}',
        );
      }
    } catch (e) {
      return GenerationRequestResult.error('Network error: $e');
    }
  }

  /// Create update assistant request and extract process_note request ID for monitoring
  Future<GenerationRequestResult> createUpdateAssistant({
    required String contactId,
    required String noteContent,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/assistant/update-assistant'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getAuthToken()}',
        },
        body: jsonEncode({
          'contact_id': contactId,
          'note_content': noteContent,
        }),
      );

      if (response.statusCode == 202) {
        final data = jsonDecode(response.body);
        // Extract the process_note request ID specifically
        final processNoteRequestId = data['request_ids']?['process_note'];

        return GenerationRequestResult.success(
          requestId: processNoteRequestId, // ← Focus on note processing
          message: data['message'] ?? 'Note processing started',
          additionalData: data['request_ids'], // All 3 request IDs available
        );
      } else {
        return GenerationRequestResult.error(
          'Failed to create update assistant request: ${response.statusCode}',
        );
      }
    } catch (e) {
      return GenerationRequestResult.error('Network error: $e');
    }
  }

  /// Submit note optimistically without waiting for completion (for log_note_screen)
  Future<GenerationRequestResult> submitNoteOptimistically({
    required String contactId,
    required String noteContent,
  }) async {
    try {
      print(
        '📡 Attempting to submit note to: $_apiBaseUrl/assistant/update-assistant',
      );
      print(
        '📋 Request payload: ${jsonEncode({'contact_id': contactId, 'note_content': noteContent})}',
      );

      final response = await http.post(
        Uri.parse('$_apiBaseUrl/assistant/update-assistant'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getAuthToken()}',
        },
        body: jsonEncode({
          'contact_id': contactId,
          'note_content': noteContent,
        }),
      );

      print('📥 Response status code: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 202) {
        final data = jsonDecode(response.body);
        // Extract the process_note request ID for reference
        final processNoteRequestId = data['request_ids']?['process_note'];

        return GenerationRequestResult.success(
          requestId: processNoteRequestId,
          message: 'Note submitted successfully for processing',
          additionalData: data['request_ids'], // All 3 request IDs available
        );
      } else {
        print('❌ Request failed with status: ${response.statusCode}');
        print('❌ Error response: ${response.body}');
        return GenerationRequestResult.error(
          'Failed to submit note: ${response.statusCode}',
        );
      }
    } catch (e, stackTrace) {
      print('❌ Exception during note submission:');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      return GenerationRequestResult.error('Network error: $e');
    }
  }

  /// Create update assistant request (legacy - matches current repository interface)
  Future<Map<String, dynamic>> updateAssistant({
    required String contactId,
    required String rawNoteContent,
    Map<String, dynamic>? context,
  }) async {
    // Implementation of updateAssistant method
    throw UnimplementedError();
  }

  // ============================================================================
  // FIRESTORE LISTENERS (Monitor Status)
  // ============================================================================

  /// Listen to a generation request's status changes
  Stream<GenerationRequestStatus> listenToRequestStatus({
    required String requestId,
    required String operationType, // 'quick_draft', 'revise_draft', etc.
  }) {
    final controller = StreamController<GenerationRequestStatus>();

    try {
      final collection = GenerationRequestUtils.getCollectionForOperation(
        operationType,
      );

      final subscription = _firestore
          .collection(collection)
          .doc(requestId)
          .snapshots()
          .listen(
            (snapshot) {
              if (snapshot.exists) {
                final data = snapshot.data() as Map<String, dynamic>;
                final status = GenerationRequestStatus.fromFirestore(
                  data,
                  requestId,
                );
                controller.add(status);

                // Auto-close stream when completed or failed
                if (status.isComplete) {
                  controller.close();
                  _activeSubscriptions.remove(requestId);
                }
              } else {
                controller.addError('Request document not found');
              }
            },
            onError: (error) {
              controller.addError('Firestore error: $error');
            },
          );

      _activeSubscriptions[requestId] = subscription;

      // Auto-cleanup after timeout
      Timer(const Duration(minutes: 10), () {
        if (_activeSubscriptions.containsKey(requestId)) {
          subscription.cancel();
          _activeSubscriptions.remove(requestId);
          if (!controller.isClosed) {
            controller.addError('Request timeout after 10 minutes');
            controller.close();
          }
        }
      });
    } catch (e) {
      controller.addError('Failed to setup listener: $e');
    }

    return controller.stream;
  }

  /// Get the current status of a request (one-time read)
  Future<GenerationRequestStatus?> getRequestStatus({
    required String requestId,
    required String operationType,
  }) async {
    try {
      final collection = GenerationRequestUtils.getCollectionForOperation(
        operationType,
      );
      final doc = await _firestore.collection(collection).doc(requestId).get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        return GenerationRequestStatus.fromFirestore(data, requestId);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get request status: $e');
    }
  }

  // ============================================================================
  // CONVENIENCE METHODS
  // ============================================================================

  /// Create quick draft and return a stream of status updates
  Future<Stream<GenerationRequestStatus>> createQuickDraftWithListener({
    required String contactId,
    required String instructions,
    String language = 'english',
  }) async {
    final result = await createQuickDraft(
      contactId: contactId,
      instructions: instructions,
      language: language,
    );

    if (result.isSuccess) {
      return listenToRequestStatus(
        requestId: result.requestId!,
        operationType: 'quick_draft',
      );
    } else {
      throw Exception(result.errorMessage);
    }
  }

  /// Create revision and return a stream of status updates
  Future<Stream<GenerationRequestStatus>> createRevisionWithListener({
    required String taskId,
    required String revisionInstructions,
    String language = 'english',
  }) async {
    final result = await createRevision(
      taskId: taskId,
      revisionInstructions: revisionInstructions,
      language: language,
    );

    if (result.isSuccess) {
      return listenToRequestStatus(
        requestId: result.requestId!,
        operationType: 'revise_draft',
      );
    } else {
      throw Exception(result.errorMessage);
    }
  }

  // ============================================================================
  // CLEANUP & HELPERS
  // ============================================================================

  /// Cancel a specific request listener
  void cancelListener(String requestId) {
    _activeSubscriptions[requestId]?.cancel();
    _activeSubscriptions.remove(requestId);
  }

  /// Cancel all active listeners
  void cancelAllListeners() {
    for (final subscription in _activeSubscriptions.values) {
      subscription.cancel();
    }
    _activeSubscriptions.clear();
  }

  /// Get authentication token for API calls
  Future<String> _getAuthToken() async {
    final String? freshToken = await _authService.getFreshAuthToken();
    if (freshToken != null) {
      return freshToken;
    } else {
      throw Exception('User not authenticated or token refresh failed.');
    }
  }

  /// Dispose resources
  void dispose() {
    cancelAllListeners();
  }
}

// ============================================================================
// RESULT MODELS
// ============================================================================

/// Result wrapper for API calls
class GenerationRequestResult {
  final bool isSuccess;
  final String? requestId;
  final String? message;
  final String? errorMessage;
  final Map<String, dynamic>? additionalData;

  GenerationRequestResult._({
    required this.isSuccess,
    this.requestId,
    this.message,
    this.errorMessage,
    this.additionalData,
  });

  factory GenerationRequestResult.success({
    required String requestId,
    String? message,
    Map<String, dynamic>? additionalData,
  }) {
    return GenerationRequestResult._(
      isSuccess: true,
      requestId: requestId,
      message: message,
      additionalData: additionalData,
    );
  }

  factory GenerationRequestResult.error(String errorMessage) {
    return GenerationRequestResult._(
      isSuccess: false,
      errorMessage: errorMessage,
    );
  }
}

/// Status model for real-time updates
class GenerationRequestStatus {
  final String requestId;
  final String status; // 'pending', 'processing', 'completed', 'failed'
  final String? errorMessage;
  final Map<String, dynamic>? resultData;
  final DateTime? lastUpdated;

  GenerationRequestStatus({
    required this.requestId,
    required this.status,
    this.errorMessage,
    this.resultData,
    this.lastUpdated,
  });

  bool get isPending => status == 'pending';
  bool get isProcessing => status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isComplete => isCompleted || isFailed;

  /// Create from Firestore document data
  factory GenerationRequestStatus.fromFirestore(
    Map<String, dynamic> data,
    String requestId,
  ) {
    return GenerationRequestStatus(
      requestId: requestId,
      status: data['status'] ?? 'pending',
      errorMessage: data['error_message'],
      resultData: _extractResultData(data),
      lastUpdated: (data['processed_on'] as Timestamp?)?.toDate(),
    );
  }

  /// Extract result data based on operation type
  static Map<String, dynamic>? _extractResultData(Map<String, dynamic> data) {
    if (data['status'] != 'completed') return null;

    final processingMetadata =
        data['processing_metadata'] as Map<String, dynamic>?;
    final generatedTaskId = processingMetadata?['generated_task_id'] as String?;

    // For task operations (quick_draft), provide the task_id for fetching
    if (generatedTaskId != null) {
      return {'generated_task_id': generatedTaskId};
    }

    // For other operations, return the result_data directly
    final resultData = data['result_data'] as Map<String, dynamic>?;
    return resultData;
  }
}
