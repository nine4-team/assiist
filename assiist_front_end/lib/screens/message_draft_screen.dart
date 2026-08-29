import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // Import Material for dialogs/scaffold messenger
import 'package:intl/intl.dart'; // For date formatting
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Import Riverpod
import 'package:assiist_front_end/providers/auth_providers.dart'; // <<< ADDED for userIdProvider & userProfileProvider
import 'package:assiist_front_end/core/models/task.dart'; // Assuming message draft still uses Task model
import 'package:assiist_front_end/theme/app_styles.dart';
import 'contact_record_screen.dart';
import 'package:assiist_front_end/providers/repository_providers.dart'; // Import providers
import 'package:assiist_front_end/core/models/contact.dart'; // Import Contact
import 'package:assiist_front_end/core/models/note.dart'; // Import Note model
import 'log_note_screen.dart';
import 'package:assiist_front_end/providers/metrics_providers.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:assiist_front_end/utils/navigation_helpers.dart'; // ADDED import for NavigationHelpers
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:assiist_front_end/widgets/audio_controls_decorator.dart'; // ADDED import for AudioControlsDecorator
import 'package:audio_waveforms/audio_waveforms.dart'; // ADDED import for RecorderController
import 'package:assiist_front_end/services/audio_service.dart';
import 'dart:async';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:assiist_front_end/utils/generation_request_utils.dart';
import 'package:assiist_front_end/providers/repository_providers.dart'; // Import repository providers
import 'package:assiist_front_end/data/repositories/api/api_update_assistant_repository.dart'; // For ProcessNoteResponse
import 'package:assiist_front_end/widgets/nav_bar_back_button.dart'; // Import centralized back button
import 'package:assiist_front_end/widgets/feedback_bar.dart'; // Import Feedback Bar widget
import 'package:assiist_front_end/core/templates/note_templates.dart'; // new generic templates

// Convert to ConsumerStatefulWidget
class MessageDraftScreen extends ConsumerStatefulWidget {
  // RENAMED Class
  final Task task; // Assuming task model for draft
  final bool cameFromDashboard; // Keep flag if needed
  final bool hideContactLink; // ADD new flag

  const MessageDraftScreen({
    // RENAMED Constructor
    super.key,
    required this.task,
    this.cameFromDashboard = false,
    this.hideContactLink = false, // Default to false
  });

  @override
  ConsumerState<MessageDraftScreen> createState() => _MessageDraftScreenState(); // RENAMED State Class
}

// Define the State class
class _MessageDraftScreenState extends ConsumerState<MessageDraftScreen> {
  // RENAMED State Class
  // --- State Variables for Editing ---
  bool _isEditing = false;
  late Task _currentTask;
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  DateTime? _selectedDueDate; // Keep this, represents "Send By" date

  // Add revision history tracking
  List<Map<String, dynamic>> _revisionHistory = [];

  // Track recent revisions for visual feedback
  bool _wasRecentlyRevised = false;

  @override
  void initState() {
    super.initState();
    _currentTask = widget.task;
    _titleController = TextEditingController(text: _currentTask.title);
    _descriptionController = TextEditingController(
      text: _currentTask.body ?? '',
    );
    _selectedDueDate = _currentTask.dueDate; // Use dueDate for "Send By"
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // --- Helper Methods (now inside State class) ---

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return DateFormat.yMMMd().add_jm().format(date);
  }

  // Helper to build styled section cards (Keep as is)
  Widget _buildSectionCard({
    required BuildContext context,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppStyles.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: child,
    );
  }

