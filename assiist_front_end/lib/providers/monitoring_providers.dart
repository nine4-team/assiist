import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/update_assistant_monitoring_service.dart';

// ✅ Service provider
final updateAssistantMonitoringServiceProvider =
    Provider<UpdateAssistantMonitoringService>((ref) {
      final firestore = FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'assiist-app',
      );

      final service = UpdateAssistantMonitoringService(
        firestore: firestore,
        config: const UpdateAssistantMonitoringConfig(),
      );

      // Dispose the service when provider is disposed
      ref.onDispose(() {
        service.dispose();
      });

      return service;
    });

// ✅ Contact monitoring state
class ContactMonitoringState {
  final bool isMonitoring;
  final Map<String, Set<String>> pendingOperations;
  final List<OperationCompletionEvent> recentCompletions;
  final MonitoringStatusEvent? lastStatusEvent;

  const ContactMonitoringState({
    this.isMonitoring = false,
    this.pendingOperations = const {},
    this.recentCompletions = const [],
    this.lastStatusEvent,
  });

  ContactMonitoringState copyWith({
    bool? isMonitoring,
    Map<String, Set<String>>? pendingOperations,
    List<OperationCompletionEvent>? recentCompletions,
    MonitoringStatusEvent? lastStatusEvent,
  }) {
    return ContactMonitoringState(
      isMonitoring: isMonitoring ?? this.isMonitoring,
      pendingOperations: pendingOperations ?? this.pendingOperations,
      recentCompletions: recentCompletions ?? this.recentCompletions,
      lastStatusEvent: lastStatusEvent ?? this.lastStatusEvent,
    );
  }
}

// ✅ Contact monitoring notifier
class ContactMonitoringNotifier extends StateNotifier<ContactMonitoringState> {
  final UpdateAssistantMonitoringService _monitoringService;
  final String _contactId;
  StreamSubscription<OperationCompletionEvent>? _completionSubscription;
  StreamSubscription<MonitoringStatusEvent>? _statusSubscription;

  ContactMonitoringNotifier({
    required String contactId,
    required UpdateAssistantMonitoringService monitoringService,
  }) : _contactId = contactId,
       _monitoringService = monitoringService,
       super(const ContactMonitoringState()) {
    _initializeMonitoring();
  }

  void _initializeMonitoring() {
    _setupCompletionListener();
    _setupStatusListener();
    _monitoringService.startMonitoringForContact(_contactId);
  }

  void _setupCompletionListener() {
    _completionSubscription = _monitoringService.operationCompletions
        .where((event) => event.contactId == _contactId)
        .listen((event) {
          // Add to recent completions (keep last 5)
          final newCompletions = [...state.recentCompletions, event];
          if (newCompletions.length > 5) {
            newCompletions.removeAt(0);
          }

          state = state.copyWith(recentCompletions: newCompletions);
        });
  }

  void _setupStatusListener() {
    _statusSubscription = _monitoringService.monitoringStatus.listen((
      statusEvent,
    ) {
      state = state.copyWith(
        isMonitoring: statusEvent.isMonitoring,
        lastStatusEvent: statusEvent,
      );
    });
  }

  // Clear recent completions (useful after showing notifications)
  void clearRecentCompletions() {
    state = state.copyWith(recentCompletions: []);
  }

  @override
  void dispose() {
    _completionSubscription?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }
}

// ✅ Contact monitoring state provider (family for different contacts)
final contactMonitoringStateProvider = StateNotifierProvider.family
    .autoDispose<ContactMonitoringNotifier, ContactMonitoringState, String>((
      ref,
      contactId,
    ) {
      try {
        final monitoringService = ref.watch(
          updateAssistantMonitoringServiceProvider,
        );

        final notifier = ContactMonitoringNotifier(
          contactId: contactId,
          monitoringService: monitoringService,
        );

        return notifier;
      } catch (e, stackTrace) {
        rethrow;
      }
    });

// ✅ Helper provider for global monitoring status
final globalMonitoringStatusProvider = StreamProvider<MonitoringStatusEvent>((
  ref,
) {
  final service = ref.watch(updateAssistantMonitoringServiceProvider);
  return service.monitoringStatus;
});

// ✅ Helper provider for operation completions
final operationCompletionsProvider = StreamProvider<OperationCompletionEvent>((
  ref,
) {
  final service = ref.watch(updateAssistantMonitoringServiceProvider);
  return service.operationCompletions;
});
