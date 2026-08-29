import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:assiist_front_end/core/repositories/contact_repository.dart';
// import 'package:assiist_front_end/data/repositories/dummy/dummy_contact_repository.dart'; // Commented out dummy
import 'package:assiist_front_end/core/repositories/task_repository.dart'; // Import Task repo interface
// import 'package:assiist_front_end/data/repositories/dummy/dummy_task_repository.dart'; // Commented out dummy
import 'package:assiist_front_end/core/models/task.dart'; // Import Task model
import 'package:assiist_front_end/core/models/contact.dart'; // Import Contact model
// Import Firestore implementation later when ready
// import 'package:assiist_front_end/data/repositories/firestore/firestore_contact_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// --- ADD Imports for API Repositories and Auth Providers ---
import 'package:assiist_front_end/data/repositories/api/api_contact_repository.dart';
import 'package:assiist_front_end/data/repositories/api/api_task_repository.dart'; // Add API task repo import
import 'package:assiist_front_end/data/repositories/api/api_note_repository.dart'; // <<< IMPORT ApiNoteRepository
import 'auth_providers.dart'; // For baseUrlProvider, accessTokenProvider, AND authServiceProvider
import 'package:assiist_front_end/core/repositories/note_repository.dart'; // <<< IMPORT NoteRepository interface
// --- ADD Import for TimelineEvent ---
import 'package:assiist_front_end/screens/contact_record_screen.dart'
    show TimelineEvent, TimelineEventType; // Adjust path if needed
import 'package:assiist_front_end/core/models/note.dart'; // <<< IMPORT Note model
// --- ADD Appointment Imports ---
import 'package:assiist_front_end/core/repositories/appointment_repository.dart';
import 'package:assiist_front_end/data/repositories/api/api_appointment_repository.dart';
import 'package:assiist_front_end/core/models/appointment.dart';
// --- END Appointment Imports ---
// Remove import for the deleted api_user_repository.dart file
// import 'package:assiist_front_end/core/repositories/user_repository.dart';
// import 'package:assiist_front_end/data/repositories/api/api_user_repository.dart';
// Use package imports for pending contact repository
import 'package:assiist_front_end/core/repositories/pending_contact_repository.dart';
import 'package:assiist_front_end/data/repositories/api/api_pending_contact_repository.dart';
import 'package:assiist_front_end/core/models/pending_contact.dart';
import 'package:assiist_front_end/data/repositories/api/api_user_metrics_repository.dart';
import 'package:assiist_front_end/core/repositories/user_metrics_repository.dart';
import 'package:assiist_front_end/data/repositories/api/api_generation_request_repository.dart';
import 'package:assiist_front_end/core/repositories/user_settings_repository.dart';
import 'package:assiist_front_end/data/repositories/api/api_user_settings_repository.dart';
import 'package:assiist_front_end/services/auth_service.dart';
// ADD: Imports for AccountRepository
import 'package:assiist_front_end/core/repositories/account_repository.dart';
import 'package:assiist_front_end/data/repositories/api/api_account_repository.dart';
import 'package:assiist_front_end/core/repositories/user_profile_repository.dart';
import 'package:assiist_front_end/data/repositories/api/api_user_profile_repository.dart';
import 'package:assiist_front_end/data/repositories/api/api_update_assistant_repository.dart';
import 'package:assiist_front_end/core/repositories/assistant_repository.dart';
import 'package:assiist_front_end/data/repositories/api/api_assistant_repository.dart';
import 'package:assiist_front_end/services/attachment_service.dart';
// ADD: Imports for FeedbackRepository
import 'package:assiist_front_end/core/repositories/feedback_repository.dart';
import 'package:assiist_front_end/data/repositories/api/api_feedback_repository.dart';

/// Provider for the ContactRepository interface.
///
/// By default, it provides the DummyContactRepository for UI development.
/// To switch to the real Firestore implementation, change the provider's
/// create callback to return an instance of FirestoreContactRepository.
final contactRepositoryProvider = Provider<ContactRepository>((ref) {
  // --- Switch between Dummy and API implementation here ---

  // Return Dummy implementation for now:
  // return DummyContactRepository(); // Commented out dummy

  // --- Return API implementation ---
  final baseUrl = ref.watch(baseUrlProvider);
  final authService = ref.watch(authServiceProvider);

  if (baseUrl == null) {
    throw Exception("API Base URL is not configured.");
  }
  // authService is an instance of AuthService, not nullable based on typical provider setup for services.
  // If authServiceProvider could yield null, further checks or different provider type would be needed.
  return ApiContactRepository(baseUrl: baseUrl, authService: authService);
});

