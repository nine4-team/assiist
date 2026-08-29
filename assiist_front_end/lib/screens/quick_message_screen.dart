import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // For potential Material widgets if needed later
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Import Riverpod
// Removed Firestore imports - using service layer now
import 'dart:async';
import 'package:assiist_front_end/providers/auth_providers.dart'; // Import providers
import 'package:assiist_front_end/widgets/select_or_add_contact.dart';
import 'package:assiist_front_end/widgets/add_contact_form.dart'; // Although form is inside SelectOrAdd, keep import for Contact model access via it for now
// import 'package:assiist_front_end/widgets/audio_controls_decorator.dart'; // REMOVE
import 'package:assiist_front_end/core/models/contact.dart';
// import 'package:assiist_front_end/widgets/enhanced_draft_progress_dialog.dart'; // REMOVE enhanced dialog import
import 'package:assiist_front_end/theme/app_styles.dart';
// import 'package:assiist_front_end/services/speech_to_text_service.dart'; // REMOVE
import 'package:assiist_front_end/widgets/notes_input_field.dart'; // IMPORT the reusable input field
import 'package:assiist_front_end/core/models/task.dart'; // <<< IMPORT Task model
import 'package:assiist_front_end/providers/repository_providers.dart'; // <<< IMPORT Repository Providers
import 'package:assiist_front_end/core/errors/exceptions.dart'; // <<< IMPORT Custom Exceptions
import 'package:assiist_front_end/utils/unfocus_helper.dart'; // Use UnfocusHelper instead of UnfocusScope
import 'message_draft_screen.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:assiist_front_end/utils/generation_request_utils.dart';

// Enum for selected language
enum MessageLanguage { english, spanish }

// Change StatefulWidget to ConsumerStatefulWidget
class GetDraftScreen extends ConsumerStatefulWidget {
  final Contact? initialContact;
  // REMOVE Prop drilling - access token/locationId should come from providers
  // final String? accessToken;
  // final String? locationId;

  const GetDraftScreen({
    super.key,
    this.initialContact,
    // this.accessToken,
    // this.locationId,
  });

  @override
  ConsumerState<GetDraftScreen> createState() => _GetDraftScreenState();
}

// Change State to ConsumerState
class _GetDraftScreenState extends ConsumerState<GetDraftScreen> {
  // --- State Variables ---
  final GlobalKey<SelectOrAddContactState> _selectOrAddContactKey =
      GlobalKey<SelectOrAddContactState>();
  final _instructionsController = TextEditingController();
  final FocusNode _instructionsFocusNode = FocusNode(); // ADD FocusNode
  bool _isSubmitting = false; // Will use for 'Get Draft' loading state
  MessageLanguage _selectedLanguage =
      MessageLanguage.english; // Default language

  // REMOVE old speech service state
  // final SpeechToTextService _speechService = SpeechToTextService();
  // bool _isListening = false;
  // String _speechError = '';
  // String? _lastRecognizedWords;

