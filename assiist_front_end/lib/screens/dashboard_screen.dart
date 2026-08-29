import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // Using Material Icons as Cupertino doesn't have a full set
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Import Riverpod
import 'dart:ui'; // Import for ImageFilter
import 'package:assiist_front_end/providers/auth_providers.dart'; // Import providers
// Corrected imports using relative paths
// import 'package:assiist_front_end/widgets/contact_search_field.dart'; // REMOVE
import 'package:assiist_front_end/screens/log_note_screen.dart'; // Corrected path
import 'package:assiist_front_end/screens/settings_screen.dart'; // ADD import for SettingsScreen
import 'package:assiist_front_end/theme/app_styles.dart';
import 'package:assiist_front_end/core/models/contact.dart'; // Corrected path assuming lib/core/models
import 'package:assiist_front_end/core/models/task.dart'; // IMPORT centralized model
// import 'package:assiist_front_end/core/models/draft.dart'; // REMOVE centralized model
// import 'package:assiist_front_end/widgets/add_contact_form.dart'; // REMOVE
import 'package:assiist_front_end/widgets/select_or_add_contact.dart'; // IMPORT new widget
import 'package:assiist_front_end/screens/quick_message_screen.dart'; // ADD import for GetDraftScreen
// IMPORT New Widgets
import 'package:assiist_front_end/widgets/kpi_widget.dart';
import 'package:assiist_front_end/widgets/task_item.dart';
import 'package:assiist_front_end/widgets/draft_item.dart'; // ADD Import for the new DraftItem
import 'package:assiist_front_end/widgets/slidable_pending_contact_item.dart'; // CORRECTED Import path
import 'package:assiist_front_end/screens/contact_record_screen.dart'; // ADD import for ContactRecordScreen
import 'package:assiist_front_end/widgets/borderless_action_button.dart'; // Import the reusable button
import 'package:assiist_front_end/screens/task_screen.dart'; // ADD import for TaskScreen
import 'package:assiist_front_end/screens/message_draft_screen.dart'; // <<< ADD Import for MessageDraftScreen
import 'package:assiist_front_end/providers/repository_providers.dart'; // Import repository providers
import 'package:assiist_front_end/core/errors/exceptions.dart'; // IMPORT custom exceptions
// import '../screens/contacts_screen.dart'; // REMOVE Non-existent import

import 'package:flutter_slidable/flutter_slidable.dart'; // <<< ADD Import for SlidableAutoCloseBehavior
import 'package:assiist_front_end/core/models/pending_contact.dart'; // <<<< ADD CORRECT IMPORT
import 'package:assiist_front_end/utils/navigation_helpers.dart'; // <<< IMPORT NavigationHelpers
import 'package:assiist_front_end/screens/assistant_interface_screen.dart';
import 'package:assiist_front_end/providers/metrics_providers.dart';
import 'package:assiist_front_end/widgets/control_center_nav_bar.dart'; // Import Control Center Nav Bar
import 'package:assiist_front_end/widgets/share_assiist_dashboard.dart'; // Import the dashboard-specific widget
import 'package:assiist_front_end/widgets/feedback_bar.dart'; // Import Feedback Bar widget
import 'package:assiist_front_end/utils/unfocus_helper.dart'; // Use UnfocusHelper instead of UnfocusScope
import 'package:assiist_front_end/screens/edit_contact_screen.dart'; // Import edit screen

// --- NEW: Dashboard Task Filter --- //
final dashboardTaskFilterProvider = StateProvider.autoDispose<bool>(
  (ref) => false, // false = Pending, true = Completed
);
// --- END Filter ---

enum InteractionType { inPerson, call, message, none }

// Change StatefulWidget to ConsumerStatefulWidget
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  // Update state type
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

// Change State to ConsumerState
class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with TickerProviderStateMixin {
  // --- Contact Search/Add State (REFACTORED) --- //
  // Contact? _selectedContact; // REMOVE
  // bool _showAddContactFields = false; // REMOVE (Managed by SelectOrAddContact)
  // String _currentSearchQuery = ''; // REMOVE
  Contact?
  _selectedContactForDashboard; // NEW: Holds the contact selected by the child
  final GlobalKey<SelectOrAddContactState> _selectOrAddContactKey =
      GlobalKey<SelectOrAddContactState>(); // NEW: Key for child access
  // --- Add State for Processing Items ---
  final Set<String> _itemsBeingProcessed = {};

  // ADD ScrollController
  final ScrollController _scrollController = ScrollController();