// --- Task Repository --- //
final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  // --- Switch between Dummy and API implementation here ---

  // Return Dummy implementation for now:
  // return DummyTaskRepository(); // Commented out dummy

  // Return API implementation when ready:
  final baseUrl = ref.watch(baseUrlProvider);
  final authService = ref.watch(authServiceProvider);
  // Similar check for baseUrl as in contactRepositoryProvider
  if (baseUrl == null) {
    throw Exception("API Base URL is not configured.");
  }
  // Assuming ApiTaskRepository handles potential null token appropriately
  return ApiTaskRepository(baseUrl: baseUrl, authService: authService);
});

// --- Note Repository --- //
final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authService = ref.watch(authServiceProvider);
  if (baseUrl == null) {
    throw Exception("API Base URL is not configured.");
  }
  // Assuming ApiNoteRepository handles potential null token appropriately
  return ApiNoteRepository(baseUrl: baseUrl, authService: authService);
});

// --- NEW: Appointment Repository Provider ---
final appointmentRepositoryProvider = Provider<AppointmentRepository>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authService = ref.watch(authServiceProvider);
  if (baseUrl == null) {
    throw Exception("API Base URL is not configured.");
  }
  return ApiAppointmentRepository(baseUrl: baseUrl, authService: authService);
});
// --- END NEW ---

// --- NEW: Feedback Repository Provider ---
final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authService = ref.watch(authServiceProvider);
  if (baseUrl == null) {
    throw Exception("API Base URL is not configured.");
  }
  return ApiFeedbackRepository(baseUrl: baseUrl, authService: authService);
});
// --- END NEW ---

// --- REMOVE Task View State --- //

// --- NEW: Provider family to fetch notes for a specific contact ---
final notesForContactProvider = FutureProvider.family<List<Note>, String>((
  ref,
  contactId,
) async {
  if (contactId.isEmpty) {
    return [];
  }
  final noteRepository = ref.watch(noteRepositoryProvider);
  final notes = await noteRepository.getNotesForContact(contactId);
  return notes;
});
// --- END NEW ---

// --- NEW: Provider family to fetch appointments for a specific contact ---
final appointmentsForContactProvider =
    FutureProvider.family<List<Appointment>, String>((ref, contactId) async {
      if (contactId.isEmpty) {
        return [];
      }
      final appointmentRepository = ref.watch(appointmentRepositoryProvider);
      final appointments = await appointmentRepository
          .getAppointmentsForContact(contactId);
      return appointments;
    });
// --- END NEW ---

// --- Specific Data Providers using Repositories --- //

/// Provider to fetch PENDING tasks for the dashboard, including contact info.
final dashboardTasksProvider = FutureProvider<List<Task>>((ref) async {
  final taskRepository = ref.watch(taskRepositoryProvider);
  final allTasks = await taskRepository.getAllTasksForUser();

  // Filter for PENDING tasks with more lenient actionable_date check
  final pendingTasks =
      allTasks
          .where(
            (task) =>
                task.status == 'pending' &&
                (task.actionableDate == null ||
                    task.actionableDate!.isBefore(DateTime.now())),
          )
          .toList();

  return pendingTasks;
});

/// Provider family to fetch tasks for a specific contact.
/// NOTE: This provider fetches ALL tasks (pending and completed) for the contact.
final tasksForContactProvider = FutureProvider.family<List<Task>, String>((
  ref,
  contactId,
) async {
  // If contactId is empty, return empty list immediately (or handle as error)
  if (contactId.isEmpty) {
    return [];
  }
  final taskRepository = ref.watch(taskRepositoryProvider);
  final tasks = await taskRepository.getTasksForContact(contactId);

  // TODO: Consider fetching associated Contact object here if needed by TaskItem
  // Since we are already in the context of a Contact screen, maybe less critical here?
  // However, the Task model itself doesn't store the full Contact object when parsed from Firestore.
  // If TaskItem needs contact details, they might need to be passed differently
  // or fetched here (less efficient if TaskItem only needs name).

  return tasks;
});

// TODO: Add providers for other specific data needs (e.g., tasks for a specific contact)

// TODO: Add providers for Notes, Appointments etc. here later. // <<< We added Notes provider above

// --- NEW: Provider to fetch and combine all timeline events for a contact ---
final timelineEventsForContactProvider = FutureProvider.family<
  List<TimelineEvent>,
  String