  @override
  void initState() {
    super.initState();
    if (widget.initialContact != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectOrAddContactKey.currentState != null) {
          _selectOrAddContactKey.currentState!.selectContactExternally(
            widget.initialContact!,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    _instructionsFocusNode.dispose(); // DISPOSE FocusNode
    // REMOVE _speechService.stopListening();
    super.dispose();
  }

  // REMOVE old Speech related methods
  // void _initializeSpeech() async { ... }
  // void _onSpeechStatus(String status) { ... }
  // void _onSpeechError(String error) { ... }
  // void _startListening() { ... }
  // void _stopListening() { ... }
  // void _onSpeechResult(String text, bool isFinalResult) { ... }

  // Simple quick draft flow with immediate feedback
  Future<void> _createDraft() async {
    FocusScope.of(context).unfocus();

    final selectedContact =
        _selectOrAddContactKey.currentState?.selectedContact;
    final instructions = _instructionsController.text.trim();
    final language = _selectedLanguage.name; // Get language name

    // Basic Validation
    if (selectedContact == null) {
      _showErrorDialog("Please select or add a contact.");
      return;
    }
    if (instructions.isEmpty) {
      _showErrorDialog("Please provide message instructions.");
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      print('--- Starting Simple Quick Draft Flow ---');
      print('Contact ID: ${selectedContact.id}');
      print('Instructions: $instructions');
      print('Language: $language');

      // Show simple draft dialog immediately for instant feedback
      final success = await _showSimpleQuickDraftFlow(
        context: context,
        contactId: selectedContact.id,
        instructions: instructions,
        language: language,
      );

      print('Simple quick draft flow completed. Success: $success');

      // Only pop the screen after successful completion
      if (mounted && success) {
        Navigator.pop(context);
      }
    } catch (e, stackTrace) {
      print("Error in quick draft generation flow: $e\n$stackTrace");
      if (mounted) {
        _showErrorDialog(
          "An error occurred while requesting quick draft generation. Please try again.",
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  // Simple quick draft flow with immediate feedback
  Future<bool> _showSimpleQuickDraftFlow({
    required BuildContext context,
    required String contactId,
    required String instructions,
    required String language,
  }) async {
    // Use the simple quick draft dialog (aligned with revision UX)
    return await _showSimpleQuickDraftDialog(
      context: context,
      contactId: contactId,
      instructions: instructions,
      language: language,
    );
  }

  // Simple quick draft dialog based on the revision pattern
  Future<bool> _showSimpleQuickDraftDialog({
    required BuildContext context,
    required String contactId,
    required String instructions,
    required String language,
  }) async {
    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return _SimpleQuickDraftDialog(
            contactId: contactId,
            instructions: instructions,
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
              content: Text('Failed to submit quick draft request: $e'),
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

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder:
          (context) => CupertinoAlertDialog(
            title: const Text('Quick Draft Request Failed'), // Updated title
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

  // --- Build Helpers ---
  Widget _buildSectionCard({
    required BuildContext context,
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16.0),
  }) {
    return Container(
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
      padding: padding,
      child: child,
    );
  }

  // UPDATED: Language Toggle Row Builder
  Widget _buildLanguageToggleRow() {
    final theme = CupertinoTheme.of(context);
    final bool isEnglish = _selectedLanguage == MessageLanguage.english;

    // Define styles based on the ones from MessageDraftScreen's RevisionModal
    final TextStyle selectedStyle = AppStyles.bodyTextStyle(
      context,
    ).copyWith(fontWeight: FontWeight.w600);
    final TextStyle unselectedStyle = AppStyles.bodyTextStyle(context).copyWith(
      fontWeight: FontWeight.normal,
      color: CupertinoColors.systemGrey,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween, // Align items
      children: [
        Text('Draft message in:', style: AppStyles.labelTextStyle(context)),
        Row(
          children: [
            // Spanish Label (now on the left of the toggle)
            GestureDetector(
              onTap: () {
                if (_selectedLanguage != MessageLanguage.spanish) {
                  setState(() {
                    _selectedLanguage = MessageLanguage.spanish;
                  });
                }
              },
              child:
                  !isEnglish
                      ? AppStyles.accentText(
                        context,
                        'Spanish',
                        style: AppStyles.bodyTextStyle(
                          context,
                        ).copyWith(fontWeight: FontWeight.w600),
                      )
                      : Text('Spanish', style: unselectedStyle),
            ),
            const SizedBox(width: 12),
            // Language Toggle
            CupertinoSwitch(
              value: isEnglish, // True if English, False if Spanish
              onChanged: (bool value) {
                setState(() {
                  _selectedLanguage =
                      value ? MessageLanguage.english : MessageLanguage.spanish;
                });
              },
              activeColor:
                  AppStyles.useGradientAccent
                      ? AppStyles.solidAccent
                      : AppStyles.accentTextColor(context),
              trackColor: (AppStyles.useGradientAccent
                      ? AppStyles.solidAccent
                      : AppStyles.accentTextColor(context))
                  .withOpacity(0.3),
            ),
            const SizedBox(width: 12),
            // English Label (now on the right of the toggle)
            GestureDetector(
              onTap: () {
                if (_selectedLanguage != MessageLanguage.english) {
                  setState(() {
                    _selectedLanguage = MessageLanguage.english;
                  });
                }
              },
              child:
                  isEnglish
                      ? AppStyles.accentText(
                        context,
                        'English',
                        style: AppStyles.bodyTextStyle(
                          context,
                        ).copyWith(fontWeight: FontWeight.w600),
                      )
                      : Text('English', style: unselectedStyle),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    return UnfocusHelper.addDismissKeyboard(
      // Use UnfocusHelper instead of UnfocusScope
      context: context,
      child: CupertinoPageScaffold(
        backgroundColor: AppStyles.subtleBackgroundColor(context),
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16.0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildSectionCard(
                      context: context,
                      child: SelectOrAddContact(
                        key: _selectOrAddContactKey,
                        onContactSelected: (contact) {},
                      ),
                    ),
                    const SizedBox(height: 20),
                    NotesInputField(
                      notesController: _instructionsController,
                      notesFocusNode: _instructionsFocusNode,
                      minLines: 4,
                      maxLines: 6,
                    ),
                    const SizedBox(height: 20),
                    _buildSectionCard(
                      context: context,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12.0,
                        horizontal: 16.0,
                      ),
                      child: _buildLanguageToggleRow(),
                    ),
                    const SizedBox(height: 16.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        AppStyles.borderlessButton(
                          context: context,
                          text: 'Cancel',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        _isSubmitting
                            ? AppStyles.filledButton(
                              context: context,
                              text: '',
                              onPressed: () {}, // Disabled state
                            )
                            : AppStyles.filledButton(
                              context: context,
                              text: 'Draft',
                              onPressed: () => _createDraft(),
                            ),
                      ],
                    ),
                    const SizedBox(height: 50),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Simple quick draft dialog based on the revision pattern
class _SimpleQuickDraftDialog extends ConsumerStatefulWidget {
  final String contactId;
  final String instructions;
  final String language;
  final BuildContext parentContext;

  const _SimpleQuickDraftDialog({
    required this.contactId,
    required this.instructions,
    required this.language,
    required this.parentContext,
  });

  @override
  ConsumerState<_SimpleQuickDraftDialog> createState() =>
      _SimpleQuickDraftDialogState();
}

class _SimpleQuickDraftDialogState
    extends ConsumerState<_SimpleQuickDraftDialog> {
  StreamSubscription<DocumentSnapshot>? _subscription;
  String _status = 'submitting';
  String? _error;
  String? _requestId;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _submitQuickDraftRequest();
  }

  @override
  void dispose() {
    print('🔥 Simple quick draft dialog disposing');
    _isDisposed = true;
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _submitQuickDraftRequest() async {
    try {
      final assistantRepo = ref.read(assistantRepositoryProvider);

      // Prepare quick draft payload
      final quickDraftPayload = {
        'contact_id': widget.contactId,
        'message_instructions': widget.instructions,
        'language': widget.language,
      };

      print(
        "🔥 Submitting quick draft with payload: ${jsonEncode(quickDraftPayload)}",
      );

      // Submit quick draft request and get request_id
      final responseData = await assistantRepo.quickDraft(quickDraftPayload);
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
      print("❌ Error submitting quick draft request: $e");
      _handleError("Failed to submit quick draft: $e");
    }
  }

  void _startFirestoreListener(String requestId) {
    final firestore = FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: 'assiist-app',
    );

    _subscription = firestore
        .collection(
          GenerationRequestUtils.getCollectionForOperation('quick_draft'),
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
            print("🔥 Quick draft status update: $status");

            setState(() {
              _status = status;
              if (status == 'failed') {
                _error = data['error_message'] ?? 'Unknown error occurred';
              }
            });

            if (status == 'completed') {
              print("🔥 Quick draft completed successfully");

              // Extract task ID from processing metadata
              final processingMetadata =
                  data['processing_metadata'] as Map<String, dynamic>?;
              final taskId =
                  processingMetadata?['generated_task_id'] as String?;

              if (taskId != null) {
                _fetchAndNavigateToTask(taskId);
              } else {
                _handleError('No task ID received from server');
              }
            } else if (status == 'failed') {
              print("🔥 Quick draft failed: ${_error}");
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

  Future<void> _fetchAndNavigateToTask(String taskId) async {
    if (_isDisposed) return;

    try {
      print('🔥 Fetching task with ID: $taskId');
      final taskRepo = ref.read(taskRepositoryProvider);
      final task = await taskRepo.getById(taskId, widget.contactId);

      if (task != null) {
        // Invalidate providers to refresh task lists
        ref.invalidate(dashboardTasksProvider);
        ref.invalidate(tasksForContactProvider(widget.contactId));

        // Navigate to draft screen
        await Navigator.of(widget.parentContext).push(
          CupertinoPageRoute(
            builder:
                (context) =>
                    MessageDraftScreen(task: task, cameFromDashboard: true),
          ),
        );

        // Close dialog
        if (mounted) Navigator.of(context).pop(true);
      } else {
        _handleError('Task not found');
      }
    } catch (e) {
      print('🔥 Error fetching task: $e');
      _handleError('Error fetching generated task: $e');
    }
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
                  title: const Text('Quick Draft Failed'),
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
          _status == 'failed'
              ? Icon(
                _getStatusIcon(),
                color: CupertinoColors.systemRed,
                size: 24,
              )
              : AppStyles.accentIcon(icon: _getStatusIcon(), size: 24),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              'Creating Draft',
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
            const CupertinoActivityIndicator(
              radius: 12.0,
              color: CupertinoColors.systemRed,
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
              style: AppStyles.bodyTextStyle(
                context,
              ).copyWith(color: CupertinoColors.systemRed, fontSize: 14),
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
            child: Text('Cancel', style: AppStyles.buttonTextStyle(context)),
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
        return 'Creating your message...\n(10-15 seconds)';
      case 'completed':
        return 'Your message draft has been created successfully!';
      case 'failed':
        return 'Something went wrong while creating your draft.';
      default:
        return 'Creating your message...\n(This usually takes 10-15 seconds)';
    }
  }
}

// Helper function to convert task data from GenerationRequest to Task object
Task _taskFromGenerationRequestData(Map<String, dynamic> taskData) {
  final id = taskData['id'] as String?;
  final title = taskData['title'] as String?;
  final body = taskData['body'] as String?;
  final userId = taskData['user_id'] as String?;
  final contactId = taskData['contact_id'] as String?;
  final createdBy = taskData['created_by'] as String?;

  if (id == null ||
      title == null ||
      body == null ||
      userId == null ||
      contactId == null ||
      createdBy == null) {
    throw Exception(
      'Missing required task data fields. Received: ${taskData.keys.toList()}',
    );
  }

  final newTask = Task(
    id: id,
    title: title,
    body: body,
    type: taskData['type'] as String? ?? 'message',
    status: taskData['status'] as String? ?? 'pending',
    userId: userId,
    contactId: contactId,
    createdBy: createdBy,
    createdOn: DateTime.now(),
    sms_url: taskData['sms_url'] as String?,
    contactDisplayName: taskData['contact_display_name'] as String?,
    assistant_message: taskData['assistant_message'] as String?,
    llm_provider: taskData['llm_provider'] as String?,
    accountId: taskData['account_id'] as String?,
  );

  return newTask;
}