  // Helper for bottom action bar (View Mode)
  Widget _buildViewActionBar(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      // Wrap the content in a Column to place text below the button row
      child: Column(
        mainAxisSize: MainAxisSize.min, // Take minimum vertical space
        crossAxisAlignment: CrossAxisAlignment.end, // Align text to the right
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment:
                CrossAxisAlignment
                    .center, // Vertically center buttons in the row
            children: [
              // --- Delete Button (Moved to Left) ---
              AppStyles.borderlessButton(
                context: context,
                text: 'Delete',
                onPressed: _deleteTask,
              ),

              // --- Buttons on the Right (Grouped: Revise, Send) ---
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.center, // Align buttons vertically
                children: [
                  // --- Revise Button (Right-Center) ---
                  AppStyles.borderedButton(
                    context: context,
                    text: 'Revise',
                    onPressed: _reviseMessage,
                  ),
                  const SizedBox(width: 12), // Spacing between revise and send
                  // --- Send Button (Moved to Far Right) ---
                  AppStyles.filledButton(
                    context: context,
                    text: 'Send',
                    onPressed: _send,
                  ),
                ],
              ),
            ],
          ),
          // --- "Sent manually" Text (Below the Send Button Area - Aligned Right) ---
          const SizedBox(height: 4), // Spacing between button row and text
          Padding(
            padding: const EdgeInsets.only(
              right: 4,
            ), // Align near Send button on the right
            child: GestureDetector(
              onTap: _sendManually,
              child: AppStyles.accentText(
                context,
                'Sent manually',
                style: AppStyles.labelTextStyle(
                  context,
                ).copyWith(fontSize: 12, decoration: TextDecoration.underline),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper for bottom action bar (Edit Mode) - Keep as is
  Widget _buildEditActionBar(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 12.0,
      ).copyWith(bottom: MediaQuery.of(context).padding.bottom + 12.0),
      decoration: BoxDecoration(
        color: AppStyles.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            onPressed: _cancelEditing,
            child: AppStyles.buttonAccentText(context, 'Cancel'),
          ),
          // Note: The 'Done' button is in the NavigationBar trailing item
        ],
      ),
    );
  }

  // Method to Toggle Edit Mode (Keep as is)
  void _toggleEditing() {
    setState(() {
      _isEditing = !_isEditing;
    });
  }

  // --- Repository Action Handlers ---

  // Simple send method for the Send button
  Future<void> _send() async {
    // Capture necessary data from _currentTask at the beginning
    final String? currentTaskId = _currentTask.id;
    final String? currentContactId = _currentTask.contactId;
    final String? smsUrl = _currentTask.sms_url;
    final String taskType = _currentTask.type;

    if (currentTaskId == null || currentContactId == null) {
      print("Error: Cannot send message without Task ID or Contact ID.");
      _showErrorDialog("Cannot send message: missing required information.");
      return;
    }

    // Validate SMS URL for message tasks
    if (taskType == 'message' && (smsUrl == null || smsUrl.isEmpty)) {
      _showErrorDialog(
        "Cannot send message: missing SMS URL. Please contact support.",
      );
      return;
    }

    // 1. Optimistically Launch SMS URL (if applicable)
    if (taskType == 'message' && smsUrl != null && smsUrl.isNotEmpty) {
      final Uri smsUri = Uri.parse(smsUrl);
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      } else {
        _showErrorDialog(
          "Could not open SMS link. Please check your SMS app or contact support.",
        );
        return;
      }
    }

    // 2. Update last contacted timestamp
    try {
      final contactRepo = ref.read(contactRepositoryProvider);
      await contactRepo.updateLastContacted(currentContactId);
      print("Updated last contacted timestamp for contact $currentContactId");

      // Invalidate contact provider to refresh the contact data
      ref.invalidate(contactByIdProvider(currentContactId));
    } catch (e) {
      print("Warning: Failed to update last contacted timestamp: $e");
      // Don't block the flow if this fails
    }

    // 3. Mark task as completed
    try {
      final taskRepo = ref.read(taskRepositoryProvider);
      final updatedTask = await taskRepo.updateTask(
        currentTaskId,
        currentContactId,
        {
          'status': 'completed',
          'completed_on': DateTime.now().toIso8601String(),
        },
      );

      if (updatedTask != null) {
        print("✅ Task $currentTaskId marked as completed");

        // Invalidate task providers to refresh UI
        ref.invalidate(dashboardTasksProvider);
        ref.invalidate(tasksForContactProvider(currentContactId));
      } else {
        print("Warning: Failed to mark task as completed");
      }
    } catch (e) {
      print("Warning: Failed to mark task as completed: $e");
      // Don't block the flow if this fails
    }

    // 4. Silent note logging to update_assistant endpoint
    try {
      final updateAssistantRepo = ref.read(updateAssistantRepositoryProvider);

      // Construct the note content similar to _sendManually but for sent messages
      final String noteContent = NoteTemplates.manualSendMessage(_currentTask);

      print("🤖 Silently logging sent message to update assistant");
      print("📝 Note content: $noteContent");
      print("👤 Contact ID: $currentContactId");

      // Silent call to update assistant - don't wait for completion
      updateAssistantRepo
          .updateAssistant(
            contactId: currentContactId,
            rawNoteContent: noteContent,
            context: {
              'source': 'message_draft_screen_send',
              'timestamp': DateTime.now().toIso8601String(),
              'task_id': currentTaskId,
              'message_sent_via': 'sms_app',
            },
          )
          .catchError((e) {
            print(
              "Warning: Failed to log sent message to update assistant: $e",
            );
            // Don't block the flow if this fails - return a dummy response
            return ProcessNoteResponse(
              success: false,
              tasksProcessed: 0,
              contextUpdated: false,
              noteSaved: {'error': 'Failed to log message'},
            );
          });

      print("✅ Silent note logging initiated for sent message");
    } catch (e) {
      print("Warning: Failed to initiate silent note logging: $e");
      // Don't block the flow if this fails
    }

    // 5. Pop MessageDraftScreen immediately after attempting to launch SMS
    if (mounted) {
      Navigator.pop(
        context,
        true,
      ); // Pop with 'true' to indicate an action was taken
    }
  }

  // RENAMED from _completeTask
  Future<void> _sendManually() async {
    if (_currentTask.id == null || _currentTask.contactId == null) {
      print("Error: Cannot mark draft as sent without ID or Contact ID.");
      _showErrorDialog("Cannot mark as sent: missing required information.");
      return;
    }

    // Update last contacted timestamp before navigating to LogNoteScreen
    try {
      final contactRepo = ref.read(contactRepositoryProvider);
      await contactRepo.updateLastContacted(_currentTask.contactId!);
      print(
        "Updated last contacted timestamp for contact ${_currentTask.contactId}",
      );

      // Invalidate contact provider to refresh the contact data
      ref.invalidate(contactByIdProvider(_currentTask.contactId!));
    } catch (e) {
      print("Warning: Failed to update last contacted timestamp: $e");
      // Don't block the flow if this fails
    }

    // Construct the notes template for LogNoteScreen
    final String notesTemplate = NoteTemplates.manualSendMessage(_currentTask);

    // Construct a minimal Contact object for LogNoteScreen
    final Contact? initialContact =
        (_currentTask.contactId != null)
            ? Contact(
              id: _currentTask.contactId!,
              first_name: _currentTask.contactDisplayName?.split(' ').first,
              last_name:
                  _currentTask.contactDisplayName != null &&
                          _currentTask.contactDisplayName!.contains(' ')
                      ? _currentTask.contactDisplayName!.substring(
                        _currentTask.contactDisplayName!.indexOf(' ') + 1,
                      )
                      : null,
              is_deleted: false,
            )
            : null;

    // Navigate to LogNoteScreen with the task to modify
    final bool? logSuccess = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder:
            (_) => LogNoteScreen(
              initialContact: initialContact,
              completedTaskNotes: notesTemplate,
              taskToModify: _currentTask,
              isCompleting: true,
              hideContactSelector: true,
            ),
      ),
    );

    // Pop MessageDraftScreen if LogNoteScreen was successful
    if (logSuccess == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  // Placeholder for Revise action
  Future<void> _reviseMessage() async {
    // Show revision dialog
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: CupertinoColors.black,
      builder: (BuildContext context) {
        return RevisionModal(
          messageText: _currentTask.body ?? _currentTask.title,
          onSubmit: (instructions, language) {
            Navigator.pop(context);
            _submitRevision(instructions, language);
          },
        );
      },
    );
  }

  // Method to handle revision submission
  Future<void> _submitRevision(
    String revisionInstructions,
    String language,
  ) async {
    if (revisionInstructions.trim().isEmpty) {
      _showErrorDialog("Please provide revision instructions.");
      return;
    }

    final userId = ref.read(userIdProvider);
    if (userId == null) {
      _showErrorDialog("User not authenticated. Cannot submit revision.");
      return;
    }
    if (_currentTask.id == null || _currentTask.contactId == null) {
      _showErrorDialog(
        "Task or Contact ID is missing. Cannot submit revision.",
      );
      return;
    }

    try {
      // Show simple revision dialog immediately for instant feedback
      if (mounted) {
        final result = await _showSimpleRevisionFlow(
          context: context,
          revisionInstructions: revisionInstructions,
          language: language,
        );

        if (result == true) {
          // Just update the visual state and refresh data
          setState(() {
            _wasRecentlyRevised = true;
          });

          // Invalidate providers to refresh task data
          ref.invalidate(dashboardTasksProvider);
          ref.invalidate(tasksForContactProvider(_currentTask.contactId!));

          // Reset visual flag after animation
          Future.delayed(Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _wasRecentlyRevised = false;
              });
            }
          });
        }
      }
    } catch (e) {
      print("Error revising message: $e");
      if (mounted) {
        String errorMessage = "Failed to revise message";

        if (e.toString().contains("not found")) {
          errorMessage = "Task not found. It may have been deleted.";
        } else if (e.toString().contains("no message content")) {
          errorMessage = "This task has no message content to revise.";
        } else if (e.toString().contains("don't have access")) {
          errorMessage = "You don't have access to this task.";
        } else {
          errorMessage = "Failed to revise message: ${e.toString()}";
        }

        _showErrorDialog(errorMessage);
      }
    }
  }

  // Simple revision flow with immediate feedback
  Future<bool> _showSimpleRevisionFlow({
    required BuildContext context,
    required String revisionInstructions,
    required String language,
  }) async {
    try {
      // Show dialog immediately for instant feedback
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return _SimpleRevisionDialog(
            taskId: _currentTask.id!,
            contactId: _currentTask.contactId!,
            revisionInstructions: revisionInstructions,
            language: language,
            parentContext: context,
          );
        },
      );

      return result ?? false;
    } catch (e) {
      if (!context.mounted) return false;

      showCupertinoDialog(
        context: context,
        builder:
            (context) => CupertinoAlertDialog(
              title: const Text('Request Failed'),
              content: Text('Failed to submit revision request: $e'),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
      return false;
    }
  }

  // Keep _deleteTask logic for now, it deletes the underlying Task object
  Future<void> _deleteTask() async {
    if (_currentTask.id == null || _currentTask.contactId == null) {
      print("Error: Cannot delete draft without ID or Contact ID.");
      _showErrorDialog("Cannot delete draft: missing required information.");
      return;
    }

    // Construct the notes template for LogNoteScreen
    final String notesTemplate = NoteTemplates.deletedMessageDraft(
      _currentTask,
    );

    // Use the helper method to create the minimal contact
    final Contact? initialContact =
        NavigationHelpers.createMinimalContactFromTask(_currentTask);

    // Navigate to LogNoteScreen with the task to modify
    final bool? logSuccess = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder:
            (_) => LogNoteScreen(
              initialContact: initialContact,
              completedTaskNotes: notesTemplate,
              taskToModify: _currentTask,
              isDeleting: true,
              hideContactSelector: true,
            ),
      ),
    );

    // Pop MessageDraftScreen if LogNoteScreen was successful
    if (logSuccess == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  // Helper to show error dialog (Keep as is)
  void _showErrorDialog(String message) {
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder:
          (context) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text(message),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
                isDefaultAction: true,
              ),
            ],
          ),
    );
  }

  // Implement Save Task Updates (Keep as is for editing fields)
  Future<void> _saveTaskUpdates() async {
    FocusScope.of(context).unfocus();
    final String newTitle = _titleController.text.trim();
    final String newDescription = _descriptionController.text.trim();
    final DateTime? newSendByDate = _selectedDueDate; // Renamed for clarity

    if (newTitle.isEmpty) {
      _showErrorDialog(
        "Message draft title cannot be empty.",
      ); // Update error text
      return;
    }

    bool changed =
        newTitle != _currentTask.title ||
        newDescription != (_currentTask.body ?? '') ||
        newSendByDate != _currentTask.dueDate; // Check against dueDate

    if (!changed) {
      setState(() {
        _isEditing = false;
      });
      return;
    }

    final updates = <String, dynamic>{
      'title': newTitle,
      'body': newDescription.isEmpty ? null : newDescription,
      'due_date': newSendByDate?.toIso8601String(), // Map to due_date field
    };
    if (newSendByDate == null) {
      updates['due_date'] = null;
    }

    print("Saving draft updates: $updates");

    final taskRepo = ref.read(taskRepositoryProvider);
    if (_currentTask.id == null || _currentTask.contactId == null) {
      _showErrorDialog("Cannot update draft: missing ID or Contact ID.");
      return;
    }

    try {
      await taskRepo.updateTask(
        _currentTask.id!,
        _currentTask.contactId!,
        updates,
      );

      ref.invalidate(
        dashboardTasksProvider,
      ); // May need specific draft providers later
      ref.invalidate(tasksForContactProvider(_currentTask.contactId!));
      // Invalidate this specific task to force a refetch
      final taskIdentifier = TaskIdentifier(
        taskId: _currentTask.id!,
        contactId: _currentTask.contactId!,
      );
      ref.invalidate(currentTaskProvider(taskIdentifier));

      final updatedTask = _currentTask.copyWith(
        title: newTitle,
        body: newDescription.isEmpty ? null : newDescription,
        dueDate: newSendByDate, // Update local state
      );

      if (mounted) {
        setState(() {
          _currentTask = updatedTask;
          _isEditing = false;
        });
      }
    } catch (e) {
      print("Error updating draft ${_currentTask.id}: $e");
      if (mounted) {
        _showErrorDialog("Failed to update draft: ${e.toString()}");
      }
    }
  }

  // Implement Cancel Editing (Keep as is)
  void _cancelEditing() {
    _titleController.text = _currentTask.title;
    _descriptionController.text = _currentTask.body ?? '';
    _selectedDueDate = _currentTask.dueDate;
    setState(() {
      _isEditing = false;
    });
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    if (widget.task.id == null || widget.task.contactId == null) {
      return _buildMessageContent(context, _currentTask);
    }

    final taskIdentifier = TaskIdentifier(
      taskId: widget.task.id!,
      contactId: widget.task.contactId!,
    );
    final taskAsync = ref.watch(currentTaskProvider(taskIdentifier));

    return taskAsync.when(
      data: (taskData) {
        if (taskData == null) {
          return CupertinoPageScaffold(
            navigationBar: const CupertinoNavigationBar(
              leading: NavBarBackButton(),
              middle: Text('Draft Not Found'),
            ),
            child: const Center(
              child: Text(
                'This message draft could not be found. It may have been deleted.',
              ),
            ),
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && taskData != _currentTask && !_isEditing) {
            setState(() {
              _currentTask = taskData;
              _titleController.text = taskData.title;
              _descriptionController.text = taskData.body ?? '';
              _selectedDueDate = taskData.dueDate;
            });
          }
        });

        return _buildMessageContent(context, taskData);
      },
      loading:
          () => CupertinoPageScaffold(
            backgroundColor: AppStyles.subtleBackgroundColor(context),
            navigationBar: CupertinoNavigationBar(
              leading: const NavBarBackButton(),
              middle: const Text('Message Draft'),
              trailing: _buildTrailingActions(context, _currentTask),
            ),
            child: const Center(child: CupertinoActivityIndicator()),
          ),
      error:
          (err, stack) => CupertinoPageScaffold(
            navigationBar: CupertinoNavigationBar(
              leading: const NavBarBackButton(),
              middle: const Text('Error'),
              trailing: _buildTrailingActions(context, _currentTask),
            ),
            child: Center(child: Text('Failed to load draft: $err')),
          ),
    );
  }

  Widget _buildTrailingActions(BuildContext context, Task task) {
    String copyText = task.title;
    if (task.body != null && task.body!.isNotEmpty) {
      copyText += '\n\n${task.body}';
    }
    if (task.status == 'completed' &&
        (task.completedOn ?? task.updatedOn ?? task.createdOn) != null) {
      final sentTimestamp =
          task.completedOn ?? task.updatedOn ?? task.createdOn;
      copyText +=
          '\n\nSent: ${DateFormat.yMd().add_jm().format(sentTimestamp!)}';
    }
    if (task.status == 'pending' &&
        (task.dueDate ?? task.actionableDate) != null) {
      copyText +=
          '\n\nSend by: ${DateFormat.yMd().add_jm().format(task.dueDate ?? task.actionableDate!)}';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!_isEditing)
          CupertinoButton(
            padding: EdgeInsets.zero,
            child: AppStyles.accentIcon(
              icon: CupertinoIcons.doc_on_doc,
              size: 22.0,
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: copyText));
              showCupertinoDialog(
                context: context,
                builder:
                    (context) => CupertinoAlertDialog(
                      title: const Text('Copied'),
                      content: const Text('Message draft copied to clipboard'),
                      actions: [
                        CupertinoDialogAction(
                          child: const Text('OK'),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
              );
            },
          ),
        CupertinoButton(
          padding: EdgeInsets.zero,
          child: AppStyles.buttonAccentText(
            context,
            _isEditing ? 'Done' : 'Edit',
          ),
          onPressed: () {
            if (_isEditing) {
              _saveTaskUpdates();
            } else {
              _toggleEditing();
            }
          },
        ),
      ],
    );
  }

  Widget _buildMessageContent(BuildContext context, Task task) {
    return CupertinoPageScaffold(
      backgroundColor: AppStyles.subtleBackgroundColor(context),
      navigationBar: CupertinoNavigationBar(
        leading: const NavBarBackButton(),
        middle: const Text('Message Draft'),
        trailing: _buildTrailingActions(context, task),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0), // Original padding
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24.0), // Original initial spacing
                    // Contact Name Display (using current data logic, original-inspired styling for "No Contact")
                    if (!widget.hideContactLink)
                      if (task.contactDisplayName?.isNotEmpty ?? false)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            minSize: 0,
                            onPressed: () {
                              if (task.contactId?.isNotEmpty ?? false) {
                                Navigator.of(context).push(
                                  CupertinoPageRoute(
                                    builder:
                                        (_) => ContactRecordScreen(
                                          contactId: task.contactId!,
                                        ),
                                  ),
                                );
                              }
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppStyles.accentText(
                                  context,
                                  task.contactDisplayName!,
                                  style: AppStyles.bodyTextStyle(
                                    context,
                                  ).copyWith(fontSize: 16),
                                ),
                                const SizedBox(width: 4),
                                AppStyles.accentIcon(
                                  icon: CupertinoIcons.chevron_right,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8.0,
                          ), // Original padding for this case
                          child: Text(
                            'No Contact Linked',
                            style: AppStyles.labelTextStyle(
                              context,
                            ), // Original style
                          ),
                        ),
                    if (!widget.hideContactLink)
                      const SizedBox(
                        height: 24.0,
                      ), // Original spacing after contact link
                    // Title / Subject (Editable or View)
                    _isEditing
                        ? CupertinoTextField(
                          controller: _titleController,
                          placeholder: 'Subject / Title',
                          style: AppStyles.inputTextStyle(
                            context,
                          ).copyWith(fontWeight: FontWeight.bold),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12.0,
                            horizontal: 16.0,
                          ),
                        )
                        : Text(
                          task.title.isEmpty ? "(No Subject)" : task.title,
                          style: AppStyles.inputTextStyle(
                            context,
                          ).copyWith(fontWeight: FontWeight.bold),
                        ),

                    const SizedBox(height: 12.0),

                    _isEditing
                        ? CupertinoTextField(
                          controller: _descriptionController,
                          placeholder: 'Message body...',
                          maxLines: 10,
                          textInputAction: TextInputAction.newline,
                          style: AppStyles.inputTextStyle(context),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12.0,
                            horizontal: 16.0,
                          ),
                        )
                        : (task.body?.isNotEmpty ?? false)
                        ? Text(
                          task.body!,
                          style: AppStyles.bodyTextStyle(context),
                        )
                        : const SizedBox.shrink(),

                    if (!_isEditing && (task.body?.isNotEmpty ?? false))
                      const SizedBox(height: 16.0),

                    _isEditing
                        ? Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => _pickSendByDate(context),
                            child: Row(
                              children: [
                                AppStyles.accentIcon(
                                  icon: CupertinoIcons.calendar,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                AppStyles.accentText(
                                  context,
                                  'Send by: ${_formatDate(_selectedDueDate)}',
                                  style: AppStyles.labelTextStyle(context),
                                ),
                              ],
                            ),
                          ),
                        )
                        : Padding(
                          padding: const EdgeInsets.only(
                            top: 8.0,
                          ), // Original padding
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.calendar,
                                size: 18,
                                color: AppStyles.secondaryTextColor(context),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Send by: ${_formatDate(task.dueDate)}',
                                style: AppStyles.labelTextStyle(context),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
            _isEditing
                ? _buildEditActionBar(context)
                : _buildViewActionBar(context),
            // Add the Feedback Bar at the bottom with proper padding
            Container(
              padding: EdgeInsets.only(
                bottom:
                    MediaQuery.of(
                      context,
                    ).padding.bottom, // Just safe area padding
              ),
              child: FeedbackBar(),
            ),
          ],
        ),
      ),
    );
  }

  // Renamed from _pickDueDate to be specific, but original was _showDatePicker
  Future<void> _pickSendByDate(BuildContext context) async {
    // Keep current name _pickSendByDate
    FocusScope.of(context).unfocus();
    showCupertinoModalPopup(
      context: context,
      builder:
          (_) => Container(
            height: 250,
            color: CupertinoColors.systemBackground.resolveFrom(context),
            child: Column(
              children: [
                SizedBox(
                  height: 200,
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.dateAndTime,
                    initialDateTime: _selectedDueDate ?? DateTime.now(),
                    onDateTimeChanged: (DateTime newDateTime) {
                      setState(() {
                        _selectedDueDate = newDateTime;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }
}

// Separate stateful widget for the revision modal to properly handle state
class RevisionModal extends StatefulWidget {
  final String messageText;
  final Function(String, String) onSubmit;

  const RevisionModal({
    super.key,
    required this.messageText,
    required this.onSubmit,
  });

  @override
  State<RevisionModal> createState() => _RevisionModalState();
}

class _RevisionModalState extends State<RevisionModal> {
  late TextEditingController revisionInstructionsController;
  bool reviseInEnglish = true;

  // Audio recording state
  bool _isListening = false;
  bool _isProcessing = false;
  bool _isInitializing = true;
  Duration _elapsedTime = Duration.zero;
  RecorderController? _recorderController;
  Timer? _recordingTimer;
  late final String _fieldId;

  @override
  void initState() {
    super.initState();
    revisionInstructionsController = TextEditingController();
    _fieldId = 'revision_modal_ 2${DateTime.now().millisecondsSinceEpoch}';
    _recorderController = AudioService().getRecorderController(_fieldId);
    _initializeInBackground();
  }

  @override
  void dispose() {
    revisionInstructionsController.dispose();
    _recordingTimer?.cancel();
    AudioService().dispose(_fieldId);
    super.dispose();
  }

  Future<void> _initializeInBackground() async {
    try {
      final audioService = AudioService();
      await audioService.initialize();

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      print("Error during initialization: $e");
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  void _toggleLanguage(bool value) {
    setState(() {
      reviseInEnglish = value;
    });
  }

  // Synchronous VoidCallback for AudioControlsDecorator
  void _onMicPressed() {
    if (_isInitializing) {
      print("Still initializing speech recognition...");
      return;
    }
    if (!AudioService().isReady) {
      print("Speech recognition not available or not initialized.");
      return;
    }
    if (!_isListening) {
      _startListening();
    } else {
      _stopListening();
    }
  }

  void _startListening() async {
    if (!AudioService().isReady || _isListening) return;
    if (!mounted) return;

    setState(() {
      _isListening = true;
      _elapsedTime = Duration.zero;
    });

    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _elapsedTime = Duration(seconds: _elapsedTime.inSeconds + 1);
      });
    });

    try {
      await AudioService().startListening(
        fieldId: _fieldId,
        onResult: _onSpeechResult,
      );
    } catch (e) {
      print("Error during start/listen: $e");
      if (mounted) {
        setState(() => _isListening = false);
        _recordingTimer?.cancel();
      }
    }
  }

  void _stopListening() async {
    _recordingTimer?.cancel();
    try {
      await AudioService().stopListening(_fieldId);
    } catch (e) {
      print("Error stopping recording: $e");
    }
    if (mounted) {
      setState(() => _isListening = false);
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    // Actually transcribe the speech to text
    if (result.finalResult && result.recognizedWords.isNotEmpty) {
      if (!mounted) return;

      final controller = revisionInstructionsController;
      final currentText = controller.text;
      final selection = controller.selection;
      String newText;

      // Append or replace logic
      if (selection.isValid && selection.start != -1) {
        // If there's a selection, replace it
        newText = currentText.replaceRange(
          selection.start,
          selection.end,
          '${result.recognizedWords} ',
        );
        // Set cursor position after the inserted text
        final newOffset = selection.start + result.recognizedWords.length + 1;
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newOffset),
        );
      } else {
        // If no selection, append at the end
        newText = '$currentText${result.recognizedWords} ';
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }
    }
  }

  // Synchronous VoidCallback for AudioControlsDecorator
  void _onCancelPressed() {
    print("CANCEL: Cancel requested. Calling _stopListening...");
    _stopListening();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppStyles.cardBackgroundColor(context),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20.0),
          topRight: Radius.circular(20.0),
        ),
      ),
      padding: const EdgeInsets.all(20.0),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Close button at top right
            Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(
                  CupertinoIcons.xmark,
                  color: CupertinoColors.systemGrey,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Current message display
            Text(widget.messageText, style: AppStyles.bodyTextStyle(context)),
            const SizedBox(height: 24),

            // Revision instructions field
            Container(
              decoration: BoxDecoration(
                color: AppStyles.subtleBackgroundColor(context),
                borderRadius: BorderRadius.circular(12.0),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Revision Instructions",
                    style: AppStyles.labelTextStyle(context),
                  ),
                  const SizedBox(height: 8),
                  AudioControlsDecorator(
                    isListening: _isListening,
                    isProcessing: _isProcessing,
                    elapsedTime: _elapsedTime,
                    recorderController: _recorderController,
                    onMicPressed: _onMicPressed,
                    onCancelPressed: _onCancelPressed,
                    child: CupertinoTextField(
                      controller: revisionInstructionsController,
                      placeholder:
                          "Describe how you'd like to revise this message...",
                      maxLines: 4,
                      decoration: null,
                      style: AppStyles.inputTextStyle(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Language selection row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Revise in:",
                  style: AppStyles.bodyTextStyle(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                Row(
                  children: [
                    // Spanish label
                    GestureDetector(
                      onTap: () => _toggleLanguage(false),
                      child:
                          !reviseInEnglish
                              ? AppStyles.accentText(
                                context,
                                "Spanish",
                                style: AppStyles.bodyTextStyle(
                                  context,
                                ).copyWith(fontWeight: FontWeight.w600),
                              )
                              : Text(
                                "Spanish",
                                style: AppStyles.bodyTextStyle(
                                  context,
                                ).copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: CupertinoColors.systemGrey,
                                ),
                              ),
                    ),
                    const SizedBox(width: 12),
                    // Language toggle with primary color for track
                    CupertinoSwitch(
                      value: reviseInEnglish,
                      onChanged: _toggleLanguage,
                      activeColor: AppStyles.accentTextColor(context),
                      trackColor: AppStyles.accentTextColor(context),
                    ),
                    const SizedBox(width: 12),
                    // English label
                    GestureDetector(
                      onTap: () => _toggleLanguage(true),
                      child:
                          reviseInEnglish
                              ? AppStyles.accentText(
                                context,
                                "English",
                                style: AppStyles.bodyTextStyle(
                                  context,
                                ).copyWith(fontWeight: FontWeight.w600),
                              )
                              : Text(
                                "English",
                                style: AppStyles.bodyTextStyle(
                                  context,
                                ).copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: CupertinoColors.systemGrey,
                                ),
                              ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: AppStyles.accentButtonDecoration(
                  borderRadius: BorderRadius.circular(30),
                ),
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  borderRadius: BorderRadius.circular(30),
                  onPressed: () {
                    widget.onSubmit(
                      revisionInstructionsController.text,
                      reviseInEnglish ? 'english' : 'spanish',
                    );
                  },
                  child: Text(
                    "Submit Revision",
                    style: AppStyles.buttonTextStyle(
                      context,
                    ).copyWith(color: CupertinoColors.white),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// Simple revision dialog based on the working pattern
class _SimpleRevisionDialog extends ConsumerStatefulWidget {
  final String taskId;
  final String contactId;
  final String revisionInstructions;
  final String language;
  final BuildContext parentContext;

  const _SimpleRevisionDialog({
    required this.taskId,
    required this.contactId,
    required this.revisionInstructions,
    required this.language,
    required this.parentContext,
  });

  @override
  ConsumerState<_SimpleRevisionDialog> createState() =>
      _SimpleRevisionDialogState();
}

class _SimpleRevisionDialogState extends ConsumerState<_SimpleRevisionDialog> {
  StreamSubscription<DocumentSnapshot>? _subscription;
  String _status = 'submitting';
  String? _error;
  String? _requestId;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _submitRevisionRequest();
  }

  @override
  void dispose() {
    print('🔥 Simple revision dialog disposing');
    _isDisposed = true;
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _submitRevisionRequest() async {
    try {
      final assistantRepo = ref.read(assistantRepositoryProvider);

      // Prepare revision payload
      final revisionPayload = {
        'task_id': widget.taskId,
        'contact_id': widget.contactId,
        'revision_instructions': widget.revisionInstructions,
        'message_language': widget.language,
      };

      print(
        "🔥 Submitting revision with payload: ${jsonEncode(revisionPayload)}",
      );

      // Submit revision request and get request_id
      final responseData = await assistantRepo.reviseDraft(revisionPayload);
      final requestId = responseData['id'] as String?;

      if (requestId == null || requestId.isEmpty) {
        _handleError("Invalid response: missing request ID");
        return;
      }

      print("🔥 Received request ID: $requestId");

      if (!_isDisposed) {
        setState(() {
          _requestId = requestId;
          _status = 'pending';
        });
        _startFirestoreListener(requestId);
      }
    } catch (e) {
      print("❌ Error submitting revision request: $e");
      _handleError("Failed to submit revision: $e");
    }
  }

  void _startFirestoreListener(String requestId) {
    final firestore = FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: 'assiist-app',
    );

    _subscription = firestore
        .collection(
          GenerationRequestUtils.getCollectionForOperation('revise_draft'),
        )
        .doc(requestId)
        .snapshots()
        .listen(
          (snapshot) {
            if (_isDisposed) return;

            if (!snapshot.exists) {
              print("🔥 Document does not exist yet, waiting...");
              return;
            }

            final data = snapshot.data();
            if (data == null) return;

            final status = data['status'] ?? 'pending';
            print("🔥 Revision status update: $status");

            setState(() {
              _status = status;
              if (status == 'failed') {
                _error = data['error_message'] ?? 'Unknown error occurred';
              }
            });

            if (status == 'completed') {
              print("🔥 Revision completed successfully");

              // Refresh the specific task
              if (mounted) {
                final taskIdentifier = TaskIdentifier(
                  taskId: widget.taskId,
                  contactId: widget.contactId,
                );
                ref
                    .read(currentTaskProvider(taskIdentifier).notifier)
                    .refreshTask();
                ref.invalidate(dashboardTasksProvider);
                ref.invalidate(tasksForContactProvider(widget.contactId));
              }

              // Close with success after brief delay
              Future.delayed(const Duration(milliseconds: 800), () {
                if (mounted && !_isDisposed) {
                  Navigator.of(context).pop(true);
                }
              });
            } else if (status == 'failed') {
              print("🔥 Revision failed: ${_error}");
              // Auto-close on failure after showing error
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted && !_isDisposed) {
                  Navigator.of(context).pop(false);
                }
              });
            }
          },
          onError: (error) {
            print('❌ Firestore listener error: $error');
            if (!_isDisposed) {
              _handleError(
                'Connection error. Please check your internet connection.',
              );
            }
          },
        );

    // Set timeout
    Timer(const Duration(minutes: 2), () {
      if (!_isDisposed && _status != 'completed' && _status != 'failed') {
        _handleError('Request timed out after 2 minutes');
      }
    });
  }

  void _handleError(String error) {
    if (_isDisposed) return;

    setState(() {
      _status = 'failed';
      _error = error;
    });

    // Auto-close after showing error
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && !_isDisposed) {
        Navigator.of(context).pop(false);

        // Show error in parent context
        if (widget.parentContext.mounted) {
          showCupertinoDialog(
            context: widget.parentContext,
            builder:
                (context) => CupertinoAlertDialog(
                  title: const Text('Revision Failed'),
                  content: Text(error),
                  actions: [
                    CupertinoDialogAction(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);

    return CupertinoAlertDialog(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getStatusIcon(),
            color:
                _status == 'failed'
                    ? AppStyles.accentTextColor(context)
                    : AppStyles.accentTextColor(context),
            size: 24,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              'Revising Message',
              style: AppStyles.bodyTextStyle(
                context,
              ).copyWith(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),

          // Show spinner for active states
          if (_status == 'submitting' ||
              _status == 'pending' ||
              _status == 'processing') ...[
            CupertinoActivityIndicator(
              radius: 12.0,
              color: AppStyles.accentTextColor(context),
            ),
            const SizedBox(height: 16),
          ],

          Text(
            _getStatusText(),
            style: AppStyles.bodyTextStyle(context),
            textAlign: TextAlign.center,
          ),
          if (_error != null && _status == 'failed') ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: AppStyles.bodyTextStyle(context).copyWith(
                color: AppStyles.accentTextColor(context),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        if (_status == 'submitting' ||
            _status == 'pending' ||
            _status == 'processing')
          CupertinoDialogAction(
            onPressed: () {
              _subscription?.cancel();
              Navigator.of(context).pop(false);
            },
            child: AppStyles.buttonAccentText(context, 'Cancel'),
          ),
      ],
    );
  }

  IconData _getStatusIcon() {
    switch (_status) {
      case 'submitting':
        return CupertinoIcons.arrow_up_circle;
      case 'pending':
        return CupertinoIcons.clock;
      case 'processing':
        return CupertinoIcons.sparkles;
      case 'completed':
        return CupertinoIcons.check_mark_circled_solid;
      case 'failed':
        return CupertinoIcons.exclamationmark_triangle_fill;
      default:
        return CupertinoIcons.clock;
    }
  }

  String _getStatusText() {
    switch (_status) {
      case 'submitting':
      case 'pending':
      case 'processing':
        return 'Creating revision...\n(10-15 seconds)';
      case 'completed':
        return 'Your message has been revised successfully!';
      case 'failed':
        return 'Something went wrong while revising your message.';
      default:
        return 'Creating revision...\n(This usually takes 10-15 seconds)';
    }
  }
}