>((ref, contactId) async {
  if (contactId.isEmpty) {
    return [];
  }

  // Fetch tasks, notes, and appointments in parallel
  final tasksFuture = ref.watch(tasksForContactProvider(contactId).future);
  final notesFuture = ref.watch(notesForContactProvider(contactId).future);
  final appointmentsFuture = ref.watch(
    appointmentsForContactProvider(contactId).future,
  );

  // Wait for all fetches to complete
  final List<Task> tasks = await tasksFuture;
  final List<Note> notes = await notesFuture;
  final List<Appointment> appointments = await appointmentsFuture;

  final List<TimelineEvent> timelineEvents = [];

  // Transform Tasks into TimelineEvents
  for (final task in tasks) {
    DateTime? eventTimestamp;
    TimelineEventType? eventType;
    String? eventDescription;

    if (task.status == 'pending') {
      // For pending tasks, use dueDate for both messages and actions
      eventTimestamp = task.dueDate;

      if (task.type == 'message') {
        eventType = TimelineEventType.scheduledMessage;
        eventDescription = "${task.title}: ${task.body ?? ''}";
      } else if (task.type == 'action') {
        eventType = TimelineEventType.scheduledTask;
        eventDescription = task.description ?? task.title;
      }
    } else if (task.status == 'completed') {
      // For completed tasks, ONLY use completedOn - log missing data integrity
      if (task.completedOn != null) {
        eventTimestamp = task.completedOn;

        if (task.type == 'message') {
          eventType = TimelineEventType.messageSent;
          eventDescription = "${task.title}: ${task.body ?? ''}";
        } else if (task.type == 'action') {
          eventType = TimelineEventType.taskCompleted;
          eventDescription = task.description ?? task.title;
        }
      } else {
        // Log data integrity issue - completed task missing completedOn timestamp
        print(
          'WARNING: Completed task ${task.id} (${task.title}) missing completedOn timestamp',
        );
        // Skip adding this task to timeline rather than using misleading fallback dates
        continue;
      }
    }

    if (eventTimestamp != null && eventType != null) {
      timelineEvents.add(
        TimelineEvent(
          id: task.id,
          timestamp: eventTimestamp,
          description: eventDescription ?? task.title,
          type: eventType,
        ),
      );
    }
  }

  // Transform Notes into TimelineEvents
  for (final note in notes) {
    // Notes are always past events
    timelineEvents.add(
      TimelineEvent(
        id: note.id ?? '',
        timestamp: note.createdOn,
        description: note.processedNote?.body ?? note.rawNote ?? '',
        type: TimelineEventType.noteAdded,
      ),
    );
  }

  // Transform Appointments into TimelineEvents
  for (final appointment in appointments) {
    DateTime? eventTimestamp = appointment.startTime;
    TimelineEventType? eventType;

    if (eventTimestamp != null) {
      if (eventTimestamp.isAfter(DateTime.now())) {
        eventType = TimelineEventType.scheduledAppointment;
      } else {
        eventType = TimelineEventType.appointmentHeld;
      }

      timelineEvents.add(
        TimelineEvent(
          id: appointment.id ?? '',
          timestamp: eventTimestamp,
          description: appointment.title,
          type: eventType,
        ),
      );
    }
  }

  // Return unsorted - the screen will handle sorting appropriately for past vs upcoming
  return timelineEvents;
});
// --- END NEW ---

// REFACTORED: dashboardDraftsProvider to derive from dashboardTasksProvider's AsyncValue
final dashboardDraftsProvider = Provider.autoDispose<AsyncValue<List<Task>>>((
  ref,
) {
  // Watch the AsyncValue of dashboardTasksProvider
  final asyncTasks = ref.watch(dashboardTasksProvider);

  // Transform the AsyncValue
  return asyncTasks.when(
    data: (allPendingTasks) {
      // Filter for PENDING message drafts
      // Note: dashboardTasksProvider already filters for status == 'pending'
      final pendingDrafts =
          allPendingTasks
              .where(
                (task) => task.type == 'message',
              ) // No need to re-check status if dashboardTasksProvider guarantees it
              .toList();
      return AsyncValue.data(pendingDrafts);
    },
    loading: () => const AsyncValue.loading(),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
  );
});

// Provider for PendingContactRepository
final pendingContactRepositoryProvider = Provider<PendingContactRepository>((
  ref,
) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authService = ref.watch(authServiceProvider);
  if (baseUrl == null) {
    throw Exception(
      "API Base URL is not configured for PendingContactRepository.",
    );
  }
  return ApiPendingContactRepository(
    baseUrl: baseUrl,
    authService: authService,
  );
});

