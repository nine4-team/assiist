import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

// ✅ Configuration class for Update Assistant monitoring
class UpdateAssistantMonitoringConfig {
  final bool monitorTaskUpdates; // Listen to update_tasks operations
  final bool monitorContextUpdates; // Listen to update_context operations
  final bool monitorNoteProcessing; // Listen to process_note operations
  final Duration timeoutDuration; // Monitoring timeout (default: 2 minutes)

  const UpdateAssistantMonitoringConfig({
    this.monitorTaskUpdates = true,
    this.monitorContextUpdates = true,
    this.monitorNoteProcessing = true,
    this.timeoutDuration = const Duration(minutes: 2),
  });
}

// ✅ Event models for UI communication
class OperationCompletionEvent {
  final String requestId;
  final String operationType;
  final String contactId;
  final List<String> providersToInvalidate;

  const OperationCompletionEvent({
    required this.requestId,
    required this.operationType,
    required this.contactId,
    required this.providersToInvalidate,
  });
}

class MonitoringStatusEvent {
  final bool isMonitoring;
  final Map<String, int> pendingOperationCounts;
  final bool allOperationsComplete;

  const MonitoringStatusEvent({
    required this.isMonitoring,
    required this.pendingOperationCounts,
    required this.allOperationsComplete,
  });
}

// ✅ Main monitoring service
class UpdateAssistantMonitoringService {
  final FirebaseFirestore _firestore;
  UpdateAssistantMonitoringConfig _config;

  // Operation tracking
  final Map<String, Set<String>> _pendingOperationsByType = {
    'update_tasks': <String>{},
    'update_context': <String>{},
    'process_note': <String>{},
  };
  final Map<String, Timer> _operationTimeouts = {};
  final Map<String, StreamSubscription> _firestoreListeners = {};

  // Event controllers for UI communication
  final StreamController<OperationCompletionEvent>
  _operationCompletionController =
      StreamController<OperationCompletionEvent>.broadcast();
  final StreamController<MonitoringStatusEvent> _monitoringStatusController =
      StreamController<MonitoringStatusEvent>.broadcast();

  // Public streams
  Stream<OperationCompletionEvent> get operationCompletions =>
      _operationCompletionController.stream;
  Stream<MonitoringStatusEvent> get monitoringStatus =>
      _monitoringStatusController.stream;

  // Currently monitored contact (single contact monitoring for now)
  String? _currentContactId;

  UpdateAssistantMonitoringService({
    required FirebaseFirestore firestore,
    UpdateAssistantMonitoringConfig? config,
  }) : _firestore = firestore,
       _config = config ?? const UpdateAssistantMonitoringConfig();

  // ✅ Main method to start monitoring for a contact
  Future<void> startMonitoringForContact(String contactId) async {
    // Stop any previous monitoring
    if (_currentContactId != null) {
      stopMonitoring();
    }

    _currentContactId = contactId;
    print(
      "🔥 SERVICE: Starting Update Assistant monitoring for contact: $contactId",
    );

    try {
      // Check each operation type based on configuration
      final List<Future<QuerySnapshot>> futures = [];
      final List<String> operationTypes = [];

      if (_config.monitorTaskUpdates) {
        futures.add(_queryRecentOperations(contactId, 'update_tasks'));
        operationTypes.add('update_tasks');
      }
      if (_config.monitorContextUpdates) {
        futures.add(_queryRecentOperations(contactId, 'update_context'));
        operationTypes.add('update_context');
      }
      if (_config.monitorNoteProcessing) {
        futures.add(_queryRecentOperations(contactId, 'process_note'));
        operationTypes.add('process_note');
      }

      final results = await Future.wait(futures);

      for (int i = 0; i < results.length; i++) {
        final operationType = operationTypes[i];
        final snapshot = results[i];

        if (snapshot.docs.isNotEmpty) {
          print(
            "🔄 Found ${snapshot.docs.length} recent $operationType operations",
          );
          for (final doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>?;
            final status = data?['status'] ?? 'pending';

            if (status == 'completed') {
              // Operation already completed - trigger immediate refresh
              print("🔄 $operationType already completed: ${doc.id}");
              _handleOperationCompletion(doc.id, operationType, contactId);
            } else if (status == 'pending' || status == 'processing') {
              // Operation still in progress - monitor it
              _startOperationMonitor(doc.id, operationType, contactId);
            } else if (status == 'failed') {
              // Operation failed - handle failure
              print("🔄 $operationType already failed: ${doc.id}");
              _handleOperationFailure(
                doc.id,
                operationType,
                contactId,
                data?['error_message'],
              );
            }
          }
        }
      }

      _emitMonitoringStatus();
    } catch (e) {
      print("Warning: Could not start monitoring for contact $contactId: $e");
    }
  }

  // ✅ Helper method to query recent operations for a specific type (regardless of status)
  Future<QuerySnapshot> _queryRecentOperations(
    String contactId,
    String operationType,
  ) {
    return _firestore
        .collection('genai_requests')
        .where('contact_id', isEqualTo: contactId)
        .where('request_type', isEqualTo: operationType)
        .where(
          'created_on',
          isGreaterThan: DateTime.now().subtract(const Duration(minutes: 5)),
        )
        .get();
  }