  // REMOVE Controllers for Add Contact fields
  // final _firstNameController = TextEditingController();
  // final _lastNameController = TextEditingController();
  // final _phoneController = TextEditingController();
  // final _emailController = TextEditingController();
  // final _businessTypeController = TextEditingController();
  // final _companyController = TextEditingController(); // TODO: Rename pending
  // final _addressedAsController = TextEditingController();
  // final _relationshipInfoController = TextEditingController();
  bool _isSaving = false; // Keep for save button state

  // REMOVE local _pendingContacts list
  // List<PendingContact> _pendingContacts = [];

  // Keep SlidableControllers, but logic will change in build method
  final Map<String, SlidableController> _slidableControllers = {};

  @override
  void initState() {
    super.initState();
    // No need to initialize dummy data or controllers here anymore
    // Controllers will be initialized in the build method as data loads
  }

  @override
  void dispose() {
    // Dispose controllers when screen disposes
    for (final controller in _slidableControllers.values) {
      controller.dispose();
    }
    _slidableControllers.clear();
    _scrollController.dispose(); // ADDED: Dispose scroll controller
    super.dispose();
  }

  // --- Task Completion --- //
  Future<void> _handleTaskCompletion(
    Task task,
    WidgetRef ref,
    BuildContext itemBuildContext,
  ) async {
    print(
      "[DashboardScreen] _handleTaskCompletion entered for task: ${task.id}, title: ${task.title}, type: ${task.type}, status: ${task.status}",
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
          task.id!,
          task.contactId!,
          updates,
        );
        if (updatedTask == null)
          throw Exception("Task update failed on the backend.");

        ref.invalidate(dashboardTasksProvider);
      } on ApiException catch (e) {
        _showErrorDialog(itemBuildContext, e.message ?? "Error updating task");
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
    }