// Provider for fetching DASHBOARD Pending Contacts (status='pending')
final dashboardPendingContactsProvider =
    FutureProvider.autoDispose<List<PendingContact>>((ref) async {
      final repository = ref.watch(pendingContactRepositoryProvider);
      // Explicitly fetch with status 'pending' for the dashboard
      return repository.getPendingContacts(status: 'pending');
    });

// Provider for UserMetricsRepository
final userMetricsRepositoryProvider = Provider<UserMetricsRepository>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authService = ref.watch(authServiceProvider);

  if (baseUrl == null) {
    throw Exception("API Base URL is not configured.");
  }
  return ApiUserMetricsRepository(baseUrl: baseUrl, authService: authService);
});

// Provider for ApiGenerationRequestRepository
final generationRequestRepositoryProvider =
    Provider<ApiGenerationRequestRepository>((ref) {
      final baseUrl = ref.watch(baseUrlProvider);
      final authService = ref.watch(authServiceProvider);

      if (baseUrl == null) {
        throw Exception("API Base URL is not configured.");
      }
      return ApiGenerationRequestRepository(
        baseUrl: baseUrl,
        authService: authService,
      );
    });

// --- UserSettings Repository Provider ---
final userSettingsRepositoryProvider = Provider<UserSettingsRepository>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authService = ref.watch(authServiceProvider);
  final pendingContactRepo = ref.watch(pendingContactRepositoryProvider);

  if (baseUrl == null) {
    throw Exception(
      "API Base URL is not configured for UserSettingsRepository.",
    );
  }
  return ApiUserSettingsRepository(
    baseUrl: baseUrl,
    authService: authService,
    pendingContactRepository: pendingContactRepo,
  );
});

// ADDED: Account Repository Provider
final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authService = ref.watch(authServiceProvider);

  if (baseUrl == null) {
    throw Exception("API Base URL is not configured for AccountRepository.");
  }
  return ApiAccountRepository(baseUrl: baseUrl, authService: authService);
});

// Provider for UserProfileRepository
final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authService = ref.watch(authServiceProvider);
  return ApiUserProfileRepository(baseUrl: baseUrl, authService: authService);
});

// Provider for AssistantRepository
final assistantRepositoryProvider = Provider<AssistantRepository>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authService = ref.watch(authServiceProvider);

  if (baseUrl == null) {
    throw Exception("API Base URL is not configured for AssistantRepository.");
  }
  return ApiAssistantRepository(baseUrl: baseUrl, authService: authService);
});

// --- NEW: Provider family for individual task state management ---
final currentTaskProvider = StateNotifierProvider.family<
  CurrentTaskNotifier,
  AsyncValue<Task?>,
  TaskIdentifier
>((ref, taskIdentifier) {
  return CurrentTaskNotifier(ref, taskIdentifier);
});

class TaskIdentifier {
  final String taskId;
  final String contactId;

  TaskIdentifier({required this.taskId, required this.contactId});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskIdentifier &&
        other.taskId == taskId &&
        other.contactId == contactId;
  }

  @override
  int get hashCode => taskId.hashCode ^ contactId.hashCode;
}

class CurrentTaskNotifier extends StateNotifier<AsyncValue<Task?>> {
  final Ref ref;
  final TaskIdentifier taskIdentifier;

  CurrentTaskNotifier(this.ref, this.taskIdentifier)
    : super(const AsyncValue.loading()) {
    _loadTask();
  }

  Future<void> _loadTask() async {
    try {
      state = const AsyncValue.loading();
      final taskRepo = ref.read(taskRepositoryProvider);

      // Use the existing contact-scoped endpoint that already works
      final task = await taskRepo.getById(
        taskIdentifier.taskId,
        taskIdentifier.contactId,
      );

      if (task == null) {
        throw Exception('Task not found');
      }

      state = AsyncValue.data(task);
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
    }
  }

  void refreshTask() {
    _loadTask();
  }

  void updateTaskLocally(Task updatedTask) {
    state = AsyncValue.data(updatedTask);
  }
}

// Provider for Update Assistant Repository
final updateAssistantRepositoryProvider =
    Provider<ApiUpdateAssistantRepository>((ref) {
      final baseUrl = ref.watch(baseUrlProvider);
      final authService = ref.watch(authServiceProvider);

      if (baseUrl == null) {
        throw Exception("API Base URL is not configured.");
      }
      return ApiUpdateAssistantRepository(
        baseUrl: baseUrl,
        authService: authService,
      );
    });

// Provider for Attachment Service
final attachmentServiceProvider = Provider<AttachmentService>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authService = ref.watch(authServiceProvider);

  if (baseUrl == null) {
    throw Exception("API Base URL is not configured.");
  }
  return AttachmentService(baseUrl: baseUrl, authService: authService);
});
