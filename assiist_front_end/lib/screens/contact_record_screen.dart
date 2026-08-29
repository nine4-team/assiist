import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // Import Material for Divider
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Import Riverpod
import 'package:assiist_front_end/providers/auth_providers.dart'; // Import providers
import 'package:assiist_front_end/core/models/contact.dart';
import 'package:assiist_front_end/theme/app_styles.dart';
// Import widgets we'll reuse later
import 'package:assiist_front_end/widgets/kpi_widget.dart';
import 'package:assiist_front_end/widgets/task_item.dart';
import 'package:assiist_front_end/widgets/draft_item.dart'; // ADDED Import for DraftItem
import 'package:url_launcher/url_launcher.dart'; // ADD url_launcher import
// import 'package:assiist_front_end/widgets/draft_item.dart'; // REMOVE DraftItem import - Already added above, removing duplicate if any
// IMPORT Models
import 'package:assiist_front_end/core/models/task.dart';
import 'package:assiist_front_end/core/models/note.dart'; // <<< Add Note import
import 'package:assiist_front_end/core/models/appointment.dart'; // <<< Add Appointment import
// import 'package:assiist_front_end/core/models/draft.dart'; // REMOVE Draft model import
import 'package:assiist_front_end/core/models/contact.dart'; // Ensure Contact model is imported
// IMPORT Widgets
import 'package:assiist_front_end/widgets/borderless_action_button.dart'; // Import new button
import 'dart:async'; // Needed for Future.delayed or other async ops potentially
// IMPORT Screens
import 'log_note_screen.dart'; // Import screen for navigation
import './task_screen.dart'; // IMPORT TaskScreen
// IMPORT Timeline package
import 'package:timeline_tile/timeline_tile.dart'; // Import TimelineTile
import 'package:intl/intl.dart'; // Import for date formatting
// IMPORT Providers
import 'package:assiist_front_end/providers/repository_providers.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart'; // <<< IMPORT Custom Exceptions
import 'message_draft_screen.dart'; // <<< ADD Import for MessageDraftScreen
import 'assistant_interface_screen.dart'; // Navigate to combined interface
// import 'package:assiist_front_end/providers/contact_providers.dart'; // <<< REMOVE non-existent import
import 'package:assiist_front_end/utils/navigation_helpers.dart'; // ADDED IMPORT
import 'package:assiist_front_end/widgets/app_segmented_toggle.dart';
import 'package:assiist_front_end/providers/metrics_providers.dart';
import 'dart:ui';
import 'package:assiist_front_end/widgets/control_center_nav_bar.dart'; // Import the extracted widget
import 'package:assiist_front_end/widgets/share_assiist_contact_record.dart'; // Import the new widget
import 'edit_contact_screen.dart'; // Import EditContactScreen
import 'package:assiist_front_end/providers/reservation_providers.dart'; // Import reservation providers
import 'package:flutter/services.dart'; // Add for Clipboard
import 'package:assiist_front_end/widgets/select_or_add_contact.dart'; // ADDED for modal
import 'package:assiist_front_end/widgets/vip_components.dart'; // Import VIP components
import 'package:assiist_front_end/providers/vip_providers.dart'; // Import VIP providers
import 'package:assiist_front_end/widgets/linkable_text.dart'; // Import LinkableText for clickable attachment links
import 'package:cloud_firestore/cloud_firestore.dart'; // ✅ NEW: Firebase imports
import 'package:firebase_core/firebase_core.dart';
import 'package:assiist_front_end/providers/monitoring_providers.dart'; // ✅ NEW: Monitoring service
import 'package:assiist_front_end/widgets/nav_bar_back_button.dart'; // Import centralized back button
import 'package:assiist_front_end/widgets/feedback_bar.dart'; // Import Feedback Bar widget

// Provider for fetching a single contact by ID
final contactByIdProvider = FutureProvider.family<Contact?, String>((
  ref,
  contactId,
) async {
  final contactRepository = ref.watch(contactRepositoryProvider);
  // contactRepository.getContactById is expected to return Future<Contact?>
  return await contactRepository.getContactById(contactId);
});

// --- NEW: State Provider for Task Filter --- //
final contactTaskFilterProvider = StateProvider<bool>(
  (ref) => false,
); // false = Pending, true = Completed

// --- NEW: State Provider for Message Filter --- //
final contactMessageFilterProvider = StateProvider.autoDispose<bool>(
  (ref) => false,
); // false = Drafts, true = Sent

// --- NEW: Define Timeline Event Types ---
enum TimelineEventType {
  // Past
  noteAdded, // Logged Interaction
  messageSent,
  taskCompleted,
  appointmentHeld,
  // Future
  scheduledMessage,
  scheduledTask,
  scheduledAppointment,
}

// Helper to get display properties for each type
class TimelineEventDisplayProps {
  final String shortLabel;
  final IconData icon;

  TimelineEventDisplayProps({required this.shortLabel, required this.icon});

  static Map<TimelineEventType, TimelineEventDisplayProps> props = {
    TimelineEventType.noteAdded: TimelineEventDisplayProps(
      shortLabel: 'Note',
      icon: CupertinoIcons.doc_text_fill,
    ),
    TimelineEventType.messageSent: TimelineEventDisplayProps(
      shortLabel: 'Msg',
      icon: CupertinoIcons.paperplane_fill,
    ),
    TimelineEventType.taskCompleted: TimelineEventDisplayProps(
      shortLabel: 'Task',
      icon: CupertinoIcons.check_mark_circled_solid,
    ),
    TimelineEventType.appointmentHeld: TimelineEventDisplayProps(
      shortLabel: 'Appt',
      icon: CupertinoIcons.calendar_badge_plus,
    ),
    TimelineEventType.scheduledMessage: TimelineEventDisplayProps(
      shortLabel: 'Msg',
      icon: CupertinoIcons.paperplane_fill,
    ),
    TimelineEventType.scheduledTask: TimelineEventDisplayProps(
      shortLabel: 'Task',
      icon: CupertinoIcons.check_mark_circled_solid,
    ),
    TimelineEventType.scheduledAppointment: TimelineEventDisplayProps(
      shortLabel: 'Appt',
      icon: CupertinoIcons.calendar_badge_plus,
    ),
  };
}
// --- END NEW ---

// Define a simple class for timeline events (can be moved later)
class TimelineEvent {
  final String id;
  final DateTime timestamp;
  final String description;
  final TimelineEventType type;
  final dynamic details; // Add this field to store the full details

  TimelineEvent({
    required this.id,
    required this.timestamp,
    required this.description,
    required this.type,
    this.details, // Make it optional
  });

  // Helper to get display properties based on type
  TimelineEventDisplayProps get displayProps =>
      TimelineEventDisplayProps.props[type]!;
}

// Add at the top with other providers
final timelineTabProvider = StateProvider<int>(
  (ref) => 0,
); // 0 = Upcoming, 1 = Past

// Add at the top with other providers
final timelineItemDetailsCacheProvider = StateProvider<Map<String, dynamic>>(
  (ref) => {},
);

// Convert to ConsumerStatefulWidget to fetch contact data if only ID is provided
class ContactRecordScreen extends ConsumerStatefulWidget {
  final Contact? contact; // Made nullable
  final String? contactId; // New optional parameter

  // Deep Link Parameters
  final bool expandAllDetailsInitially;
  final bool scrollToDetailsSection;

  // Keys for scrolling and accordions - can remain if needed
  final GlobalKey _detailsSectionKey = GlobalKey();
  final _isRelationshipExpanded = ValueNotifier<bool>(false);
  final _isPersonalExpanded = ValueNotifier<bool>(false);
  final _isBusinessExpanded = ValueNotifier<bool>(false);

  ContactRecordScreen({
    super.key,
    this.contact, // Made nullable
    this.contactId,
    this.expandAllDetailsInitially = false,
    this.scrollToDetailsSection = false,
  }) : assert(
         contact != null || contactId != null,
         'Either contact or contactId must be provided.',
       ),
       super() {
    // Ensure super constructor is called correctly for const constructor
    // Initialize accordion states based on deep link param in constructor
    if (expandAllDetailsInitially) {
      _isPersonalExpanded.value = true;
      _isRelationshipExpanded.value = true;
      _isBusinessExpanded.value = true;
    }

    // Schedule scroll action if triggered by deep link
    // This needs to be in didChangeDependencies or similar for StatefulWidget
    // or handled carefully if still intended here with a check for mounted state.
  }

  @override
  _ContactRecordScreenState createState() => _ContactRecordScreenState();
}

