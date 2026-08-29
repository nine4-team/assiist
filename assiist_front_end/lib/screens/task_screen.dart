import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // Import Material for dialogs/scaffold messenger
import 'package:intl/intl.dart'; // For date formatting
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Import Riverpod
import 'package:assiist_front_end/widgets/linkified_text.dart'; // For auto-linkification
import 'package:assiist_front_end/core/models/task.dart';
import 'package:assiist_front_end/theme/app_styles.dart';
import 'contact_record_screen.dart';
import 'package:assiist_front_end/providers/repository_providers.dart'; // Import providers
import 'package:assiist_front_end/core/models/contact.dart'; // Import Contact
import 'package:assiist_front_end/utils/navigation_helpers.dart'; // ADDED IMPORT
import '../screens/log_note_screen.dart'; // ADDED IMPORT
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:assiist_front_end/widgets/nav_bar_back_button.dart'; // Import centralized back button
import 'package:assiist_front_end/widgets/feedback_bar.dart'; // Import Feedback Bar widget
import 'package:assiist_front_end/core/templates/note_templates.dart'; // new generic templates
// import 'package:assiist_front_end/core/repositories/contact_repository.dart'; // Import Contact repo if needed for fetch

// Convert to ConsumerStatefulWidget
class TaskScreen extends ConsumerStatefulWidget {
  final Task task;
  final bool cameFromDashboard; // Keep flag
  final bool hideContactLink; // ADD new flag

  const TaskScreen({
    super.key,
    required this.task,
    this.cameFromDashboard = false,
    this.hideContactLink = false, // Default to false
  });

  @override
  ConsumerState<TaskScreen> createState() => _TaskScreenState();
}

// Define the State class
class _TaskScreenState extends ConsumerState<TaskScreen> {
  // --- State Variables for Editing ---
  bool _isEditing = false;
  late Task
  _currentTask; // ADD state variable for the task being displayed/edited
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  DateTime? _selectedDueDate;

  @override
  void initState() {
    super.initState();
    // Initialize _currentTask with the initial task
    _currentTask = widget.task;
    // Initialize controllers and date with initial task data
    _titleController = TextEditingController(text: _currentTask.title);
    _descriptionController = TextEditingController(
      text: _currentTask.body ?? '',
    );
    _selectedDueDate = _currentTask.dueDate;
  }

  @override
  void dispose() {
    // Dispose controllers
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // --- Helper Methods (now inside State class) ---

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return DateFormat.yMMMd().add_jm().format(date);
  }