    // Now mark the task as complete
    final Map<String, dynamic> updates = {'status': 'completed'};
    try {
      final taskRepo = ref.read(taskRepositoryProvider);
      final updatedTask = await taskRepo.updateTask(
        task.id!,
        task.contactId!,
        updates,
      );
      if (updatedTask == null)
        throw Exception("Task update failed on the backend.");

      ref.invalidate(dashboardTasksProvider);
    } on ApiException catch (e) {
      _showErrorDialog(itemBuildContext, e.message ?? "Error updating task");
    } catch (e) {
      _showErrorDialog(itemBuildContext, "An unexpected error occurred: $e");
    }
  }

  // ADD Helper for showing error dialog (can be reused)
  void _showErrorDialog(BuildContext context, String message) {
    // Ensure it runs after the build phase if called during submit
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showCupertinoDialog(
        context: context,
        builder: (BuildContext context) {
          return CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text(message),
            actions: <Widget>[
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    });
  }

  // --- Contact Selection Callback (Adapted) --- //
  void _onContactSelectedForDashboard(Contact contact) {
    // Update state with the selected contact from the child widget.
    setState(() {
      _selectedContactForDashboard = contact;
      // Child widget handles clearing search text internally
      // Add mode is also handled internally by child
    });
    print('Dashboard: Contact Selected via Callback - ${contact.displayName}');

    // Ensure keyboard is dismissed
    FocusScope.of(context).unfocus();
  }

  // --- REMOVED Contact Handlers --- //
  // void _handleContactSelection(Contact contact) { ... }
  // void _handleSearchTextChanged(String text) { ... }
  // void _handleToggleAddContact(bool isAdding) { ... }
  // void _clearAddContactFields() { ... }

  // --- NEW: Pending Contact Action Handlers --- //

  /// Handles the 'Ignore' action for a pending contact.
  void _handleIgnorePendingContact(
    BuildContext actionContext,
    PendingContact contact,
  ) async {
    final email = contact.email;
    final contactId = contact.id;

    if (_itemsBeingProcessed.contains(contactId)) {
      print(
        '[_handleIgnore] Action already in progress for $contactId. Ignoring.',
      );
      return;
    }

    if (email == null || email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(actionContext).showSnackBar(
          SnackBar(
            content: Text('Cannot ignore contact without an email.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    print('[_handleIgnore] Attempting to ignore $contactId for $email');
    final SlidableController? controller = _slidableControllers[contactId];

    setState(() {
      _itemsBeingProcessed.add(contactId);
    });

    bool success = false;
    String? errorMessage;
    try {
      final pendingContactRepo = ref.read(pendingContactRepositoryProvider);
      await pendingContactRepo.updatePendingContactStatus(contactId, 'ignored');
      success = true;
      print('[_handleIgnore] API call successful for $contactId');
    } on ApiException catch (e) {
      errorMessage = e.message;
      print(
        '[_handleIgnore] API call failed (ApiException) for $contactId: $e',
      );
    } catch (e) {
      errorMessage = 'An unexpected error occurred.';
      print(
        '[_handleIgnore] API call failed (Generic Exception) for $contactId: $e',
      );
    }

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;

        _itemsBeingProcessed.remove(contactId);

        if (success) {
          print(
            '[_handleIgnore] API success for $contactId. Ensuring controller is closed before invalidating.',
          );
          if (controller != null &&
              controller.actionPaneType.value != ActionPaneType.none) {
            try {
              print(
                '[_handleIgnore] Awaiting controller.close() for $contactId',
              );
              await controller.close();
              print('[_handleIgnore] Controller closed for $contactId');
            } catch (e) {
              print(
                '[_handleIgnore] Error closing controller for $contactId: $e (proceeding with invalidate)',
              );
            }
          }
          ref.invalidate(dashboardPendingContactsProvider);

          if (mounted) {
            // Attempt SnackBar
            try {
              ScaffoldMessenger.of(actionContext).showSnackBar(
                SnackBar(content: Text('$email added to ignore list.')),
              );
            } catch (e) {
              print(
                '[_handleIgnore] Error showing success SnackBar for $contactId: $e',
              );
            }
          }
        } else {
          setState(() {});
          if (mounted && errorMessage != null) {
            // Attempt SnackBar for error
            try {
              ScaffoldMessenger.of(actionContext).showSnackBar(
                SnackBar(
                  content: Text('Error ignoring $email: $errorMessage'),
                  backgroundColor: AppStyles.solidAccent,
                ),
              );
            } catch (e) {
              print(
                '[_handleIgnore] Error showing error SnackBar for $contactId: $e',
              );
            }
          }
        }
      });
    }
  }

  void _handleAddPendingContact(BuildContext actionContext, PendingContact pc) {
    print(
      "Adding pending contact: ${pc.displayName} (${pc.email ?? pc.phone}) with ID ${pc.id}",
    );
    if (pc.email == null) {
      _showErrorDialog(context, "Cannot add contact without an email address.");
      return;
    }

    _slidableControllers[pc.id]?.close();

    setState(() {
      _itemsBeingProcessed.add(pc.id);
    });

    // Now using NavigationHelpers and awaiting the result via .then()
    NavigationHelpers.navigateToLogNoteScreen<bool?>(
      context,
      potentialContactEmail: pc.email,
      appointmentTitle: pc.sourceEventTitle ?? pc.displayName,
      appointmentNotes: pc.appointmentNotes,
      appointmentTime: pc.appointmentTime,
      isRescheduled: pc.isRescheduled,
      originalAppointmentTime: pc.originalAppointmentTime,
      rescheduleReason: pc.rescheduleReason,
    ).then((success) async {
      if (!mounted) return;

      if (success == true) {
        // Mark the pending contact as added so it disappears from list
        bool statusUpdateSuccess = false;
        try {
          final repo = ref.read(pendingContactRepositoryProvider);
          await repo.updatePendingContactStatus(pc.id, 'added');
          statusUpdateSuccess = true;
          print(
            'Successfully updated pending contact status for ${pc.id} to added',
          );
        } catch (e) {
          print('Error updating pending contact status for ${pc.id}: $e');
          // Show error to user since this is a critical failure
          if (mounted) {
            ScaffoldMessenger.of(actionContext).showSnackBar(
              SnackBar(
                content: Text(
                  'Failed to update contact status. Please try again.',
                ),
                backgroundColor: AppStyles.solidAccent,
              ),
            );
          }
        }

        // Only refresh if the status update actually succeeded
        if (statusUpdateSuccess) {
          ref.invalidate(dashboardPendingContactsProvider);
          // Note: Don't immediately dispose the controller - let the natural cleanup
          // in _buildPendingContactsList handle it when the provider data refreshes
        }
      }

      // Always remove from processing set at the end, regardless of success/failure
      setState(() {
        _itemsBeingProcessed.remove(pc.id);
      });
    });
  }

  // --- Handler for tapping a slidable item using ID ---
  void _handlePendingContactTap(PendingContact contact) {
    if (_itemsBeingProcessed.contains(contact.id)) {
      print(
        "[_handlePendingContactTap] Item ${contact.id} is currently processing, tap ignored.",
      );
      return;
    }
    final controller = _slidableControllers[contact.id];
    if (controller != null) {
      if (controller.actionPaneType.value != ActionPaneType.none) {
        controller.close(); // If open, close it
      } else {
        controller.openEndActionPane(
          // If closed, open it
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } else {
      print(
        "[_handlePendingContactTap] Error: No controller found for ID ${contact.id} on tap.",
      );
    }
  }
  // --- END HANDLER ---

  // --- Save Contact Logic (MODIFIED to use GlobalKey) ---
  Future<void> _saveContact() async {
    final selectOrAddState = _selectOrAddContactKey.currentState;
    if (selectOrAddState == null) {
      print("Error: Could not access SelectOrAddContact state.");
      return; // Or show error dialog
    }

    // Get data using the child state's method
    final Map<String, String> newContactDetails =
        selectOrAddState.getNewContactDetails();

    // Basic Validation (using details from child)
    final firstName =
        newContactDetails['first_name'] ??
        ''; // ← FIXED: Use snake_case field name
    final phone = newContactDetails['phone'] ?? '';
    if (firstName.isEmpty || phone.isEmpty) {
      showCupertinoDialog(
        context: context,
        builder:
            (context) => CupertinoAlertDialog(
              title: const Text('Missing Information'),
              content: Text(
                'Please enter at least a First Name and Phone Number (required).',
              ),
              actions: [
                CupertinoDialogAction(
                  child: const Text('OK'),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final contactRepo = ref.read(contactRepositoryProvider); // Get repository

    try {
      // REMOVE: await Future.delayed(const Duration(seconds: 1));

      // Construct using data from the child widget
      final emailsList =
          (newContactDetails['email']?.isNotEmpty ?? false)
              ? [EmailAddress(address: newContactDetails['email']!)]
              : <EmailAddress>[];
      final phonesList = [
        PhoneNumber(number: phone), // Already validated non-empty
      ];

      // --- TODO: Update Contact creation to use ALL details from map ---
      final newContact = Contact(
        // Keep dummy ID for constructor, toJson() will ignore it
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        first_name: firstName,
        last_name:
            newContactDetails['last_name']?.isEmpty ??
                    true // ← FIXED: Use snake_case field name
                ? null
                : newContactDetails['last_name'], // ← FIXED: Use snake_case field name
        addressed_as:
            newContactDetails['addressed_as']?.isEmpty ??
                    true // ← FIXED: Use snake_case field name
                ? null
                : newContactDetails['addressed_as'], // ← FIXED: Use snake_case field name
        business_name:
            newContactDetails['business_name']?.isEmpty ??
                    true // ← FIXED: Use snake_case field name
                ? null
                : newContactDetails['business_name'], // ← FIXED: Use snake_case field name
        business_type:
            newContactDetails['business_type']?.isEmpty ??
                    true // ← FIXED: Use snake_case field name
                ? null
                : newContactDetails['business_type'], // ← FIXED: Use snake_case field name
        emails: emailsList,
        phone_numbers: phonesList,
        // TODO: Handle PersonalDetails, RelationshipDetails construction
        // personal_details: PersonalDetails(occupation: ...??...)
        // relationship_details: {userId: RelationshipDetail(details: newContactDetails['relationshipInfo'])}
        is_deleted: false, // New contacts are not deleted
        // created_on, updated_on, etc., are typically handled by the backend/repository
      );

      // Call the repository to create the contact via API
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
          // Log but do not block user flow
          print('Warning: Failed to send Update Assistant request: $e');
        }
      }

      print('API Save Successful: ${createdContact.displayName}');

      // Reset the child form state after successful save
      // selectOrAddState.resetForm(); // TODO: Implement or verify reset logic in SelectOrAddContact

      if (mounted) {
        // Show success actions using the actual contact returned from the API
        _showAddContactSuccessActions(
          createdContact,
          createdContact.displayName,
        );
      }
    } catch (e) {
      if (e is DuplicateContactException) {
        // Fetch the existing contact and navigate to edit screen
        try {
          final existing = await contactRepo.getContactById(
            e.existingContactId,
          );
          if (existing != null && mounted) {
            await showCupertinoDialog(
              context: context,
              builder:
                  (context) => CupertinoAlertDialog(
                    title: const Text('Contact Exists'),
                    content: Text(
                      'A contact with the same ${e.field} already exists. Would you like to edit the existing contact instead?',
                    ),
                    actions: [
                      CupertinoDialogAction(
                        child: const Text('Edit'),
                        onPressed: () {
                          Navigator.pop(context); // close dialog
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder:
                                  (_) => EditContactScreen(contact: existing),
                            ),
                          );
                        },
                      ),
                      CupertinoDialogAction(
                        child: const Text('Cancel'),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
            );
          }
        } catch (fetchErr) {
          print('Error fetching existing contact: $fetchErr');
        }
      } else {
        print('Error saving contact via API: $e');
        if (mounted) {
          showCupertinoDialog(
            context: context,
            builder:
                (context) => CupertinoAlertDialog(
                  title: const Text('Save Failed'),
                  content: Text(
                    'Could not save contact. Please check your connection and try again.\n${e is ApiException ? e.message : ''}',
                  ),
                  actions: [
                    CupertinoDialogAction(
                      child: const Text('OK'),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- Show Success Actions (Unchanged, receives Contact) ---
  void _showAddContactSuccessActions(Contact newContact, String displayName) {
    // ... (implementation remains the same) ...
  }

  // --- Placeholder Actions (Unchanged) ---
  void _sendVCard(Contact contact, String displayName) {
    // ...
  }

  // --- REMOVED Clear Add Contact Fields --- //
  // void _clearAddContactFields() { ... }

  // --- Quick Actions Menu --- (Update to read providers)
  void _showQuickActionsMenu(BuildContext context) {
    // Read providers here instead of using widget props
    final String? accessToken = ref.read(accessTokenProvider);
    final String? locationId = ref.read(locationIdProvider);

    showCupertinoModalPopup(
      context: context,
      builder:
          (context) => CupertinoActionSheet(
            actions: [
              CupertinoActionSheetAction(
                child: const Text('Quick Message'),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder:
                          (context) => GetDraftScreen(
                            // Remove the accessToken and locationId parameters
                            // accessToken: accessToken,
                            // locationId: locationId,
                          ),
                    ),
                  );
                },
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
          ),
    );
  }

  // --- Contact Navigation (Remove passing props) ---
  void _navigateToContact({Contact? contact}) {
    final targetContact = contact ?? _selectedContactForDashboard;
    if (targetContact != null) {
      print('Navigating to detail page for contact ID: ${targetContact.id}');
      Navigator.of(context).push(
        CupertinoPageRoute(
          // ContactRecordScreen no longer needs accessToken/locationId
          builder: (_) => ContactRecordScreen(contact: targetContact),
        ),
      );
    } else {
      print(
        'Navigation attempted but no contact provided or selected on dashboard.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ensure controllers match the list size
    /* REMOVED check - Controllers are managed in initState and state updates
    if (_pendingContacts.length != _slidableControllers.length) {
        print("Warning: Controller count mismatch. Reinitializing controllers.");
        _initializeSlidableControllers();
        // Return a temporary loading state or empty container might be safer here
        // return const Center(child: CircularProgressIndicator());
    }
    */

    // --- Initialize Generation Listener ---

    // --- End Initialization ---

    final theme = CupertinoTheme.of(context);
    // USE the defined provider
    final bool showCompletedTasks = ref.watch(dashboardTaskFilterProvider);
    // Read the user profile provider
    final userProfile = ref.watch(userProfileProvider);
    final displayName =
        (userProfile?.displayName?.isNotEmpty ?? false)
            ? userProfile!.displayName!
            : (userProfile?.firstName?.isNotEmpty ?? false)
            ? userProfile!.firstName!
            : 'there';

    // Watch the new provider for pending contacts
    final pendingContactsAsyncValue = ref.watch(
      dashboardPendingContactsProvider,
    );

    // Use system theme instead of forcing dark mode
    return UnfocusHelper.addDismissKeyboard(
      context: context,
      child: CupertinoPageScaffold(
        backgroundColor: AppStyles.subtleBackgroundColor(
          context,
        ), // Changed from CupertinoColors.black
        navigationBar: CupertinoNavigationBar(
          backgroundColor: AppStyles.subtleBackgroundColor(context),
          border: Border(
            bottom: BorderSide(
              color: CupertinoColors.systemGrey3.resolveFrom(context),
              width: 0.5,
            ),
          ),
          padding: const EdgeInsetsDirectional.only(bottom: 8.0),
          leading: null,
          middle: ShareAssiistDashboard(),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            child: AppStyles.accentIcon(icon: CupertinoIcons.gear, size: 24.0),
            onPressed: () {
              Navigator.of(context).push(
                CupertinoPageRoute(builder: (context) => SettingsScreen()),
              );
              print('Settings gear tapped');
            },
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  controller:
                      _scrollController, // ADDED: Attach scroll controller
                  physics:
                      const AlwaysScrollableScrollPhysics(), // Add this to ensure scroll works even when content is small
                  slivers: [
                    CupertinoSliverRefreshControl(
                      onRefresh: () async {
                        ref.invalidate(dashboardDraftsProvider);
                        ref.invalidate(dashboardTasksProvider);
                        ref.invalidate(dashboardPendingContactsProvider);
                        ref.invalidate(userTotalMetricsProvider);
                      },
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.only(
                        left: 16.0,
                        right: 16.0,
                        top: 16.0,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          // Removed: const Center(child: Icon(CupertinoIcons.rocket_fill, size: 50.0, color: CupertinoColors.systemRed)),
                          // Removed: const SizedBox(height: 16.0),
                          // Insert KPI section above greeting
                          _buildKpiSection(),
                          const SizedBox(height: 6.0),
                          Center(
                            child: Text(
                              'Hi $displayName! Got any updates or next steps?',
                              style: AppStyles.h2TextStyle(context).copyWith(
                                color: AppStyles.primaryTextColor(context),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 8.0),
                          Center(
                            child: Text(
                              'Tell me what\'s new and I\'ll log it, create follow-ups, and help you reconnect at the right time.',
                              style: AppStyles.captionTextStyle(context),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(
                            height: 36.0,
                          ), // Add space under Assistant button
                        ]),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppStyles.cardBackgroundColor(context),
                            borderRadius: BorderRadius.circular(12.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(12.0),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12.0),
                            child: SelectOrAddContact(
                              key: _selectOrAddContactKey,
                              onContactSelected: _onContactSelectedForDashboard,
                              showNavigateChevron: true,
                              onNavigateToSelectedContact: _navigateToContact,
                              showCreateButton: true,
                              onCreateContactButtonPressed: _saveContact,
                              showEditableFieldsOnSelect: false,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.only(
                        left: 16.0,
                        right: 16.0,
                        bottom: 16.0,
                        top: 36.0,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 4.0,
                              bottom: 8.0,
                            ),
                            child: Text(
                              'Message Drafts',
                              style: AppStyles.h2TextStyle(context).copyWith(
                                color: AppStyles.primaryTextColor(context),
                              ),
                            ),
                          ),
                          _buildDraftsSection(),
                          const SizedBox(height: 24.0),
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 4.0,
                              bottom: 8.0,
                            ),
                            child: Text(
                              'Tasks',
                              style: AppStyles.h2TextStyle(context).copyWith(
                                color: AppStyles.primaryTextColor(context),
                              ),
                            ),
                          ),
                          _buildPendingTasks(),
                          const SizedBox(
                            height: 24.0,
                          ), // Spacing before next section
                          // --- NEW Pending Contacts Section (Data from Provider) --- //
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 4.0,
                              bottom: 8.0,
                            ),
                            child: Text(
                              'Potential Contacts',
                              style: AppStyles.h2TextStyle(context).copyWith(
                                color: AppStyles.primaryTextColor(context),
                              ),
                            ),
                          ),
                          _buildPendingContactsSection(
                            pendingContactsAsyncValue,
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
              // Add the ControlCenterNavBar here
              ControlCenterNavBar(
                backgroundColor: AppStyles.subtleBackgroundColor(context),
                showCalendarButton: false, // ADDED: Hide calendar button
                onCalendarTap: () {
                  // Handle Calendar action
                },
                onAssistantTap: () {
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (_) => AssistantInterfaceScreen(),
                    ),
                  );
                },
                onAddContactTap: () {
                  // ADDED: Implement Add Contact functionality
                  _selectOrAddContactKey.currentState?.enterAddMode();
                  // Scroll to top to make the add contact form visible
                  _scrollController.animateTo(
                    0.0, // Scroll to the top
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                  );
                  print('Add Contact button in NavBar tapped on Dashboard');
                },
              ),
              // Add the Feedback Bar below the ControlCenterNavBar
              FeedbackBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiSection() {
    final userId = ref.watch(userIdProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        children: [
          const SizedBox(height: 24.0),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Spacer(flex: 1),
              Consumer(
                builder: (context, ref, child) {
                  final metricsAsync =
                      userId != null
                          ? ref.watch(userTotalMetricsProvider)
                          : const AsyncValue.data({
                            'notes_logged': 0,
                            'messages_sent': 0,
                          });

                  return metricsAsync.when(
                    data:
                        (metrics) => KpiWidget(
                          label: 'notes',
                          value: '${metrics['notes_logged'] ?? 0}',
                        ),
                    loading: () => KpiWidget(label: 'notes', value: '...'),
                    error: (_, __) => KpiWidget(label: 'notes', value: '0'),
                  );
                },
              ),
              Spacer(flex: 2),
              ShaderMask(
                shaderCallback:
                    (bounds) => AppStyles.gradientAccent.createShader(
                      bounds,
                    ), // Use centralized gradient
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 80.0,
                  height: 80.0,
                  color: CupertinoColors.white,
                ),
              ),
              Spacer(flex: 2),
              Consumer(
                builder: (context, ref, child) {
                  final metricsAsync =
                      userId != null
                          ? ref.watch(userTotalMetricsProvider)
                          : const AsyncValue.data({
                            'notes_logged': 0,
                            'messages_sent': 0,
                          });

                  return metricsAsync.when(
                    data:
                        (metrics) => KpiWidget(
                          label: 'drafts',
                          value: '${metrics['messages_sent'] ?? 0}',
                        ),
                    loading: () => KpiWidget(label: 'drafts', value: '...'),
                    error: (_, __) => KpiWidget(label: 'drafts', value: '0'),
                  );
                },
              ),
              Spacer(flex: 1),
            ],
          ),
        ],
      ),
    );
  }

  // --- Builder for Pending Tasks --- //
  Widget _buildPendingTasks() {
    // Watch the provider that fetches the dashboard tasks
    final tasksAsyncValue = ref.watch(dashboardTasksProvider);

    // Use pattern matching (or .when) to handle loading/error/data states
    return switch (tasksAsyncValue) {
      AsyncData(:final value) => () {
        final now = DateTime.now();
        // Filter for PENDING ACTION tasks that are actionable
        final pendingActionTasks =
            value
                ?.where(
                  (task) =>
                      task.type == 'action' &&
                      task.status == 'pending' &&
                      (task.actionableDate == null ||
                          task.actionableDate!.isBefore(now)),
                )
                .toList() ??
            [];

        // Now build the Column based on the FILTERED list
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children:
              pendingActionTasks.isEmpty
                  ? [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Center(
                        child: Row(
                          key: const ValueKey('tasks-all-caught-up'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppStyles.accentIcon(
                              icon: CupertinoIcons.check_mark_circled_solid,
                              size: 18.0,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "You're all caught up!",
                              style: AppStyles.labelTextStyle(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ]
                  : pendingActionTasks
                      .map(
                        (task) => TaskItem(
                          key: ValueKey(task.id),
                          task: task,
                          showContactInSubtitle: true,
                          onStatusToggle:
                              (tappedTask) => _handleTaskCompletion(
                                tappedTask,
                                ref,
                                context,
                              ),
                          onTap: () {
                            Navigator.of(context).push(
                              CupertinoPageRoute(
                                builder:
                                    (_) => TaskScreen(
                                      task: task,
                                      cameFromDashboard: true,
                                    ),
                              ),
                            );
                          },
                        ),
                      )
                      .toList(),
        );
      }(),
      AsyncError(:final error) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            'Error loading tasks: $error',
            style: const TextStyle(color: CupertinoColors.systemRed),
          ),
        ),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CupertinoActivityIndicator()),
      ),
    };
  }

  // --- Builder for Drafts Section --- //
  Widget _buildDraftsSection() {
    // Watch the new provider for drafts (pending message tasks)
    final draftsAsyncValue = ref.watch(dashboardDraftsProvider);

    // Use pattern matching (or .when) to handle loading/error/data states
    return switch (draftsAsyncValue) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: () {
          final now = DateTime.now();
          // Filter for pending message tasks that are actionable
          final actionableDrafts =
              value
                  .where(
                    (task) =>
                        task.actionableDate == null ||
                        task.actionableDate!.isBefore(now),
                  )
                  .toList();

          return actionableDrafts.isEmpty
              ? [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: Row(
                      key: const ValueKey('drafts-all-caught-up'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppStyles.accentIcon(
                          icon: CupertinoIcons.check_mark_circled_solid,
                          size: 18.0,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "You're all caught up!",
                          style: AppStyles.labelTextStyle(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ]
              : actionableDrafts
                  .map(
                    (task) => DraftItem(
                      key: ValueKey('draft_item_${task.id}'),
                      task: task,
                      showContactInSubtitle: true,
                      onTap: () {
                        Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder:
                                (_) => MessageDraftScreen(
                                  task: task,
                                  cameFromDashboard: true,
                                ),
                          ),
                        );
                      },
                    ),
                  )
                  .toList();
        }(),
      ),
      AsyncError(:final error) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            'Error loading drafts: $error',
            style: const TextStyle(color: CupertinoColors.systemRed),
          ),
        ),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CupertinoActivityIndicator()),
      ),
    };
  }

  // --- UPDATED: Builder for Pending Contacts Section --- //
  Widget _buildPendingContactsSection(
    AsyncValue<List<PendingContact>> asyncValue,
  ) {
    // <<< ADD LOGGING >>>
    print(
      'DashboardScreen: _buildPendingContactsSection received: $asyncValue',
    );
    return switch (asyncValue) {
      AsyncData(:final value) => _buildPendingContactsList(
        value,
      ), // Call list builder on success
      AsyncError(:final error, :final stackTrace) => Padding(
        // <<< ADD LOGGING >>>
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            'Error loading potential contacts: $error\nStack: $stackTrace', // Log stack trace too
            style: const TextStyle(color: CupertinoColors.systemRed),
          ),
        ),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CupertinoActivityIndicator()),
      ),
    };
  }

  // --- NEW: Builder for the Actual List from Data --- //
  Widget _buildPendingContactsList(List<PendingContact> pendingContacts) {
    // <<< ADD LOGGING >>>
    print(
      'DashboardScreen: _buildPendingContactsList received ${pendingContacts.length} contacts.',
    );
    if (pendingContacts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: Text('', style: TextStyle(color: CupertinoColors.systemGrey)),
        ),
      );
    }

    // --- Ensure SlidableController cleanup logic is active ---
    final currentIds =
        pendingContacts.map((PendingContact pc) => pc.id).toSet();
    final controllersToRemove =
        _slidableControllers.keys
            .where((id) => !currentIds.contains(id))
            .toList();
    for (final id in controllersToRemove) {
      _removeSlidableController(
        id,
      ); // Make sure this is being called to dispose controllers
    }
    // --- End SlidableController cleanup ---

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < pendingContacts.length; i++) ...[
          () {
            final pc = pendingContacts[i];
            final controller = _slidableControllers.putIfAbsent(pc.id, () {
              print("Creating controller for ${pc.id}");
              return SlidableController(
                this,
              ); // 'this' is _DashboardScreenState
            });

            return SlidablePendingContactItem(
              key: ValueKey(
                'pending_contact_${pc.id}',
              ), // Consistent key prefix
              pendingContact: pc,
              controller: controller,
              onAdd:
                  (context, contact) =>
                      _handleAddPendingContact(context, contact),
              onIgnore:
                  (context, contact) =>
                      _handleIgnorePendingContact(context, contact),
              onTap: () => _handlePendingContactTap(pc),
              isProcessing: _itemsBeingProcessed.contains(pc.id),
            );
          }(),
          if (i < pendingContacts.length - 1) const SizedBox(height: 8.0),
        ],
      ],
    );
  }

  void _removeSlidableController(String contactId) {
    final controller = _slidableControllers.remove(contactId);
    if (controller == null) return;

    // If the pane is open/animating, close first, then dispose when done
    if (controller.actionPaneType.value != ActionPaneType.none) {
      controller.close().whenComplete(() {
        print("Disposing SlidableController for $contactId after close anim");
        controller.dispose();
      });
    } else {
      // Already closed – dispose on next micro-task to avoid frame conflicts
      Future.microtask(() {
        print("Disposing SlidableController for $contactId (already closed)");
        controller.dispose();
      });
    }
  }
}

// --- Helper to Build Subtitle Text --- //
String buildSubtitleText(
  List<EmailAddress>? emails,
  List<PhoneNumber>? numbers,
) {
  final email = emails?.firstOrNull?.address;
  final phone = numbers?.firstOrNull?.number;

  if (email != null && phone != null) {
    return '$email ・ $phone';
  } else if (email != null) {
    return email;
  } else if (phone != null) {
    return phone;
  }
  return 'No contact info'; // Fallback text
}

// ADD BACK: Delegate for the sticky search header
class _StickyContactSearchDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _StickyContactSearchDelegate({required this.child, required this.height});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Apply the background color ONLY when the header is shrinking/sticking
    final bool isSticking = shrinkOffset > 0;
    return Container(
      // color: CupertinoColors.darkBackgroundGray, // OLD: Always apply background
      color:
          isSticking
              ? CupertinoColors.black
              : Colors.transparent, // NEW: Conditional background
      height: height,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_StickyContactSearchDelegate oldDelegate) {
    return child != oldDelegate.child || height != oldDelegate.height;
  }
}

// Example of how to use this screen in your main app
// ... existing code ...