class _ContactRecordScreenState extends ConsumerState<ContactRecordScreen>
    with WidgetsBindingObserver {
  // Removed: _contactData, _isLoading, _error
  // Removed: _fetchContactDetails method
  bool _isSavingModalContact = false; // ADDED: For modal save state

  // ✅ NEW: Service-based monitoring (no local state needed)

  _ContactRecordScreenState() {
    // Remove debug print
  }

  @override
  void initState() {
    super.initState();
    // Remove debug print
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Remove debug print

    if (widget.scrollToDetailsSection && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget._detailsSectionKey.currentContext != null) {
          Scrollable.ensureVisible(
            widget._detailsSectionKey.currentContext!,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            alignment: 0.0,
          );
        }
      });
    }

    // ✅ Minimal navigation detection to trigger rebuild
    final route = ModalRoute.of(context);
    // Remove debug prints

    if (route != null && route.isCurrent) {
      final contactId = widget.contact?.id ?? widget.contactId;
      // Remove debug prints

      // Force a rebuild to ensure _buildContent gets called with ref.watch()
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            // This empty setState will trigger a rebuild,
            // which will call _buildContent with ref.watch()
          });

          // Also invalidate the provider to force fresh creation
          if (contactId != null) {
            // Remove debug print
            ref.invalidate(contactMonitoringStateProvider(contactId));
          }
        }
      });
    }

    // Add observer for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ✅ NEW: WidgetsBindingObserver method to detect app state changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Remove debug prints
    if (state == AppLifecycleState.resumed) {
      // Remove debug print
    }
  }

  // --- ADDED: Handle Save New Contact from Modal ---
  Future<void> _handleSaveNewContactFromModal(
    Map<String, String> newContactDetails,
  ) async {
    // Basic Validation (mimicking DashboardScreen's save)
    final firstName = newContactDetails['firstName'] ?? '';
    // For this modal, we might make phone/email optional or handle validation differently
    // For now, let's assume firstName is the primary concern for quick add.
    if (firstName.isEmpty) {
      _showErrorDialog(context, 'Please enter at least a First Name.');
      return;
    }

    setState(() => _isSavingModalContact = true);
    Navigator.pop(
      context,
    ); // Close the modal immediately, show activity on main screen or via snackbar

    try {
      final contactRepo = ref.read(contactRepositoryProvider);
      final emailsList =
          (newContactDetails['email']?.isNotEmpty ?? false)
              ? [EmailAddress(address: newContactDetails['email']!)]
              : <EmailAddress>[];
      final phonesList =
          (newContactDetails['phone']?.isNotEmpty ?? false)
              ? [PhoneNumber(number: newContactDetails['phone']!)]
              : <PhoneNumber>[];

      final newContact = Contact(
        id: DateTime.now().millisecondsSinceEpoch.toString(), // Temporary ID
        first_name: firstName,
        last_name:
            newContactDetails['lastName']?.isEmpty ?? true
                ? null
                : newContactDetails['lastName'],
        addressed_as:
            newContactDetails['addressedAs']?.isEmpty ?? true
                ? null
                : newContactDetails['addressedAs'],
        business_name:
            newContactDetails['company']?.isEmpty ?? true
                ? null
                : newContactDetails['company'], // 'company' from getNewContactDetails
        business_type:
            newContactDetails['businessType']?.isEmpty ?? true
                ? null
                : newContactDetails['businessType'],
        emails: emailsList.isNotEmpty ? emailsList : null,
        phone_numbers: phonesList.isNotEmpty ? phonesList : null,
        isVip:
            newContactDetails['isVip']?.toLowerCase() ==
            'true', // Support VIP creation
        is_deleted: false,
        // created_on, updated_on are handled by backend
      );

      final createdContact = await contactRepo.createContact(newContact);

      // --- NEW: Trigger Update Assistant to organize brain-dump notes ---
      final relationshipInfo = newContactDetails['relationshipInfo'] ?? '';
      if (relationshipInfo.trim().isNotEmpty) {
        final preface =
            'Initial brain dump about ${createdContact.displayName} and our relationship so the AI assistant has complete context:\n\n';
        final noteToSend = preface + relationshipInfo.trim();
        try {
          final updateAssistantRepo = ref.read(
            updateAssistantRepositoryProvider,
          );
          await updateAssistantRepo.updateAssistant(
            contactId: createdContact.id,
            rawNoteContent: noteToSend,
          );
        } catch (e) {
          // Non-fatal: log and continue
          print('Warning: Failed to send Update Assistant request: $e');
        }
      }

      ref.invalidate(dashboardTasksProvider); // General refresh
      ref.invalidate(dashboardDraftsProvider);
      // Potentially invalidate other list providers if they exist

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${createdContact.displayName} created successfully!',
            ),
          ),
        );
        // Navigate to the new contact's record screen
        Navigator.of(context).pushReplacement(
          // Use pushReplacement if coming from another contact's screen
          CupertinoPageRoute(
            builder: (_) => ContactRecordScreen(contact: createdContact),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog(
          context,
          'Failed to create contact: ${e is ApiException ? e.message : e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingModalContact = false);
      }
    }
  }
  // --- END ---

  // ✅ Service handles all monitoring - no manual methods needed

  // Helper methods will now take Contact as a parameter
  String _getInitials(Contact contact) {
    String initials = "";
    if (contact.first_name?.isNotEmpty ?? false) {
      initials += contact.first_name![0];
    }
    if (contact.last_name?.isNotEmpty ?? false) {
      initials += contact.last_name![0];
    }
    return initials.isEmpty ? "?" : initials.toUpperCase();
  }

  // ADDED HELPER METHOD for launching URLs
  Future<void> _launchUrlHelper(BuildContext context, String urlString) async {
    Uri uri = Uri.parse(urlString);
    // Prepend https:// if no scheme is present, common for user-inputted websites/profiles
    if (!uri.hasScheme) {
      uri = Uri.parse('https://$urlString');
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        // Check if the widget is still in the tree
        _showErrorDialog(context, 'Could not launch ${uri.toString()}');
      }
    }
  }

  // ADDED HELPER METHOD for formatting date strings
  String? _formatDateString(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;
    try {
      // Try parsing as a full date first (e.g., "YYYY-MM-DDTHH:mm:ssZ" or "YYYY-MM-DD")
      final DateTime dateTime = DateTime.parse(dateString);
      // Check if the dateString seems to be date-only
      if (dateString.length == 10 && dateString.contains('-')) {
        return DateFormat.yMMMMd().format(dateTime); // "Month Day, Year"
      }
      // If it parsed but might have time, and we only want date:
      return DateFormat.yMMMMd().format(
        dateTime,
      ); // Default to "Month Day, Year" for full dates
    } catch (e) {
      // If full parsing fails, try specific formats like "MM-DD"
      try {
        if (RegExp(r'^\d{2}-\d{2}$').hasMatch(dateString)) {
          // "01-15"
          final parts = dateString.split('-');
          // Use a non-leap year (e.g., 2001) for consistent MMMM d formatting
          final tempDate = DateTime(
            2001,
            int.parse(parts[0]),
            int.parse(parts[1]),
          );
          return DateFormat.MMMMd().format(tempDate); // "January 15"
        }
        // Example: check for "MMM d" format like "Jan 15"
        if (RegExp(r'^[a-zA-Z]{3} \d{1,2}$').hasMatch(dateString)) {
          final monthDayFormat = DateFormat('MMM d');
          try {
            final parsedMonthDay = monthDayFormat.parse(dateString);
            final tempDate = DateTime(
              2001,
              parsedMonthDay.month,
              parsedMonthDay.day,
            );
            return DateFormat.MMMMd().format(tempDate);
          } catch (parseError) {
            // fallback
          }
        }
      } catch (e2) {
        print("Error parsing specific date format '$dateString': $e2");
      }
      // If all parsing fails, return the original string
      print(
        "Could not parse date string '$dateString', returning original. Error: $e",
      );
      return dateString;
    }
  }

  void _showActionSheet(BuildContext context, WidgetRef ref, Contact contact) {
    showCupertinoModalPopup(
      context: context,
      builder:
          (BuildContext ctx) => CupertinoActionSheet(
            actions: <CupertinoActionSheetAction>[
              if (contact.phone_numbers?.isNotEmpty ?? false)
                CupertinoActionSheetAction(
                  child: const Text('Call Primary Phone'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _callContact(context, contact);
                  },
                ),
              if (contact.phone_numbers?.isNotEmpty ?? false)
                CupertinoActionSheetAction(
                  child: const Text('Message Primary Phone'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _messageContact(context, contact);
                  },
                ),
              if (contact.emails?.isNotEmpty ?? false)
                CupertinoActionSheetAction(
                  child: const Text('Email Primary Address'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _emailContact(context, contact);
                  },
                ),
              CupertinoActionSheetAction(
                child: const Text('Edit Contact'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _editContact(context, ref, contact);
                },
              ),
              CupertinoActionSheetAction(
                isDestructiveAction: true,
                child: const Text('Delete Contact'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showDeleteConfirmationDialog(context, ref, contact);
                },
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
    );
  }

  Future<void> _handleDelete(
    WidgetRef ref,
    BuildContext context,
    Contact contact,
  ) async {
    print("Attempting to delete contact ID: ${contact.id}");
    bool deletedSuccessfully = false;
    try {
      final contactRepo = ref.read(contactRepositoryProvider);
      deletedSuccessfully = await contactRepo.deleteContact(contact.id);
      if (deletedSuccessfully && context.mounted) {
        ref.invalidate(contactRepositoryProvider); // General invalidation
        ref.invalidate(dashboardTasksProvider); // Refresh dashboard tasks
        // Invalidate any specific contact list providers if they exist
        // e.g., ref.invalidate(allContactsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${contact.displayName} deleted.')),
        );
        Navigator.of(
          context,
        ).popUntil((route) => route.isFirst); // Pop to dashboard
      } else if (context.mounted) {
        throw Exception(
          "Deletion failed on the backend or context became invalid.",
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error deleting contact: ${e.message}")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("An unexpected error occurred: $e")),
        );
      }
    }
  }

  Future<void> _callContact(BuildContext context, Contact contact) async {
    final phoneNumber = contact.phone_numbers?.firstOrNull?.number;
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        _showErrorDialog(context, 'No phone number available.');
      }
    } else {
      _showErrorDialog(context, 'No phone number available.');
    }
  }

  Future<void> _messageContact(BuildContext context, Contact contact) async {
    final phoneNumber = contact.phone_numbers?.firstOrNull?.number;
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      final Uri launchUri = Uri(scheme: 'sms', path: phoneNumber);
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        _showErrorDialog(context, 'Could not open messaging app.');
      }
    } else {
      _showErrorDialog(context, 'No phone number available.');
    }
  }

  Future<void> _emailContact(BuildContext context, Contact contact) async {
    final emailAddress = contact.emails?.firstOrNull?.address;
    if (emailAddress != null && emailAddress.isNotEmpty) {
      final Uri launchUri = Uri(scheme: 'mailto', path: emailAddress);
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        _showErrorDialog(context, 'Could not open email app.');
      }
    } else {
      _showErrorDialog(context, 'No email address available.');
    }
  }

  void _editContact(BuildContext context, WidgetRef ref, Contact contact) {
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => EditContactScreen(contact: contact)),
    );
  }

  Future<void> _showDeleteConfirmationDialog(
    BuildContext context,
    WidgetRef ref,
    Contact contact,
  ) async {
    final bool? confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder:
          (context) => CupertinoAlertDialog(
            title: const Text('Delete Contact'),
            content: Text(
              'Are you sure you want to delete ${contact.displayName}?\\nThis action cannot be undone.',
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('Cancel'),
                onPressed: () => Navigator.pop(context, false),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                child: const Text('Delete'),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      await _handleDelete(ref, context, contact);
    }
  }

  Future<void> _toggleTaskCompletion(
    Task task,
    WidgetRef ref,
    BuildContext itemBuildContext,
    Contact contactForContext,
  ) async {
    print(
      "[ContactRecordScreen] _toggleTaskCompletion entered for task: ${task.id}, title: ${task.title}, type: ${task.type}, status: ${task.status}",
    );

    if (task.id == null || task.contactId == null) {
      print("Error: Cannot toggle task without ID or Contact ID.");
      _showErrorDialog(
        itemBuildContext,
        "Cannot toggle task: missing required information.",
      );
      return;
    }

    // If task is already completed, just mark it as pending
    if (task.status == 'completed') {
      final Map<String, dynamic> updates = {'status': 'pending'};
      try {
        final taskRepo = ref.read(taskRepositoryProvider);
        final updatedTask = await taskRepo.updateTask(
          task.id,
          contactForContext.id,
          updates,
        );
        if (updatedTask == null)
          throw Exception("Task update failed on the backend.");

        ref.invalidate(timelineEventsForContactProvider(contactForContext.id));
        ref.invalidate(tasksForContactProvider(contactForContext.id));
        ref.invalidate(dashboardTasksProvider);
      } on ApiException catch (e) {
        _showErrorDialog(itemBuildContext, "Error updating task: ${e.message}");
      } catch (e) {
        _showErrorDialog(itemBuildContext, "An unexpected error occurred: $e");
      }
      return;
    }

    // For non-message tasks, navigate to LogNoteScreen first only if the task is not already completed
    if (task.type != 'message' && task.status != 'completed') {
      // Use the helper method to create the minimal contact
      final Contact? initialContact =
          NavigationHelpers.createMinimalContactFromTask(task);

      // Navigate to LogNoteScreen
      final bool? logSuccess = await Navigator.of(itemBuildContext).push<bool>(
        CupertinoPageRoute(
          builder:
              (_) => LogNoteScreen(
                initialContact: initialContact,
                taskToModify: task,
                isCompleting: true,
                hideContactSelector: true,
                completedTaskNotes: NavigationHelpers.buildCompletedTaskNotes(
                  task,
                ),
              ),
        ),
      );

      // Only proceed with task completion if note was logged successfully
      if (logSuccess != true) {
        return;
      }

      // ✅ TRIGGER MONITORING: Start monitoring when returning from LogNoteScreen
      final contactId = contactForContext.id;

      // Force provider disposal and recreation
      ref.invalidate(contactMonitoringStateProvider(contactId));

      // Now watch it to create fresh instance
      ref.watch(contactMonitoringStateProvider(contactId));
    }

    // Now mark the task as complete
    final Map<String, dynamic> updates = {'status': 'completed'};
    try {
      final taskRepo = ref.read(taskRepositoryProvider);
      final updatedTask = await taskRepo.updateTask(
        task.id,
        contactForContext.id,
        updates,
      );
      if (updatedTask == null)
        throw Exception("Task update failed on the backend.");

      ref.invalidate(timelineEventsForContactProvider(contactForContext.id));
      ref.invalidate(tasksForContactProvider(contactForContext.id));
      ref.invalidate(dashboardTasksProvider);
    } on ApiException catch (e) {
      _showErrorDialog(itemBuildContext, "Error updating task: ${e.message}");
    } catch (e) {
      _showErrorDialog(itemBuildContext, "An unexpected error occurred: $e");
    }
  }

  Future<void> _showTimelineEventDetails(
    BuildContext context,
    WidgetRef ref,
    TimelineEvent event,
    Contact contactForContext,
  ) async {
    // Check cache first
    final cache = ref.read(timelineItemDetailsCacheProvider);
    if (cache.containsKey(event.id)) {
      // Use showCupertinoModalPopup for bottom sheet
      showCupertinoModalPopup(
        context: context,
        builder: (BuildContext sheetContext) {
          // Pass a new context for the sheet
          return _buildTimelineEventDetailsSheet(
            sheetContext,
            cache[event.id],
            event.type,
          );
        },
      );
      return;
    }

    // If not in cache, show loading and fetch
    // Show a more subtle loading indicator, perhaps integrated or just proceed quickly.
    // For simplicity, existing dialog for loading is kept, but could be changed.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CupertinoActivityIndicator()),
    );

    try {
      dynamic itemDetails;
      switch (event.type) {
        case TimelineEventType.noteAdded:
          itemDetails = await ref
              .read(noteRepositoryProvider)
              .getNoteById(contactForContext.id, event.id);
          break;
        case TimelineEventType.taskCompleted:
        case TimelineEventType.scheduledTask:
        case TimelineEventType.messageSent:
        case TimelineEventType.scheduledMessage:
          itemDetails = await ref
              .read(taskRepositoryProvider)
              .getById(event.id, contactForContext.id);
          break;
        case TimelineEventType.appointmentHeld:
        case TimelineEventType.scheduledAppointment:
          itemDetails = await ref
              .read(appointmentRepositoryProvider)
              .getAppointmentById(event.id);
          break;
      }

      if (context.mounted) Navigator.of(context).pop(); // Close loading

      if (itemDetails != null && context.mounted) {
        // Cache the details
        ref.read(timelineItemDetailsCacheProvider.notifier).state = {
          ...cache,
          event.id: itemDetails,
        };

        // Use showCupertinoModalPopup for bottom sheet
        showCupertinoModalPopup(
          context: context,
          builder: (BuildContext sheetContext) {
            // Pass a new context for the sheet
            return _buildTimelineEventDetailsSheet(
              sheetContext,
              itemDetails,
              event.type,
            );
          },
        );
      } else if (context.mounted) {
        _showErrorDialog(context, "Could not load item details.");
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop(); // Close loading
      if (context.mounted)
        _showErrorDialog(context, "Failed to load details: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // If a contact object is passed directly, use it.
    if (widget.contact != null) {
      return _buildContent(context, widget.contact!);
    }

    // Otherwise, if only contactId is provided, fetch using the provider.
    if (widget.contactId != null) {
      final asyncContact = ref.watch(contactByIdProvider(widget.contactId!));
      return asyncContact.when(
        data: (contactData) {
          // contactData is now Contact?
          if (contactData == null) {
            // Handle case where contact is not found (null)
            return CupertinoPageScaffold(
              navigationBar: CupertinoNavigationBar(
                middle: Text('Contact Not Found'),
              ),
              child: Center(
                child: Text('The requested contact could not be found.'),
              ),
            );
          }
          return _buildContent(context, contactData); // Pass non-null Contact
        },
        loading:
            () => const CupertinoPageScaffold(
              navigationBar: CupertinoNavigationBar(
                middle: Text('Loading Contact...'),
              ),
              child: Center(child: CupertinoActivityIndicator()),
            ),
        error:
            (err, stack) => CupertinoPageScaffold(
              navigationBar: CupertinoNavigationBar(middle: Text('Error')),
              child: Center(child: Text('Failed to load contact: $err')),
            ),
      );
    }

    // Fallback if neither contact nor contactId is provided (should not happen due to assert)
    return const CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text('Error')),
      child: Center(child: Text('Contact information is missing.')),
    );
  }

  // Extracted content building logic into a separate method
  Widget _buildContent(BuildContext context, Contact contact) {
    // Listen to timeline provider to invalidate details cache on refresh.
    // This ensures that when the list of timeline events is re-fetched (e.g., after
    // completing a task), any cached details for those events are cleared,
    // preventing stale data from being shown in the details popup.
    ref.listen<AsyncValue<List<TimelineEvent>>>(
      timelineEventsForContactProvider(contact.id),
      (previous, next) {
        if (!next.isLoading && next.hasValue) {
          ref.invalidate(timelineItemDetailsCacheProvider);
        }
      },
    );

    // ✅ Silent monitoring - no user feedback, just provider invalidation
    // Remove debug prints

    // ✅ CRITICAL: Use ref.watch to ensure the provider stays alive
    final monitoringState = ref.watch(
      contactMonitoringStateProvider(contact.id),
    );
    // Remove debug print

    ref.listen(contactMonitoringStateProvider(contact.id), (previous, next) {
      // Remove debug prints

      if (previous != null && next != null) {
        final newCompletions =
            next.recentCompletions
                .where(
                  (completion) =>
                      !previous.recentCompletions.contains(completion),
                )
                .toList();

        // Remove debug print

        for (final completion in newCompletions) {
          // Remove debug print
          // Silently invalidate providers based on operation type
          for (final providerName in completion.providersToInvalidate) {
            // Remove debug print
            switch (providerName) {
              case 'tasksForContactProvider':
                ref.invalidate(tasksForContactProvider(contact.id));
                break;
              case 'dashboardTasksProvider':
                ref.invalidate(dashboardTasksProvider);
                break;
              case 'notesForContactProvider':
                ref.invalidate(notesForContactProvider(contact.id));
                break;
              case 'timelineEventsForContactProvider':
                ref.invalidate(timelineEventsForContactProvider(contact.id));
                break;
              case 'contactByIdProvider':
                ref.invalidate(contactByIdProvider(contact.id));
                break;
            }
          }
        }
      }
    });

    final initials = _getInitials(contact);
    // The trailing menu for Edit/Delete
    final Widget trailingMenu = CupertinoButton(
      padding: EdgeInsets.zero,
      child: AppStyles.accentIcon(icon: CupertinoIcons.ellipsis),
      onPressed: () {
        showCupertinoModalPopup(
          context: context,
          builder:
              (BuildContext ctx) => CupertinoActionSheet(
                actions: <CupertinoActionSheetAction>[
                  CupertinoActionSheetAction(
                    child: const Text('Edit Contact'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _editContact(context, ref, contact);
                    },
                  ),
                ],
                cancelButton: CupertinoActionSheetAction(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
        );
      },
    );

    return CupertinoPageScaffold(
      backgroundColor: AppStyles.subtleBackgroundColor(context),
      navigationBar: CupertinoNavigationBar(
        leading: const NavBarBackButton(),
        middle: ShareAssiistContactRecord(
          contact: contact,
          onShare: () {
            // Handle share action if needed
            ref.invalidate(contactMetricsProvider(contact.id));
          },
        ),
        trailing: trailingMenu,
      ),
      child: Stack(
        children: [
          SafeArea(
            child: CustomScrollView(
              controller: ScrollController(),
              slivers: [
                CupertinoSliverRefreshControl(
                  onRefresh: () async {
                    ref.invalidate(contactMetricsProvider(contact.id));
                    ref.invalidate(tasksForContactProvider(contact.id));
                    ref.invalidate(
                      notesForContactProvider(contact.id),
                    ); // FIXED: Add notes refresh
                    ref.invalidate(
                      timelineEventsForContactProvider(contact.id),
                    );
                    ref.invalidate(dashboardTasksProvider);
                    ref.invalidate(dashboardDraftsProvider);
                  },
                ),
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.only(
                      top: 8.0,
                      bottom: 36.0,
                      left: 16.0,
                      right: 16.0,
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // VIP Badge Row
                        Row(
                          children: [
                            Spacer(),
                            Consumer(
                              builder: (context, ref, child) {
                                // Watch the VIP notifier state to get real-time VIP status
                                final vipState = ref.watch(
                                  vipContactNotifierProvider,
                                );

                                // Determine current VIP status - use updated state if available, otherwise fallback to contact
                                bool currentVipStatus = contact.isVip;
                                if (vipState.hasValue &&
                                    vipState.value != null) {
                                  currentVipStatus = vipState.value!.isVip;
                                }

                                return TappableVipBadge(
                                  isVip: currentVipStatus,
                                  size: 16,
                                  showWhenNotVip: true,
                                  onTap:
                                      vipState.isLoading
                                          ? null
                                          : () async {
                                            try {
                                              await ref
                                                  .read(
                                                    vipContactNotifierProvider
                                                        .notifier,
                                                  )
                                                  .toggleVipStatus(
                                                    contact.id,
                                                    currentVipStatus,
                                                  );
                                            } catch (e) {
                                              _showErrorDialog(
                                                context,
                                                'Failed to update VIP status: $e',
                                              );
                                            }
                                          },
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8.0),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Spacer(flex: 1),
                              CircleAvatar(
                                radius: 40,
                                backgroundColor: CupertinoColors.systemGrey4
                                    .resolveFrom(context),
                                child: Text(
                                  initials,
                                  style: TextStyle(
                                    fontSize: 36.0,
                                    fontWeight: FontWeight.w400,
                                    color: AppStyles.prominentTextColor(
                                      context,
                                    ),
                                  ),
                                ),
                              ),
                              Spacer(flex: 1),
                            ],
                          ),
                        ),
                        // Contact Name - centered
                        Text(
                          contact.displayName,
                          style: AppStyles.h1TextStyle(context),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16.0),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Consumer(
                              builder: (context, ref, child) {
                                final metricsAsync = ref.watch(
                                  contactMetricsProvider(contact.id),
                                );
                                return metricsAsync.when(
                                  data:
                                      (metrics) => KpiWidget(
                                        label: 'notes',
                                        value: '${metrics?.notesLogged ?? 0}',
                                      ),
                                  loading:
                                      () => const KpiWidget(
                                        label: 'notes',
                                        value: '...',
                                      ),
                                  error:
                                      (_, __) => const KpiWidget(
                                        label: 'notes',
                                        value: '0',
                                      ),
                                );
                              },
                            ),
                            const SizedBox(width: 24.0),
                            KpiWidget(
                              label: 'days since\nlast contacted',
                              value: contact.lastContactedDays,
                            ),
                            const SizedBox(width: 24.0),
                            Consumer(
                              builder: (context, ref, child) {
                                final draftsAsync = ref.watch(
                                  dashboardDraftsProvider,
                                );
                                return draftsAsync.when(
                                  data: (drafts) {
                                    final contactDrafts =
                                        drafts
                                            .where(
                                              (draft) =>
                                                  draft.contactId == contact.id,
                                            )
                                            .length;
                                    return KpiWidget(
                                      label: 'drafts',
                                      value: '$contactDrafts',
                                    );
                                  },
                                  loading:
                                      () => const KpiWidget(
                                        label: 'drafts',
                                        value: '...',
                                      ),
                                  error:
                                      (_, __) => const KpiWidget(
                                        label: 'drafts',
                                        value: '0',
                                      ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // General Info & Details
                SliverToBoxAdapter(
                  key: widget._detailsSectionKey, // Access GlobalKey via widget
                  child: CupertinoListSection.insetGrouped(
                    backgroundColor: AppStyles.subtleBackgroundColor(
                      context,
                    ).withOpacity(0.0),
                    margin: const EdgeInsets.all(16.0).copyWith(top: 0),
                    children: <Widget>[
                      if (contact.addressed_as != null &&
                          contact.addressed_as!.isNotEmpty)
                        CupertinoListTile(
                          leading: AppStyles.accentIcon(
                            icon: CupertinoIcons.text_bubble,
                          ),
                          title: Text(
                            'Addressed As',
                            style: AppStyles.h2TextStyle(context).copyWith(
                              color: AppStyles.primaryTextColor(context),
                            ),
                          ),
                          additionalInfo: Text(
                            contact.addressed_as!,
                            style: AppStyles.bodyTextStyle(context),
                          ),
                        ),

                      // MODIFIED: Display all phone numbers
                      if (contact.phone_numbers?.isNotEmpty ?? false)
                        ...contact.phone_numbers!.map((phone) {
                          return CupertinoListTile(
                            leading: AppStyles.accentIcon(
                              icon: CupertinoIcons.phone,
                            ),
                            title: Text(
                              phone.label ?? 'Phone',
                              style: AppStyles.h2TextStyle(context).copyWith(
                                color: AppStyles.primaryTextColor(context),
                              ),
                            ),
                            additionalInfo: Text(
                              phone.number ?? 'N/A',
                              style: AppStyles.bodyTextStyle(context),
                            ),
                            onTap: () async {
                              if (phone.number != null &&
                                  phone.number!.isNotEmpty) {
                                final Uri launchUri = Uri(
                                  scheme: 'tel',
                                  path: phone.number,
                                );
                                if (await canLaunchUrl(launchUri)) {
                                  await launchUrl(launchUri);
                                } else {
                                  _showErrorDialog(
                                    context,
                                    'Could not open phone dialer.',
                                  );
                                }
                              } else {
                                _showErrorDialog(
                                  context,
                                  'No phone number available.',
                                );
                              }
                            },
                          );
                        }).toList(),

                      // MODIFIED: Display all email addresses
                      if (contact.emails?.isNotEmpty ?? false)
                        ...contact.emails!.map((email) {
                          return CupertinoListTile(
                            leading: AppStyles.accentIcon(
                              icon: CupertinoIcons.mail,
                            ),
                            title: Text(
                              email.label ?? 'Email',
                              style: AppStyles.h2TextStyle(context).copyWith(
                                color: AppStyles.primaryTextColor(context),
                              ),
                            ),
                            additionalInfo: Text(
                              email.address ?? 'N/A',
                              style: AppStyles.bodyTextStyle(context),
                            ),
                            onTap: () async {
                              if (email.address != null &&
                                  email.address!.isNotEmpty) {
                                final Uri launchUri = Uri(
                                  scheme: 'mailto',
                                  path: email.address,
                                );
                                if (await canLaunchUrl(launchUri)) {
                                  await launchUrl(launchUri);
                                } else {
                                  _showErrorDialog(
                                    context,
                                    'Could not open email app.',
                                  );
                                }
                              } else {
                                _showErrorDialog(
                                  context,
                                  'No email address available.',
                                );
                              }
                            },
                          );
                        }).toList(),

                      if (contact.business_name != null &&
                          contact.business_name!.isNotEmpty)
                        CupertinoListTile(
                          leading: AppStyles.accentIcon(
                            icon: CupertinoIcons.building_2_fill,
                          ),
                          title: Text(
                            'Business',
                            style: AppStyles.h2TextStyle(context).copyWith(
                              color: AppStyles.primaryTextColor(context),
                            ),
                          ),
                          additionalInfo: Text(
                            contact.business_name!,
                            style: AppStyles.bodyTextStyle(context),
                          ),
                        ),
                      if (contact.addresses?.isNotEmpty ?? false)
                        ...contact.addresses!.map((address) {
                          // Display all addresses
                          return CupertinoListTile(
                            leading: AppStyles.accentIcon(
                              icon: CupertinoIcons.map_pin,
                            ),
                            title: Text(
                              address.label ?? 'Address',
                              style: AppStyles.h2TextStyle(context).copyWith(
                                color: AppStyles.primaryTextColor(context),
                              ),
                            ),
                            additionalInfo: Text(
                              '${address.street ?? ''} ${address.city ?? ''} ${address.state ?? ''} ${address.zip ?? ''}'
                                  .trim()
                                  .replaceAll(RegExp(r'\s+'), ' '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppStyles.bodyTextStyle(context),
                            ),
                          );
                        }).toList(),

                      // REMOVED: Title (Job Title) from here, will be in Personal Details accordion
                      // if (contact.personal_details?.occupation != null && contact.personal_details!.occupation!.isNotEmpty)
                      //   CupertinoListTile(
                      //     leading: const Icon(CupertinoIcons.tag),
                      //     title: Text('Title', style: AppStyles.h2TextStyle(context)),
                      //     additionalInfo: Text(contact.personal_details!.occupation!, style: AppStyles.bodyTextStyle(context)),
                      //   ),

                      // NOTE: Website field is omitted as it's not directly on the Contact model
                      // If contact.website existed:
                      // if (contact.website != null && contact.website!.isNotEmpty)
                      //   CupertinoListTile(
                      //     leading: const Icon(CupertinoIcons.globe),
                      //     title: Text('Website', style: AppStyles.h2TextStyle(context)),
                      //     additionalInfo: Text(
                      //       contact.website!,
                      //       style: AppStyles.bodyTextStyle(context).copyWith(color: CupertinoColors.activeBlue.resolveFrom(context)),
                      //       overflow: TextOverflow.ellipsis,
                      //     ),
                      //     onTap: () => _launchUrlHelper(context, contact.website!),
                      //   ),

                      // CORRECTED: Birthday from contact.date_of_birth
                      if (contact.date_of_birth != null)
                        CupertinoListTile(
                          leading: AppStyles.accentIcon(
                            icon: CupertinoIcons.gift,
                          ),
                          title: Text(
                            'Birthday',
                            style: AppStyles.h2TextStyle(context).copyWith(
                              color: AppStyles.primaryTextColor(context),
                            ),
                          ),
                          additionalInfo: Text(
                            DateFormat.yMMMMd().format(contact.date_of_birth!),
                            style: AppStyles.bodyTextStyle(context),
                          ),
                        ),

                      // NOTE: Anniversary field is omitted as it's not directly on the Contact model
                      // If contact.anniversary existed and was a DateTime:
                      // if (contact.anniversary != null)
                      //   CupertinoListTile(
                      //     leading: const Icon(CupertinoIcons.star),
                      //     title: Text('Anniversary', style: AppStyles.h2TextStyle(context)),
                      //     additionalInfo: Text(DateFormat.yMMMMd().format(contact.anniversary!), style: AppStyles.bodyTextStyle(context)),
                      //   ),
                      // If it was a String:
                      // if (contact.anniversary_string != null && contact.anniversary_string!.isNotEmpty)
                      //    CupertinoListTile(
                      //      leading: const Icon(CupertinoIcons.star),
                      //      title: Text('Anniversary', style: AppStyles.h2TextStyle(context)),
                      //      additionalInfo: Text(_formatDateString(contact.anniversary_string) ?? contact.anniversary_string!, style: AppStyles.bodyTextStyle(context)),
                      //    ),

                      // NOTE: Social media fields (LinkedIn, Twitter, Instagram, Facebook, TikTok) are omitted
                      // as they are not directly on the Contact model in a structured way.
                    ],
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 16.0),
                ), // Keep this spacer
                // RESTORED: Accordions
                SliverToBoxAdapter(
                  child: CupertinoListSection.insetGrouped(
                    backgroundColor: AppStyles.subtleBackgroundColor(
                      context,
                    ).withOpacity(0.0),
                    margin: const EdgeInsets.all(16.0).copyWith(top: 0),
                    children: <Widget>[
                      _buildAccordionSection(
                        title: 'Personal Details',
                        leadingIcon: CupertinoIcons.person,
                        isExpandedNotifier:
                            widget._isPersonalExpanded, // Access via widget
                        onExpansionChanged: (expanded) {
                          widget._isPersonalExpanded.value = expanded;
                        },
                        child: _buildPersonalDetailsContent(
                          context,
                          contact.personal_details,
                        ), // Pass contact.personal_details
                      ),
                      _buildAccordionSection(
                        title: 'Relationship Details',
                        leadingIcon: CupertinoIcons.heart,
                        isExpandedNotifier:
                            widget._isRelationshipExpanded, // Access via widget
                        onExpansionChanged: (expanded) {
                          widget._isRelationshipExpanded.value = expanded;
                        },
                        child: _buildRelationshipDetailsContent(
                          context,
                          contact.relationship_details,
                        ), // Pass contact.relationship_details
                      ),
                      _buildAccordionSection(
                        title: 'Business Opportunities',
                        leadingIcon: CupertinoIcons.briefcase,
                        isExpandedNotifier:
                            widget._isBusinessExpanded, // Access via widget
                        onExpansionChanged: (expanded) {
                          widget._isBusinessExpanded.value = expanded;
                        },
                        child: _buildBusinessDetailsContent(
                          context,
                          contact.business_details,
                        ), // Pass contact.business_details
                      ),
                    ],
                  ),
                ),
                // Messages Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      bottom: 8.0,
                      top: 16.0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: Text(
                            'Message Drafts',
                            style: AppStyles.h2TextStyle(context).copyWith(
                              color: AppStyles.primaryTextColor(context),
                            ),
                          ),
                        ),
                        AppSegmentedToggle<bool>(
                          options: const {false: 'Drafts', true: 'Sent'},
                          groupValue: ref.watch(contactMessageFilterProvider),
                          onValueChanged: (value) {
                            if (value != null)
                              ref
                                  .read(contactMessageFilterProvider.notifier)
                                  .state = value;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Divider(height: 1),
                  ),
                ),
                Consumer(
                  builder: (context, ref, child) {
                    final tasksAsyncValue = ref.watch(
                      tasksForContactProvider(contact.id),
                    ); // Use contact.id
                    return tasksAsyncValue.when(
                      loading:
                          () => const SliverToBoxAdapter(
                            child: Center(child: CupertinoActivityIndicator()),
                          ),
                      error:
                          (e, st) => SliverToBoxAdapter(
                            child: Center(
                              child: Text('Error loading messages: $e'),
                            ),
                          ),
                      data: (allTasks) {
                        final messageTasks =
                            allTasks
                                .where(
                                  (task) =>
                                      task.type == 'message' &&
                                      task.status ==
                                          (ref.watch(
                                                contactMessageFilterProvider,
                                              )
                                              ? 'completed'
                                              : 'pending') &&
                                      (task.actionableDate == null ||
                                          task.actionableDate!.isBefore(
                                            DateTime.now(),
                                          )),
                                )
                                .toList();
                        // Sort messageTasks
                        messageTasks.sort((a, b) {
                          DateTime? dateA, dateB;
                          if (ref.watch(contactMessageFilterProvider)) {
                            // completed
                            dateA = a.updatedOn ?? a.createdOn;
                            dateB = b.updatedOn ?? b.createdOn;
                          } else {
                            // pending
                            dateA = a.createdOn;
                            dateB = b.createdOn;
                          }
                          if (dateA == null && dateB == null) return 0;
                          if (dateA == null) return 1;
                          if (dateB == null) return -1;
                          return dateB.compareTo(dateA); // Descending
                        });
                        return SliverPadding(
                          padding: const EdgeInsets.only(
                            bottom: 16.0,
                            left: 16.0,
                            right: 16.0,
                            top: 8.0,
                          ),
                          sliver:
                              messageTasks.isEmpty
                                  ? SliverToBoxAdapter(
                                    child: _buildEmptyListPlaceholder(
                                      child: Text(
                                        ref.watch(contactMessageFilterProvider)
                                            ? 'No sent messages.'
                                            : "You're all caught up!",
                                        style: AppStyles.labelTextStyle(
                                          context,
                                        ),
                                      ),
                                    ),
                                  )
                                  : SliverList.builder(
                                    itemCount: messageTasks.length,
                                    itemBuilder: (context, index) {
                                      final task = messageTasks[index];
                                      return DraftItem(
                                        key: ValueKey('draft_msg_${task.id}'),
                                        task: task,
                                        showContactInSubtitle: false,
                                        onTap: () {
                                          Navigator.of(context).push(
                                            CupertinoPageRoute(
                                              builder:
                                                  (_) => MessageDraftScreen(
                                                    task: task,
                                                    hideContactLink: true,
                                                  ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                        );
                      },
                    );
                  },
                ),
                // Tasks Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      bottom: 8.0,
                      top: 16.0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: Text(
                            'Tasks',
                            style: AppStyles.h2TextStyle(context).copyWith(
                              color: AppStyles.primaryTextColor(context),
                            ),
                          ),
                        ),
                        AppSegmentedToggle<bool>(
                          options: const {false: 'Pending', true: 'Completed'},
                          groupValue: ref.watch(contactTaskFilterProvider),
                          onValueChanged: (value) {
                            if (value != null)
                              ref
                                  .read(contactTaskFilterProvider.notifier)
                                  .state = value;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Divider(height: 1),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  sliver: Consumer(
                    builder: (context, ref, child) {
                      final tasksAsyncValue = ref.watch(
                        tasksForContactProvider(contact.id),
                      ); // Use contact.id
                      return tasksAsyncValue.when(
                        loading:
                            () => const SliverToBoxAdapter(
                              child: Center(
                                child: CupertinoActivityIndicator(),
                              ),
                            ),
                        error:
                            (e, st) => SliverToBoxAdapter(
                              child: Center(
                                child: Text('Error loading tasks: $e'),
                              ),
                            ),
                        data: (allTasks) {
                          final genericTasks =
                              allTasks
                                  .where(
                                    (task) =>
                                        task.type == 'action' &&
                                        task.status ==
                                            (ref.watch(
                                                  contactTaskFilterProvider,
                                                )
                                                ? 'completed'
                                                : 'pending') &&
                                        (task.actionableDate == null ||
                                            task.actionableDate!.isBefore(
                                              DateTime.now(),
                                            )),
                                  )
                                  .toList();
                          // Sort genericTasks
                          genericTasks.sort((a, b) {
                            DateTime? dateA, dateB;
                            if (!ref.watch(contactTaskFilterProvider)) {
                              // pending
                              int dueDateComparison = 0;
                              if (a.dueDate != null && b.dueDate != null)
                                dueDateComparison = a.dueDate!.compareTo(
                                  b.dueDate!,
                                );
                              else if (a.dueDate != null)
                                dueDateComparison = -1;
                              else if (b.dueDate != null)
                                dueDateComparison = 1;
                              if (dueDateComparison != 0)
                                return dueDateComparison;
                              dateA = a.createdOn;
                              dateB =
                                  b.createdOn; // Fallback to createdOn descending for pending
                              if (dateA == null && dateB == null) return 0;
                              if (dateA == null) return 1;
                              if (dateB == null) return -1;
                              return dateB.compareTo(
                                dateA,
                              ); // CreatedOn descending for pending
                            } else {
                              // completed
                              dateA = a.updatedOn ?? a.createdOn;
                              dateB = b.updatedOn ?? b.createdOn;
                              if (dateA == null && dateB == null) return 0;
                              if (dateA == null) return 1;
                              if (dateB == null) return -1;
                              return dateB.compareTo(
                                dateA,
                              ); // Descending for completed
                            }
                          });
                          return SliverList(
                            delegate:
                                genericTasks.isEmpty
                                    ? SliverChildListDelegate([
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 16.0,
                                          right: 16.0,
                                          top: 8.0,
                                        ),
                                        child: _buildEmptyListPlaceholder(
                                          child: Text(
                                            ref.watch(contactTaskFilterProvider)
                                                ? 'No completed tasks.'
                                                : "You're all caught up!",
                                            style: AppStyles.labelTextStyle(
                                              context,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ])
                                    : SliverChildBuilderDelegate((
                                      context,
                                      index,
                                    ) {
                                      final task = genericTasks[index];
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          left: 16.0,
                                          right: 16.0,
                                          top: 8.0,
                                        ),
                                        child: TaskItem(
                                          key: ValueKey('task_${task.id}'),
                                          task: task,
                                          showContactInSubtitle: false,
                                          onTap:
                                              () =>
                                                  _handleTaskTap(task, context),
                                          onStatusToggle:
                                              (tappedTask) =>
                                                  _toggleTaskCompletion(
                                                    tappedTask,
                                                    ref,
                                                    context,
                                                    contact,
                                                  ), // Pass contact
                                        ),
                                      );
                                    }, childCount: genericTasks.length),
                          );
                        },
                      );
                    },
                  ),
                ),
                // Timeline Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      bottom: 8.0,
                      top: 16.0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: Text(
                            'Timeline',
                            style: AppStyles.h2TextStyle(context).copyWith(
                              color: AppStyles.primaryTextColor(context),
                            ),
                          ),
                        ),
                        AppSegmentedToggle<int>(
                          options: const {0: 'Upcoming', 1: 'Past'},
                          groupValue: ref.watch(timelineTabProvider),
                          onValueChanged: (value) {
                            if (value != null) {
                              ref.read(timelineTabProvider.notifier).state =
                                  value;
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Divider(height: 1),
                  ),
                ),
                Consumer(
                  builder: (context, ref, child) {
                    final timelineAsyncValue = ref.watch(
                      timelineEventsForContactProvider(contact.id),
                    );
                    final tab = ref.watch(timelineTabProvider);
                    return timelineAsyncValue.when(
                      loading:
                          () => const SliverToBoxAdapter(
                            child: Center(child: CupertinoActivityIndicator()),
                          ),
                      error:
                          (e, st) => SliverToBoxAdapter(
                            child: Container(
                              margin: const EdgeInsets.all(16.0),
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: CupertinoColors.systemRed.withOpacity(
                                  0.1,
                                ),
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(
                                  color: CupertinoColors.systemRed.withOpacity(
                                    0.3,
                                  ),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    CupertinoIcons.exclamationmark_triangle,
                                    color: CupertinoColors.systemRed,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Error loading timeline:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: CupertinoColors.systemRed,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$e',
                                    style: AppStyles.bodyTextStyle(context),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      data: (events) {
                        if (events.isEmpty) {
                          return SliverToBoxAdapter(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  'No timeline events yet',
                                  style: AppStyles.bodyTextStyle(context),
                                ),
                              ),
                            ),
                          );
                        }

                        final now = DateTime.now();
                        final upcomingEvents =
                            events.where((event) {
                              final isUpcoming =
                                  ((event.type ==
                                              TimelineEventType
                                                  .scheduledMessage ||
                                          event.type ==
                                              TimelineEventType
                                                  .scheduledTask) &&
                                      event.timestamp.isAfter(now)) ||
                                  ((event.type ==
                                              TimelineEventType
                                                  .scheduledAppointment ||
                                          event.type ==
                                              TimelineEventType
                                                  .appointmentHeld) &&
                                      event.timestamp.isAfter(now));
                              return isUpcoming;
                            }).toList();

                        final pastEvents =
                            events
                                .where(
                                  (event) =>
                                      event.type ==
                                          TimelineEventType.messageSent ||
                                      event.type ==
                                          TimelineEventType.taskCompleted ||
                                      event.type ==
                                          TimelineEventType.noteAdded ||
                                      ((event.type ==
                                                  TimelineEventType
                                                      .scheduledAppointment ||
                                              event.type ==
                                                  TimelineEventType
                                                      .appointmentHeld) &&
                                          event.timestamp.isBefore(now)),
                                )
                                .toList();

                        pastEvents.sort(
                          (a, b) => b.timestamp.compareTo(a.timestamp),
                        );
                        upcomingEvents.sort(
                          (a, b) => a.timestamp.compareTo(b.timestamp),
                        );
                        final selectedEvents =
                            tab == 0 ? upcomingEvents : pastEvents;

                        return SliverList(
                          delegate: SliverChildListDelegate(
                            selectedEvents.isEmpty
                                ? [
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                      tab == 0
                                          ? 'No upcoming events.'
                                          : 'No past events.',
                                      style: AppStyles.bodyTextStyle(context),
                                    ),
                                  ),
                                ]
                                : _buildTimelineSliverListContent(
                                  selectedEvents,
                                  context,
                                  isUpcoming: tab == 0,
                                  ref: ref,
                                  contactForContext: contact,
                                ),
                          ),
                        );
                      },
                    );
                  },
                ),
                // Add bottom padding to account for the ControlCenterNavBar
                const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 100.0,
                  ), // ControlCenterNavBar is 84px + extra clearance
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              // Ensures nav bar content isn't obscured by system UI
              top:
                  false, // Don't apply safe area to top for this positioned widget
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ControlCenterNavBar(
                    showCalendarButton: false, // MODIFIED: Hide calendar button
                    onCalendarTap: () {
                      // Handle Calendar action (currently hidden)
                    },
                    onAssistantTap: () async {
                      // Remove debug print
                      final result = await Navigator.of(context).push(
                        CupertinoPageRoute(
                          builder:
                              (_) => AssistantInterfaceScreen(
                                initialContact: contact,
                              ),
                        ),
                      );
                      // Remove debug print
                      // Monitoring handled in build method
                    },
                    onAddContactTap: () {
                      // MODIFIED: Show modal for adding contact
                      showCupertinoModalPopup(
                        context: context,
                        builder: (modalContext) {
                          return CupertinoPopupSurface(
                            // Using CupertinoPopupSurface for standard modal appearance
                            child: Material(
                              // Material widget needed for some theming/layout within Cupertino modal
                              color: AppStyles.subtleBackgroundColor(
                                modalContext,
                              ), // Match theme
                              child: SafeArea(
                                // SafeArea for content within the modal
                                top: false,
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: SingleChildScrollView(
                                    // Ensure content is scrollable if it overflows
                                    child: SelectOrAddContact(
                                      initialIsAdding: true,
                                      showCreateButton:
                                          true, // Show the "Create Contact" button inside the form
                                      showSearchField:
                                          false, // ADDED: Hide search field in modal
                                      onSaveAttempt: (details) {
                                        // Modal is dismissed by _handleSaveNewContactFromModal before it starts async work.
                                        _handleSaveNewContactFromModal(details);
                                      },
                                      onContactSelected: (selectedContact) {
                                        // If a contact is somehow selected from this "add-focused" modal,
                                        // just pop the modal. Main use case here is adding.
                                        Navigator.pop(modalContext);
                                        // Optionally, navigate to the selected contact if that's desired
                                        // Navigator.of(context).push(CupertinoPageRoute(builder: (_) => ContactRecordScreen(contact: selectedContact)));
                                      },
                                      onAddModeToggled: (isAdding) {
                                        // If user explicitly cancels add mode (e.g. by clearing search and not adding)
                                        if (!isAdding) {
                                          Navigator.pop(modalContext);
                                        }
                                      },
                                      // No need for onNavigateToSelectedContact from this modal context
                                      // No need for onCreateContactButtonPressed (using onSaveAttempt)
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  FeedbackBar(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- MOVED UI BUILDER HELPER METHODS INSIDE THE STATE CLASS --- //

  // Helper for empty list placeholders
  Widget _buildEmptyListPlaceholder({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
      child: Center(
        child:
            child is Text && child.data == "You're all caught up!"
                ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppStyles.accentIcon(
                      icon: CupertinoIcons.check_mark_circled_solid,
                      size: 18.0,
                    ),
                    const SizedBox(width: 8),
                    child,
                  ],
                )
                : child,
      ),
    );
  }

  // Helper for Accordion Sections
  Widget _buildAccordionSection({
    required String title,
    required IconData leadingIcon,
    required ValueNotifier<bool> isExpandedNotifier,
    required ValueChanged<bool> onExpansionChanged,
    required Widget child,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable: isExpandedNotifier,
      builder: (context, isExpanded, _) {
        // Custom Cupertino-styled accordion with EXACT same styling as CupertinoListTile
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row - recreate CupertinoListTile exactly
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => onExpansionChanged(!isExpanded),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 11.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 22.0),
                      child: AppStyles.accentIcon(
                        icon: leadingIcon,
                        size: 24.0,
                      ),
                    ),
                    const SizedBox(width: 18.0),
                    Expanded(
                      child: Text(
                        title,
                        style: AppStyles.h2TextStyle(
                          context,
                        ).copyWith(color: AppStyles.primaryTextColor(context)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 15.0),
                      child: AppStyles.accentIcon(
                        icon:
                            isExpanded
                                ? CupertinoIcons.chevron_up
                                : CupertinoIcons.chevron_down,
                        size: 16.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Content section with animation
            ClipRect(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: isExpanded ? null : 0,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 50.0, // 15 (left padding) + 20 (icon) + 15 (spacing)
                    right: 15.0,
                    bottom: 16.0,
                  ),
                  child: DefaultTextStyle(
                    style: AppStyles.bodyTextStyle(context),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Helper to build Relationship Details content
  Widget _buildRelationshipDetailsContent(
    BuildContext context,
    Map<String, RelationshipDetail>? detailsMap,
  ) {
    if (detailsMap == null || detailsMap.isEmpty) {
      return Text(
        'No relationship details provided.',
        style: AppStyles.labelTextStyle(context),
      );
    }
    final userEntries = detailsMap.entries.toList();

    // Build copy text
    final List<String> copyParts = [];
    for (final entry in userEntries) {
      final userId = entry.key;
      final detail = entry.value;
      final userName = 'User $userId';
      copyParts.add(
        '$userName:\n${detail.details ?? 'No specific details.'}\n',
      );
    }
    final copyText = copyParts.join('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              child: AppStyles.accentIcon(
                icon: CupertinoIcons.doc_on_doc,
                size: 20.0,
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copyText));
                showCupertinoDialog(
                  context: context,
                  builder:
                      (dialogContext) => Container(
                        height: MediaQuery.of(dialogContext).size.height,
                        child: Align(
                          alignment: Alignment(0.0, -0.5),
                          child: CupertinoAlertDialog(
                            title: const Text('Copied for Quick Export'),
                            content: const Text(
                              'Content copied for Quick Export',
                            ),
                            actions: [
                              CupertinoDialogAction(
                                child: const Text('OK'),
                                onPressed: () => Navigator.pop(dialogContext),
                              ),
                            ],
                          ),
                        ),
                      ),
                );
              },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List<Widget>.generate(userEntries.length, (index) {
              final entry = userEntries[index];
              final detail = entry.value;
              return Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: Text(
                  detail.details ?? 'No specific details.',
                  style: AppStyles.bodyTextStyle(context),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // Helper to build Personal Details content
  Widget _buildPersonalDetailsContent(
    BuildContext context,
    PersonalDetails? details,
  ) {
    if (details == null) {
      return Text(
        'No personal details provided.',
        style: AppStyles.labelTextStyle(context),
      );
    }
    final fields = {
      'Occupation': details.occupation,
      'Family': details.family,
      'Recreation': details.recreation,
      'Dreams': details.dreams,
      'Additional Info': details.additional_info,
    };
    final validEntries =
        fields.entries
            .where((entry) => entry.value != null && entry.value!.isNotEmpty)
            .toList();
    if (validEntries.isEmpty) {
      return Text(
        'No personal details provided.',
        style: AppStyles.labelTextStyle(context),
      );
    }

    // Build copy text
    final List<String> copyParts = [];
    for (final entry in validEntries) {
      copyParts.add('${entry.key}: ${entry.value}');
    }
    final copyText = copyParts.join('\n\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              child: AppStyles.accentIcon(
                icon: CupertinoIcons.doc_on_doc,
                size: 20.0,
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copyText));
                showCupertinoDialog(
                  context: context,
                  builder:
                      (dialogContext) => Container(
                        height: MediaQuery.of(dialogContext).size.height,
                        child: Align(
                          alignment: Alignment(0.0, -0.5),
                          child: CupertinoAlertDialog(
                            title: const Text('Copied for Quick Export'),
                            content: const Text(
                              'Content copied for Quick Export',
                            ),
                            actions: [
                              CupertinoDialogAction(
                                child: const Text('OK'),
                                onPressed: () => Navigator.pop(dialogContext),
                              ),
                            ],
                          ),
                        ),
                      ),
                );
              },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List<Widget>.generate(validEntries.length, (index) {
              final entry = validEntries[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${entry.key}: ',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(
                        text: entry.value,
                        style: AppStyles.bodyTextStyle(context),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // Helper to build Business Details content
  Widget _buildBusinessDetailsContent(
    BuildContext context,
    BusinessDetails? details,
  ) {
    final opportunities =
        details?.opportunities ?? []; // Use the new list and default to empty
    if (opportunities.isEmpty) {
      return Text(
        'No business details provided.',
        style: AppStyles.labelTextStyle(context),
      );
    }

    // Build copy text
    final List<String> copyParts = [];
    for (final opportunity in opportunities) {
      if (opportunity.opportunity_description != null &&
          opportunity.opportunity_description!.isNotEmpty) {
        copyParts.add('Opportunity: ${opportunity.opportunity_description}');
      }
      if (opportunity.latest_development != null &&
          opportunity.latest_development!.isNotEmpty) {
        copyParts.add('Development: ${opportunity.latest_development}');
      }
    }
    final copyText = copyParts.join('\n\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              child: AppStyles.accentIcon(
                icon: CupertinoIcons.doc_on_doc,
                size: 20.0,
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copyText));
                showCupertinoDialog(
                  context: context,
                  builder:
                      (dialogContext) => Container(
                        height: MediaQuery.of(dialogContext).size.height,
                        child: Align(
                          alignment: Alignment(0.0, -0.5),
                          child: CupertinoAlertDialog(
                            title: const Text('Copied for Quick Export'),
                            content: const Text(
                              'Content copied for Quick Export',
                            ),
                            actions: [
                              CupertinoDialogAction(
                                child: const Text('OK'),
                                onPressed: () => Navigator.pop(dialogContext),
                              ),
                            ],
                          ),
                        ),
                      ),
                );
              },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List<Widget>.generate(opportunities.length, (index) {
              final opportunity = opportunities[index]!;
              final description = opportunity.opportunity_description;
              final development = opportunity.latest_development;
              final contentWidgets = <Widget>[];
              if (description != null && description.isNotEmpty) {
                contentWidgets.add(
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Opportunity: ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: description,
                            style: AppStyles.bodyTextStyle(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              if (development != null && development.isNotEmpty) {
                if (contentWidgets.isNotEmpty)
                  contentWidgets.add(const SizedBox(height: 4.0));
                contentWidgets.add(
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Development: ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: development,
                            style: AppStyles.bodyTextStyle(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...contentWidgets,
                  if (index < opportunities.length - 1)
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: CupertinoColors.systemGrey4.resolveFrom(context),
                    ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  // Modified _buildTimelineSliverListContent to accept contactForContext
  List<Widget> _buildTimelineSliverListContent(
    List<TimelineEvent> events,
    BuildContext context, {
    required bool isUpcoming,
    required WidgetRef ref,
    required Contact contactForContext,
  }) {
    final Color connectorColor = CupertinoColors.separator
        .resolveFrom(context)
        .withOpacity(0.5);
    const double lineXPosition = 0.1;
    return List<Widget>.generate(events.length, (index) {
      final event = events[index];
      final displayProps = event.displayProps;
      bool isFirst = index == 0;
      bool isLast = index == events.length - 1;
      return Padding(
        padding: const EdgeInsets.only(left: 16.0, right: 16.0),
        child: TimelineTile(
          alignment: TimelineAlign.manual,
          lineXY: lineXPosition,
          isFirst: isFirst,
          isLast: isLast,
          beforeLineStyle: LineStyle(
            color: isFirst ? Colors.transparent : connectorColor,
            thickness: 1,
          ),
          afterLineStyle: LineStyle(
            color: isLast ? Colors.transparent : connectorColor,
            thickness: 1,
          ),
          indicatorStyle: IndicatorStyle(
            width: 35,
            height: 35,
            padding: const EdgeInsets.all(8),
            indicator: Container(
              decoration: BoxDecoration(
                color: AppStyles.cardBackgroundColor(context),
                shape: BoxShape.circle,
                border: Border.all(color: connectorColor, width: 1),
              ),
              child: Center(
                child:
                    isUpcoming
                        ? AppStyles.accentIcon(
                          icon: displayProps.icon,
                          size: 15,
                        )
                        : AppStyles.accentIcon(
                          icon: displayProps.icon,
                          size: 15,
                        ),
              ),
            ),
          ),
          endChild: GestureDetector(
            onTap: () {
              _showTimelineEventDetails(context, ref, event, contactForContext);
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 60),
              padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.description,
                    style: AppStyles.h3TextStyle(
                      context,
                    ).copyWith(color: AppStyles.primaryTextColor(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4.0),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppStyles.captionAccentText(
                        context,
                        displayProps.shortLabel,
                      ),
                      const SizedBox(width: 6.0),
                      if (!isUpcoming) ...[
                        AppStyles.accentIcon(
                          icon: CupertinoIcons.clock,
                          size: 13,
                        ),
                        const SizedBox(width: 4.0),
                        Text(
                          DateFormat.yMd().add_jm().format(event.timestamp),
                          style: AppStyles.captionTextStyle(context),
                        ),
                      ] else ...[
                        Text(
                          _getUpcomingDatePrefix(event.type),
                          style: AppStyles.captionTextStyle(
                            context,
                          ).copyWith(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 4.0),
                        Text(
                          // Show only date for future tasks
                          (event.type == TimelineEventType.scheduledMessage ||
                                  event.type == TimelineEventType.scheduledTask)
                              ? DateFormat.yMd().format(event.timestamp)
                              : DateFormat.yMd().add_jm().format(
                                event.timestamp,
                              ),
                          style: AppStyles.captionTextStyle(context),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  String _getUpcomingDatePrefix(TimelineEventType type) {
    switch (type) {
      case TimelineEventType.scheduledTask:
        return 'Due:';
      case TimelineEventType.scheduledMessage:
        return 'Send by:';
      case TimelineEventType.scheduledAppointment:
        return 'Date:';
      default:
        return '';
    }
  }

  void _handleTaskTap(Task task, BuildContext context) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => TaskScreen(task: task, hideContactLink: true),
      ),
    );
  }

  void _showErrorDialog(BuildContext context, String message) {
    if (!context.mounted) return;
    showCupertinoDialog(
      context: context,
      builder:
          (context) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text(message),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                child: const Text('OK'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
    );
  }

  Widget _buildTimelineEventDetailsSheet(
    BuildContext sheetContext, // Renamed context for clarity
    dynamic itemDetails,
    TimelineEventType type,
  ) {
    // String title = "Details"; // Title can be integrated into the sheet if needed
    String? contentToCopy;
    Widget contentWidget; // Renamed from 'content' to avoid conflict

    // Logic to build contentWidget and contentToCopy based on itemDetails type
    // This is the same core logic as in the original _buildDetailsDialog
    if (itemDetails is Note) {
      // Show processed content if available, otherwise show raw
      final String displayContent =
          itemDetails.processedNote?.body ?? itemDetails.rawNote;
      contentToCopy = displayContent;

      // Build copy content with key points if available
      if (itemDetails.processedNote?.keyPoints.isNotEmpty == true) {
        final keyPointsText = itemDetails.processedNote!.keyPoints
            .map((point) => '• $point')
            .join('\n');
        contentToCopy = '$displayContent\n\nKey Points:\n$keyPointsText';
      }

      contentWidget = SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Show processed content if available, otherwise show raw
            if (itemDetails.processedNote != null) ...[
              Text(
                'Processed Note',
                style: AppStyles.labelTextStyle(
                  sheetContext,
                ).copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              LinkableText(
                text: itemDetails.processedNote!.body,
                style: AppStyles.bodyTextStyle(sheetContext),
              ),

              if (itemDetails.processedNote!.keyPoints.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Key Points:',
                  style: AppStyles.labelTextStyle(
                    sheetContext,
                  ).copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                ...itemDetails.processedNote!.keyPoints.map(
                  (point) => Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• ',
                          style: AppStyles.bodyTextStyle(sheetContext),
                        ),
                        Expanded(
                          child: Text(
                            point,
                            style: AppStyles.bodyTextStyle(sheetContext),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              // Show original note in expandable section
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: CupertinoColors.systemGrey4.resolveFrom(
                      sheetContext,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ExpansionTile(
                  title: Text(
                    'Original Note',
                    style: AppStyles.labelTextStyle(sheetContext),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: LinkableText(
                        text: itemDetails.rawNote,
                        style: AppStyles.bodyTextStyle(sheetContext),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                'Note',
                style: AppStyles.labelTextStyle(
                  sheetContext,
                ).copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              LinkableText(
                text: itemDetails.rawNote,
                style: AppStyles.bodyTextStyle(sheetContext),
              ),
            ],

            if (itemDetails.createdOn != null) ...[
              const SizedBox(height: 8),
              Text(
                "Created: ${DateFormat.yMd().add_jm().format(itemDetails.createdOn!)}",
                style: AppStyles.labelTextStyle(sheetContext),
              ),
            ],
          ],
        ),
      );
      if (itemDetails.createdOn != null) {
        contentToCopy =
            "${contentToCopy ?? "(empty note)"}\n\nCreated: ${DateFormat.yMd().add_jm().format(itemDetails.createdOn!)}";
      }
    } else if (itemDetails is Task) {
      // title = itemDetails.type == 'message' ? "Message Details" : "Task Details";
      final DateTime? relevantTimestamp =
          itemDetails.status == 'completed'
              ? (itemDetails.completedOn ??
                  itemDetails.updatedOn ??
                  itemDetails.createdOn)
              : (itemDetails.dueDate ?? itemDetails.actionableDate);
      final String datePrefix =
          itemDetails.status == 'completed'
              ? (itemDetails.type == 'message' ? "Sent: " : "Completed: ")
              : (itemDetails.type == 'message' ? "Send by: " : "Due: ");

      final List<String> copyParts = [];
      copyParts.add(itemDetails.title);
      String bodyOrDescription =
          itemDetails.body ?? itemDetails.description ?? "";
      if (bodyOrDescription.isNotEmpty) {
        copyParts.add('\n\n$bodyOrDescription');
      }
      if (relevantTimestamp != null) {
        copyParts.add(
          '\n\n$datePrefix${DateFormat.yMd().add_jm().format(relevantTimestamp)}',
        );
      }
      contentToCopy = copyParts.join('');

      contentWidget = SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              itemDetails.title,
              style: AppStyles.h3TextStyle(sheetContext),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (bodyOrDescription.isNotEmpty)
              Text(
                bodyOrDescription,
                style: AppStyles.bodyTextStyle(sheetContext),
                textAlign: TextAlign.center,
              )
            else if (itemDetails.type ==
                'message') // Explicitly handle empty message body
              Text(
                "(No message body)",
                style: AppStyles.labelTextStyle(
                  sheetContext,
                ).copyWith(fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 8),
            if (relevantTimestamp != null) ...[
              Text(
                "$datePrefix${DateFormat.yMd().add_jm().format(relevantTimestamp)}",
                style: AppStyles.labelTextStyle(sheetContext),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (itemDetails.type == 'message') {
                    Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder:
                            (_) => MessageDraftScreen(
                              task: itemDetails,
                              hideContactLink: true,
                            ),
                      ),
                    );
                  } else {
                    Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder:
                            (_) => TaskScreen(
                              task: itemDetails,
                              hideContactLink: true,
                            ),
                      ),
                    );
                  }
                },
                child: AppStyles.accentText(
                  sheetContext,
                  "View ${itemDetails.type == 'message' ? 'Message' : 'Task'} →",
                ),
              ),
            ],
          ],
        ),
      );
    } else if (itemDetails is Appointment) {
      // title = "Appointment Details";
      final List<String> copyParts = [];
      copyParts.add(itemDetails.title);
      if (itemDetails.description != null &&
          itemDetails.description!.isNotEmpty) {
        copyParts.add('\n\n${itemDetails.description}');
      }
      if (itemDetails.startTime != null) {
        copyParts.add(
          '\n\nStart: ${DateFormat.yMd().add_jm().format(itemDetails.startTime!)}',
        );
      }
      if (itemDetails.endTime != null) {
        copyParts.add(
          '\nEnd: ${DateFormat.yMd().add_jm().format(itemDetails.endTime!)}',
        );
      }
      if (itemDetails.location != null) {
        copyParts.add('\n\nLocation: ${itemDetails.location}');
      }
      contentToCopy = copyParts.join('');

      contentWidget = SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(itemDetails.title, style: AppStyles.h3TextStyle(sheetContext)),
            const SizedBox(height: 4),
            if (itemDetails.description != null &&
                itemDetails.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                child: Text(
                  itemDetails.description!,
                  style: AppStyles.bodyTextStyle(sheetContext),
                ),
              )
            else
              const SizedBox(height: 8.0),
            if (itemDetails.startTime != null)
              Text(
                "Start: ${DateFormat.yMd().add_jm().format(itemDetails.startTime!)}",
                style: AppStyles.labelTextStyle(sheetContext),
              ),
            if (itemDetails.endTime != null)
              Text(
                "End: ${DateFormat.yMd().add_jm().format(itemDetails.endTime!)}",
                style: AppStyles.labelTextStyle(sheetContext),
              ),
            if (itemDetails.location != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  "Location: ${itemDetails.location}",
                  style: AppStyles.labelTextStyle(sheetContext),
                ),
              ),
          ],
        ),
      );
    } else {
      contentWidget = const Text("No details available.");
    }

    final IconData itemIcon =
        TimelineEventDisplayProps.props[type]?.icon ??
        CupertinoIcons.question_circle;

    return Material(
      color: AppStyles.subtleBackgroundColor(
        sheetContext,
      ), // Changed background color
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20.0),
          topRight: Radius.circular(20.0),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 12.0),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey4.resolveFrom(
                      sheetContext,
                    ),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [AppStyles.accentIcon(icon: itemIcon, size: 28.0)],
              ),
              const SizedBox(height: 16.0),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      MediaQuery.of(sheetContext).size.height *
                      0.4, // Max 40% of screen height
                ),
                child:
                    contentWidget, // This is already a SingleChildScrollView where needed
              ),
              const SizedBox(height: 24.0),
              Row(
                children: [
                  if (contentToCopy != null && contentToCopy.isNotEmpty)
                    Expanded(
                      child: CupertinoButton(
                        color: CupertinoColors.systemGrey4,
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: contentToCopy!),
                          );
                          Navigator.pop(sheetContext);
                          showCupertinoDialog(
                            context: context,
                            builder:
                                (dialogContext) => Container(
                                  height:
                                      MediaQuery.of(dialogContext).size.height,
                                  child: Align(
                                    alignment: Alignment(0.0, -0.5),
                                    child: CupertinoAlertDialog(
                                      title: const Text(
                                        'Copied for Quick Export',
                                      ),
                                      content: const Text(
                                        'Content copied for Quick Export',
                                      ),
                                      actions: [
                                        CupertinoDialogAction(
                                          child: const Text('OK'),
                                          onPressed:
                                              () =>
                                                  Navigator.pop(dialogContext),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          );
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AppStyles.accentIcon(
                              icon: CupertinoIcons.doc_on_doc,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            AppStyles.accentText(sheetContext, "Copy"),
                          ],
                        ),
                      ),
                    ),
                  if (contentToCopy != null && contentToCopy.isNotEmpty)
                    const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton(
                      color: CupertinoColors.systemGrey4,
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AppStyles.accentIcon(
                            icon: CupertinoIcons.xmark,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          AppStyles.accentText(sheetContext, "Close"),
                        ],
                      ),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