  // Helper to build styled section cards
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment:
            CrossAxisAlignment.center, // Keep vertical center alignment
        children: [
          // --- Delete Button (Moved to Left) ---
          AppStyles.borderlessButton(
            context: context,
            text: 'Delete',
            onPressed: _deleteTask,
          ),

          // --- Complete Button (Moved to Right) ---
          AppStyles.filledButton(
            context: context,
            text: 'Complete',
            onPressed: _completeTask,
          ),
        ],
      ),
    );
  }

  // Helper for bottom action bar (Edit Mode)
  Widget _buildEditActionBar(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    return Container(
      // Similar styling as view mode bar
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
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
        ],
      ),
    );
  }

  // --- NEW: Method to Toggle Edit Mode ---
  void _toggleEditing() {
    setState(() {
      _isEditing = !_isEditing;
      // If switching FROM edit mode, potentially reset fields?
      // Or handle save/cancel explicitly in EditActionBar
    });
  }

  // --- Repository Action Handlers ---

  Future<void> _completeTask() async {
    if (_currentTask.id == null || _currentTask.contactId == null) {
      print("Error: Cannot complete task without ID or Contact ID.");
      _showErrorDialog("Cannot complete task: missing required information.");
      return;
    }

    // Use the helper method to create the minimal contact
    final Contact? initialContact =
        NavigationHelpers.createMinimalContactFromTask(_currentTask);

    // Navigate to LogNoteScreen with pre-filled notes
    final bool? logSuccess = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder:
            (_) => LogNoteScreen(
              initialContact: initialContact,
              taskToModify: _currentTask,
              isCompleting: true,
              hideContactSelector: true,
              completedTaskNotes: NavigationHelpers.buildCompletedTaskNotes(
                _currentTask,
              ),
            ),
      ),
    );

    if (mounted && (logSuccess == true || logSuccess == null)) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _deleteTask() async {
    final taskRepo = ref.read(taskRepositoryProvider);
    if (_currentTask.id == null || _currentTask.contactId == null) {
      print("Error: Cannot delete task without ID or Contact ID.");
      _showErrorDialog("Cannot delete task: missing required information.");
      return;
    }

    print(
      "Attempting to soft delete Task ID: \\${_currentTask.id} for Contact ID: \\${_currentTask.contactId}",
    );

    // Store task details before deletion for navigation
    final Task taskToDeleteDetails = _currentTask;

    // Construct the notes template for LogNoteScreen
    final String notesTemplate = NoteTemplates.deletedTask(taskToDeleteDetails);

    // Use the helper method to create the minimal contact
    final Contact? initialContact =
        NavigationHelpers.createMinimalContactFromTask(taskToDeleteDetails);

    // Navigate to LogNoteScreen
    final bool? logSuccess = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder:
            (_) => LogNoteScreen(
              initialContact: initialContact,
              completedTaskNotes: notesTemplate,
              isDeleting: true,
              hideContactSelector: true,
            ),
      ),
    );

    // Only perform the soft delete after logging
    if (mounted && (logSuccess == true || logSuccess == null)) {
      try {
        final updates = {'status': 'deleted'};
        final Task? updatedTask = await taskRepo.updateTask(
          _currentTask.id!,
          _currentTask.contactId!,
          updates,
        );
        ref.invalidate(dashboardTasksProvider);
        ref.invalidate(tasksForContactProvider(_currentTask.contactId!));
        Navigator.pop(context, true);
      } catch (e) {
        print(
          "Error soft deleting task \\${_currentTask.id}: \\${e.toString()}",
        );
        if (mounted) {
          _showErrorDialog("Failed to delete task: \\${e.toString()}");
        }
      }
    }
  }

  // Helper to show error dialog (using CupertinoAlertDialog)
  void _showErrorDialog(String message) {
    if (!mounted) return; // Check if widget is still in the tree
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

  // Implement Save Task Updates
  Future<void> _saveTaskUpdates() async {
    // Hide keyboard
    FocusScope.of(context).unfocus();

    final String newTitle = _titleController.text.trim();
    final String newDescription = _descriptionController.text.trim();
    final DateTime? newDueDate = _selectedDueDate;

    // Basic validation (e.g., title shouldn't be empty)
    if (newTitle.isEmpty) {
      _showErrorDialog("Task title cannot be empty.");
      return;
    }

    // Check if anything actually changed (optional, but good practice)
    bool changed =
        newTitle != _currentTask.title ||
        newDescription != (_currentTask.body ?? '') ||
        newDueDate != _currentTask.dueDate;

    if (!changed) {
      setState(() {
        _isEditing = false; // Exit edit mode if nothing changed
      });
      return;
    }

    // Construct updates map - only include fields that changed?
    // Or send all potentially editable fields? Let's send all for simplicity.
    final updates = <String, dynamic>{
      'title': newTitle,
      'body':
          newDescription.isEmpty ? null : newDescription, // Send null if empty
      'due_date': newDueDate?.toIso8601String(), // Use ISO string for repo
      // Include other potential fields if they were editable
    };
    // Remove nulls specifically for Firestore compatibility if needed, but repo interface uses Map
    // updates.removeWhere((key, value) => value == null && key == 'description'); // Let repo handle null descriptions
    if (newDueDate == null) {
      // updates['due_date'] = FieldValue.delete(); // REMOVE Firestore-specific code
      // Pass null to the repository. Firestore implementation will handle conversion.
      updates['due_date'] = null;
    }

    print("Saving task updates: $updates");

    // --- Call Repository ---
    final taskRepo = ref.read(taskRepositoryProvider);
    if (_currentTask.id == null || _currentTask.contactId == null) {
      _showErrorDialog("Cannot update task: missing ID or Contact ID.");
      return;
    }

    try {
      await taskRepo.updateTask(
        _currentTask.id!,
        _currentTask.contactId!,
        updates,
      );

      // Invalidate providers
      ref.invalidate(dashboardTasksProvider);
      ref.invalidate(tasksForContactProvider(_currentTask.contactId!));
      // Invalidate this specific task to force a refetch
      final taskIdentifier = TaskIdentifier(
        taskId: _currentTask.id!,
        contactId: _currentTask.contactId!,
      );
      ref.invalidate(currentTaskProvider(taskIdentifier));

      // IMPORTANT: Update the local _currentTask state variable
      // Create a new task object reflecting the saved state
      final updatedTask = _currentTask.copyWith(
        title: newTitle,
        body: newDescription.isEmpty ? null : newDescription,
        dueDate: newDueDate, // Already DateTime? or null
      );

      // Update state and exit edit mode
      if (mounted) {
        setState(() {
          _currentTask = updatedTask; // Update the local task state
          _isEditing = false;
        });
        // Optionally show a success message
        // _showCompletionDialog("Task updated!");
      }
    } catch (e) {
      print("Error updating task ${_currentTask.id}: $e");
      if (mounted) {
        _showErrorDialog("Failed to update task: ${e.toString()}");
        // Optional: Stay in edit mode on failure?
      }
    }
  }

  // Implement Cancel Editing
  void _cancelEditing() {
    // Reset controllers and date to original values
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
    // If task has no ID, it can't be fetched from a provider.
    // This happens for new, unsaved tasks. We build with local `_currentTask` state.
    if (widget.task.id == null || widget.task.contactId == null) {
      return _buildTaskContent(context, _currentTask); // Build with local state
    }

    // If we have an ID, watch the provider for live updates.
    final taskIdentifier = TaskIdentifier(
      taskId: widget.task.id!,
      contactId: widget.task.contactId!,
    );
    final taskAsync = ref.watch(currentTaskProvider(taskIdentifier));

    return taskAsync.when(
      data: (taskData) {
        if (taskData == null) {
          // Handle case where task is not found (e.g., deleted).
          return CupertinoPageScaffold(
            navigationBar: const CupertinoNavigationBar(
              leading: NavBarBackButton(),
              middle: Text('Task Not Found'),
            ),
            child: const Center(
              child: Text(
                'This task could not be found. It may have been deleted.',
              ),
            ),
          );
        }

        // When new data arrives from the provider, update our local state.
        // We do this in a post-frame callback to avoid build-time state changes.
        // We also check `_isEditing` to prevent overwriting user input.
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

        // Build the main UI with the latest task data.
        return _buildTaskContent(context, taskData);
      },
      loading:
          () => CupertinoPageScaffold(
            backgroundColor: AppStyles.subtleBackgroundColor(context),
            navigationBar: CupertinoNavigationBar(
              leading: const NavBarBackButton(),
              middle: const Text('Task'),
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
            child: Center(child: Text('Failed to load task: $err')),
          ),
    );
  }

  Widget _buildTrailingActions(BuildContext context, Task task) {
    String copyText = task.title;
    if (task.body != null && task.body!.isNotEmpty) {
      copyText += '\n\n${task.body}';
    } else if (task.description != null && task.description!.isNotEmpty) {
      copyText += '\n\n${task.description}';
    }
    if (task.status == 'completed' &&
        (task.completedOn ?? task.updatedOn ?? task.createdOn) != null) {
      final completedTimestamp =
          task.completedOn ?? task.updatedOn ?? task.createdOn;
      copyText +=
          '\n\nCompleted: ${DateFormat.yMd().add_jm().format(completedTimestamp!)}';
    }
    if (task.status == 'pending' && task.dueDate != null) {
      copyText += '\n\nDue: ${DateFormat.yMd().add_jm().format(task.dueDate!)}';
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
                      content: const Text('Task details copied to clipboard'),
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

  Widget _buildTaskContent(BuildContext context, Task task) {
    // final theme = CupertinoTheme.of(context); // No longer needed here
    // final task = _currentTask; // Now passed as parameter

    // Build copy text (mimic timeline item copy)
    String copyText = task.title;
    if (task.body != null && task.body!.isNotEmpty) {
      copyText += '\n\n${task.body}';
    } else if (task.description != null && task.description!.isNotEmpty) {
      copyText += '\n\n${task.description}';
    }
    if (task.status == 'completed' &&
        (task.completedOn ?? task.updatedOn ?? task.createdOn) != null) {
      final completedTimestamp =
          task.completedOn ?? task.updatedOn ?? task.createdOn;
      copyText +=
          '\n\nCompleted: ${DateFormat.yMd().add_jm().format(completedTimestamp!)}';
    }
    if (task.status == 'pending' && task.dueDate != null) {
      copyText += '\n\nDue: ${DateFormat.yMd().add_jm().format(task.dueDate!)}';
    }

    return CupertinoPageScaffold(
      backgroundColor: AppStyles.subtleBackgroundColor(context),
      navigationBar: CupertinoNavigationBar(
        leading: const NavBarBackButton(),
        middle: const Text('Task'),
        trailing: _buildTrailingActions(context, task),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24.0), // Consistent initial spacing
                    // Contact Name Display (Simplified to match MessageDraftScreen)
                    if (!_isEditing && !widget.hideContactLink)
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
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'No Contact Linked',
                            style: AppStyles.labelTextStyle(context),
                          ),
                        ),
                    if (!widget
                        .hideContactLink) // Spacing only if contact link section is potentially visible
                      const SizedBox(
                        height: 24.0,
                      ), // Consistent spacing after contact link
                    // Title (Editable or View)
                    _isEditing
                        ? CupertinoTextField(
                          controller: _titleController,
                          placeholder: 'Task Title',
                          style: AppStyles.inputTextStyle(
                            context,
                          ).copyWith(fontWeight: FontWeight.bold, fontSize: 18),
                          // decoration: AppStyles.minimalInputDecoration, // REMOVED
                          padding: const EdgeInsets.symmetric(
                            vertical: 12.0,
                            horizontal: 16.0,
                          ), // Default-like padding
                        )
                        : Text(
                          task.title.isEmpty ? "(No Title)" : task.title,
                          style: AppStyles.inputTextStyle(context).copyWith(
                            fontWeight: FontWeight.bold,
                          ), // Consistent title style
                        ),
                    const SizedBox(height: 12.0), // Consistent spacing
                    // Description / Body (Editable or View)
                    _isEditing
                        ? CupertinoTextField(
                          controller: _descriptionController,
                          placeholder: 'Task description...',
                          maxLines: 5,
                          style: AppStyles.inputTextStyle(context),
                          // decoration: AppStyles.minimalInputDecoration, // REMOVED
                          padding: const EdgeInsets.symmetric(
                            vertical: 12.0,
                            horizontal: 16.0,
                          ), // Default-like padding
                        )
                        : (task.body?.isNotEmpty ?? false)
                        ? LinkifiedText(
                          task.body!,
                          style: AppStyles.bodyTextStyle(
                            context,
                          ), // Consistent body style (15pt)
                        )
                        : const SizedBox.shrink(),

                    if (!_isEditing && (task.body?.isNotEmpty ?? false))
                      const SizedBox(
                        height: 16.0,
                      ), // Consistent spacing after body
                    // Due Date Section (Editable or View) - Matches MessageDraftScreen's "Send By"
                    _isEditing
                        ? Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed:
                                () => _pickDueDate(
                                  context,
                                ), // Ensure lambda for context
                            child: Row(
                              children: [
                                AppStyles.accentIcon(
                                  icon: CupertinoIcons.calendar,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                AppStyles.accentText(
                                  context,
                                  'Due by: ${_formatDate(_selectedDueDate)}',
                                  style: AppStyles.labelTextStyle(context),
                                ),
                              ],
                            ),
                          ),
                        )
                        : Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.calendar,
                                size: 18,
                                color: AppStyles.secondaryTextColor(context),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Due by: ${_formatDate(task.dueDate)}', // "Due by" wording
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
                bottom: MediaQuery.of(context).padding.bottom,
              ),
              child: FeedbackBar(),
            ),
          ],
        ),
      ),
    );
  }

  // Date Picker Logic
  Future<void> _pickDueDate(BuildContext context) async {
    // Hide keyboard if open
    FocusScope.of(context).unfocus();

    showCupertinoModalPopup(
      context: context,
      builder:
          (_) => Container(
            height: 250,
            color: CupertinoColors.systemBackground.resolveFrom(context),
            child: Column(
              children: [
                // Optional: Add Done/Cancel buttons here if needed
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