  // ✅ Start monitoring a specific operation
  void _startOperationMonitor(
    String requestId,
    String operationType,
    String contactId,
  ) {
    if (_pendingOperationsByType[operationType]?.contains(requestId) == true)
      return;

    _pendingOperationsByType[operationType]?.add(requestId);

    print("🔄 Starting $operationType monitor for request: $requestId");

    // Set up Firestore listener
    final listenerKey = '$requestId-$operationType';
    _firestoreListeners[listenerKey] = _firestore
        .collection('genai_requests')
        .doc(requestId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!snapshot.exists) return;

            final data = snapshot.data();
            final status = data?['status'] ?? 'pending';

            if (status == 'completed') {
              print("🔄 $operationType completed for request: $requestId");
              _handleOperationCompletion(requestId, operationType, contactId);
            } else if (status == 'failed') {
              print("🔄 $operationType failed for request: $requestId");
              _handleOperationFailure(
                requestId,
                operationType,
                contactId,
                data?['error_message'],
              );
            }
          },
          onError: (error) {
            print('❌ $operationType listener error: $error');
            _cleanupOperation(requestId, operationType);
          },
        );

    // Set timeout for this specific operation
    _operationTimeouts[requestId] = Timer(_config.timeoutDuration, () {
      if (_pendingOperationsByType[operationType]?.contains(requestId) ==
          true) {
        _handleOperationTimeout(requestId, operationType, contactId);
      }
    });

    _emitMonitoringStatus();
  }

  // ✅ Handle successful operation completion
  void _handleOperationCompletion(
    String requestId,
    String operationType,
    String contactId,
  ) {
    _cleanupOperation(requestId, operationType);

    // Determine which providers to invalidate
    final providersToInvalidate = _getProvidersForOperation(operationType);

    // Emit completion event
    _operationCompletionController.add(
      OperationCompletionEvent(
        requestId: requestId,
        operationType: operationType,
        contactId: contactId,
        providersToInvalidate: providersToInvalidate,
      ),
    );

    _emitMonitoringStatus();
  }

  // ✅ Handle operation failure
  void _handleOperationFailure(
    String requestId,
    String operationType,
    String contactId,
    String? errorMessage,
  ) {
    _cleanupOperation(requestId, operationType);
    print("❌ $operationType failed for request $requestId: $errorMessage");
    _emitMonitoringStatus();
  }

  // ✅ Handle operation timeout
  void _handleOperationTimeout(
    String requestId,
    String operationType,
    String contactId,
  ) {
    _cleanupOperation(requestId, operationType);
    print("⏰ $operationType timeout for request: $requestId");
    _emitMonitoringStatus();
  }

  // ✅ Clean up operation tracking
  void _cleanupOperation(String requestId, String operationType) {
    _pendingOperationsByType[operationType]?.remove(requestId);
    _operationTimeouts.remove(requestId)?.cancel();

    final listenerKey = '$requestId-$operationType';
    _firestoreListeners.remove(listenerKey)?.cancel();
  }

  // ✅ Get providers to invalidate for each operation type
  List<String> _getProvidersForOperation(String operationType) {
    switch (operationType) {
      case 'update_tasks':
        return [
          'tasksForContactProvider',
          'dashboardTasksProvider',
          'timelineEventsForContactProvider', // Tasks appear in timeline
        ];
      case 'update_context':
        return ['contactByIdProvider'];
      case 'process_note':
        return [
          'notesForContactProvider',
          'timelineEventsForContactProvider', // Notes appear in timeline
        ];
      default:
        return [];
    }
  }

  // ✅ Emit current monitoring status
  void _emitMonitoringStatus() {
    final pendingCounts = <String, int>{};
    for (final entry in _pendingOperationsByType.entries) {
      pendingCounts[entry.key] = entry.value.length;
    }

    final totalPending = pendingCounts.values.fold(
      0,
      (sum, count) => sum + count,
    );

    _monitoringStatusController.add(
      MonitoringStatusEvent(
        isMonitoring: totalPending > 0,
        pendingOperationCounts: pendingCounts,
        allOperationsComplete: totalPending == 0,
      ),
    );
  }

  // ✅ Update configuration
  void updateConfiguration(UpdateAssistantMonitoringConfig newConfig) {
    _config = newConfig;
    print("🔄 Updated monitoring configuration");
  }

  // ✅ Stop all monitoring
  void stopMonitoring() {
    print("🔄 Stopping Update Assistant monitoring");

    // Cancel all timers
    for (final timer in _operationTimeouts.values) {
      timer.cancel();
    }
    _operationTimeouts.clear();

    // Cancel all Firestore listeners
    for (final subscription in _firestoreListeners.values) {
      subscription.cancel();
    }
    _firestoreListeners.clear();

    // Clear tracking
    for (final operationSet in _pendingOperationsByType.values) {
      operationSet.clear();
    }

    _currentContactId = null;
    _emitMonitoringStatus();
  }

  // ✅ Check if monitoring a specific contact
  bool isMonitoringContact(String contactId) {
    return _currentContactId == contactId;
  }

  // ✅ Dispose and cleanup
  void dispose() {
    stopMonitoring();
    _operationCompletionController.close();
    _monitoringStatusController.close();
  }
}
