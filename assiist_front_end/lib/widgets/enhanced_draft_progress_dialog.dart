import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:assiist_front_end/core/models/generation_request.dart';
import 'package:assiist_front_end/core/models/task.dart';
import 'package:assiist_front_end/providers/repository_providers.dart';
import 'package:assiist_front_end/screens/message_draft_screen.dart';
import 'package:assiist_front_end/theme/app_styles.dart';
import 'package:assiist_front_end/services/generation_request_service.dart'
    as service;
import 'dart:async';
import 'package:uuid/uuid.dart';

enum DraftProgressStep {
  submitting, // Request being submitted to API
  submitted, // Request successfully submitted, waiting for processing
  analyzing, // AI analyzing request and gathering context
  generating, // AI generating content
  finalizing, // Creating task and saving results
  completed, // Success - draft ready
  failed, // Error occurred
}

class DraftProgressInfo {
  final DraftProgressStep step;
  final String title;
  final String subtitle;
  final IconData icon;
  final double progress; // 0.0 to 1.0
  final Duration estimatedTimeRemaining;
  final bool isError;

  const DraftProgressInfo({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.progress,
    required this.estimatedTimeRemaining,
    this.isError = false,
  });

  static const Map<DraftProgressStep, DraftProgressInfo> _stepInfo = {
    DraftProgressStep.submitting: DraftProgressInfo(
      step: DraftProgressStep.submitting,
      title: "Submitting Request",
      subtitle: "Sending your request to our AI system...",
      icon: CupertinoIcons.arrow_up_circle,
      progress: 0.1,
      estimatedTimeRemaining: Duration(seconds: 25),
    ),
    DraftProgressStep.submitted: DraftProgressInfo(
      step: DraftProgressStep.submitted,
      title: "Request Received",
      subtitle: "Your request has been accepted and queued for processing",
      icon: CupertinoIcons.checkmark_circle,
      progress: 0.2,
      estimatedTimeRemaining: Duration(seconds: 20),
    ),
    DraftProgressStep.analyzing: DraftProgressInfo(
      step: DraftProgressStep.analyzing,
      title: "Analyzing Context",
      subtitle: "AI is gathering contact information and your preferences...",
      icon: CupertinoIcons.search_circle,
      progress: 0.4,
      estimatedTimeRemaining: Duration(seconds: 15),
    ),
    DraftProgressStep.generating: DraftProgressInfo(
      step: DraftProgressStep.generating,
      title: "Crafting Your Message",
      subtitle:
          "AI is writing a personalized message based on your instructions...",
      icon: CupertinoIcons.sparkles,
      progress: 0.7,
      estimatedTimeRemaining: Duration(seconds: 8),
    ),
    DraftProgressStep.finalizing: DraftProgressInfo(
      step: DraftProgressStep.finalizing,
      title: "Finalizing Draft",
      subtitle: "Saving your draft and preparing the preview...",
      icon: CupertinoIcons.doc_circle,
      progress: 0.9,
      estimatedTimeRemaining: Duration(seconds: 2),
    ),
    DraftProgressStep.completed: DraftProgressInfo(
      step: DraftProgressStep.completed,
      title: "Draft Ready!",
      subtitle: "Your personalized message has been created successfully",
      icon: CupertinoIcons.check_mark_circled_solid,
      progress: 1.0,
      estimatedTimeRemaining: Duration.zero,
    ),
    DraftProgressStep.failed: DraftProgressInfo(
      step: DraftProgressStep.failed,
      title: "Generation Failed",
      subtitle: "Something went wrong while creating your draft",
      icon: CupertinoIcons.exclamationmark_triangle_fill,
      progress: 0.0,
      estimatedTimeRemaining: Duration.zero,
      isError: true,
    ),
  };

  static DraftProgressInfo forStep(DraftProgressStep step) {
    return _stepInfo[step]!;
  }
}

class EnhancedDraftProgressDialog extends StatefulWidget {
  final String contactId;
  final String requestType; // 'quick_draft' or 'revise_draft'
  final BuildContext parentContext;

  // Quick draft specific
  final String? instructions;
  final String? language;

  // Revision specific
  final String? taskId;
  final String? revisionInstructions;

  const EnhancedDraftProgressDialog({
    Key? key,
    required this.contactId,
    required this.requestType,
    required this.parentContext,
    this.instructions,
    this.language,
    this.taskId,
    this.revisionInstructions,
  }) : super(key: key);

  @override
  State<EnhancedDraftProgressDialog> createState() =>
      _EnhancedDraftProgressDialogState();
}

class _EnhancedDraftProgressDialogState
    extends State<EnhancedDraftProgressDialog>
    with TickerProviderStateMixin {
  final service.GenerationRequestService _service =
      service.GenerationRequestService();
  StreamSubscription<service.GenerationRequestStatus>? _subscription;
  DraftProgressStep _currentStep = DraftProgressStep.submitting;
  String? _error;
  String? _requestId; // Track request ID internally
  bool _isDisposed = false;
  Timer? _progressTimer;
  Timer? _timeoutTimer;

  late AnimationController _progressAnimationController;
  late Animation<double> _progressAnimation;
  late AnimationController _pulseAnimationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startProgressFlow();
    _startTimeoutTimer();
  }

  void _initializeAnimations() {
    _progressAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _progressAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _pulseAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _pulseAnimationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    print(
      '🔥 Enhanced dialog disposing, cancelling listener for ${_requestId ?? 'unknown'}',
    );
    _isDisposed = true;
    _subscription?.cancel();
    _progressTimer?.cancel();
    _timeoutTimer?.cancel();
    _progressAnimationController.dispose();
    _pulseAnimationController.dispose();
    super.dispose();
  }

  void _startProgressFlow() {
    // Start with immediate feedback
    _updateStep(DraftProgressStep.submitting);

    // Make API call immediately (like revision dialog)
    _submitRequest();
  }

  Future<void> _submitRequest() async {
    try {
      service.GenerationRequestResult result;

      if (widget.requestType == 'quick_draft') {
        result = await _service.createQuickDraft(
          contactId: widget.contactId,
          instructions: widget.instructions!,
          language: widget.language ?? 'english',
        );
      } else {
        result = await _service.createRevision(
          taskId: widget.taskId!,
          revisionInstructions: widget.revisionInstructions!,
          language: widget.language ?? 'english',
        );
      }

      if (!result.isSuccess) {
        _handleError(result.errorMessage ?? 'Failed to submit request');
        return;
      }

      _requestId = result.requestId!;

      if (!_isDisposed) {
        _updateStep(DraftProgressStep.submitted);
        _startFirestoreListener();
      }
    } catch (e) {
      _handleError('Failed to submit request: $e');
    }
  }

  void _updateStep(DraftProgressStep newStep) {
    if (_isDisposed) return;

    setState(() {
      _currentStep = newStep;
    });

    // Animate progress bar
    final info = DraftProgressInfo.forStep(newStep);
    _progressAnimationController.animateTo(info.progress);
  }

  void _startFirestoreListener() {
    if (_requestId == null) {
      _handleError('Request ID not available');
      return;
    }

    final statusStream = _service.listenToRequestStatus(
      requestId: _requestId!,
      operationType: widget.requestType,
    );

    _subscription = statusStream.listen(
      (status) {
        if (_isDisposed) return;

        print('🔥 Service status update: ${status.status}');
        _processStatusUpdate(status.status, status.resultData ?? {});
      },
      onError: (error) {
        print('❌ Service listener error: $error');
        if (!_isDisposed) {
          _handleError(
            'Connection error. Please check your internet connection.',
          );
        }
      },
    );
  }

  void _processStatusUpdate(String status, Map<String, dynamic> data) {
    print('🔥 Processing status update: $status');
    print('🔥 Data keys: ${data.keys.toList()}');
    print('🔥 Data content: ${data.toString()}');

    switch (status) {
      case 'pending':
        if (_currentStep.index < DraftProgressStep.analyzing.index) {
          _updateStep(DraftProgressStep.analyzing);
        }
        break;

      case 'processing':
        _updateStep(DraftProgressStep.generating);
        break;

      case 'completed':
        _updateStep(DraftProgressStep.finalizing);

        Timer(const Duration(milliseconds: 1000), () {
          if (!_isDisposed) {
            _updateStep(DraftProgressStep.completed);

            Timer(const Duration(milliseconds: 1500), () {
              if (!_isDisposed) {
                print('🔥 Checking for task data...');
                final taskId = data['generated_task_id'] as String?;
                print('🔥 Generated task ID: $taskId');
                if (taskId != null) {
                  _fetchAndHandleTask(taskId);
                } else {
                  print(
                    '🔥 No task ID found, available keys: ${data.keys.toList()}',
                  );
                  _handleError('No task ID received from server');
                }
              }
            });
          }
        });
        break;

      case 'failed':
        final errorMessage = data['error_message'] ?? 'Generation failed';
        _handleError(errorMessage);
        break;
    }
  }

  void _startTimeoutTimer() {
    _timeoutTimer = Timer(const Duration(minutes: 2), () {
      if (!_isDisposed && _currentStep != DraftProgressStep.completed) {
        _handleError('Request timed out. Please try again.');
      }
    });
  }

  void _fetchAndHandleTask(String taskId) async {
    if (_isDisposed) return;

    try {
      print('🔥 Fetching task with ID: $taskId');
      final container = ProviderScope.containerOf(context);
      final taskRepo = container.read(taskRepositoryProvider);
      final task = await taskRepo.getById(taskId, widget.contactId);

      if (task != null) {
        // Invalidate providers to refresh task lists
        container.invalidate(dashboardTasksProvider);
        container.invalidate(tasksForContactProvider(widget.contactId));

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

  void _handleSuccess(Map<String, dynamic> taskData) async {
    if (_isDisposed) return;

    try {
      final task = _taskFromGenerationRequestData(taskData);

      // Invalidate providers to refresh task lists
      if (mounted) {
        final container = ProviderScope.containerOf(context);
        container.invalidate(dashboardTasksProvider);
        container.invalidate(tasksForContactProvider(widget.contactId));
      }

      // Navigate to draft screen
      await Navigator.of(widget.parentContext).push(
        CupertinoPageRoute(
          builder:
              (context) =>
                  MessageDraftScreen(task: task, cameFromDashboard: true),
        ),
      );

      // Close dialog
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e, stackTrace) {
      print('🔥 Error in _handleSuccess: $e');
      _handleError('Error processing generated draft: $e');
    }
  }

  void _handleError(String error) {
    if (_isDisposed) return;

    setState(() {
      _currentStep = DraftProgressStep.failed;
      _error = error;
    });

    // Auto-close after showing error for a bit
    Timer(const Duration(seconds: 3), () {
      if (mounted && !_isDisposed) {
        Navigator.of(context).pop(false);

        // Show error dialog in parent context
        if (widget.parentContext.mounted) {
          showCupertinoDialog(
            context: widget.parentContext,
            builder:
                (context) => CupertinoAlertDialog(
                  title: const Text('Generation Failed'),
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
    final info = DraftProgressInfo.forStep(_currentStep);

    return CupertinoAlertDialog(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: info.isError ? 1.0 : _pulseAnimation.value,
                child: Icon(
                  info.icon,
                  color:
                      info.isError
                          ? CupertinoColors
                              .systemRed // Keep red for errors
                          : AppStyles
                              .solidAccent, // Use accent system for non-errors
                  size: 24,
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              widget.requestType == 'quick_draft'
                  ? 'Creating Draft'
                  : 'Revising Draft',
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

          // Progress bar
          Container(
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: CupertinoColors.systemGrey5,
            ),
            child: AnimatedBuilder(
              animation: _progressAnimation,
              builder: (context, child) {
                return FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _progressAnimation.value * info.progress,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color:
                          info.isError
                              ? CupertinoColors
                                  .systemRed // Keep red for errors
                              : AppStyles
                                  .solidAccent, // Use accent system for progress
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // Step title
          Text(
            info.title,
            style: AppStyles.bodyTextStyle(
              context,
            ).copyWith(fontWeight: FontWeight.w600, fontSize: 16),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          // Step subtitle
          Text(
            info.subtitle,
            style: AppStyles.labelTextStyle(context),
            textAlign: TextAlign.center,
          ),

          // Time estimate (only show if not completed or failed)
          if (!info.isError && _currentStep != DraftProgressStep.completed) ...[
            const SizedBox(height: 12),
            Text(
              'Estimated time: ${info.estimatedTimeRemaining.inSeconds}s remaining',
              style: AppStyles.labelTextStyle(
                context,
              ).copyWith(color: CupertinoColors.systemGrey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],

          // Error details
          if (_error != null && info.isError) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CupertinoColors.systemRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: CupertinoColors.systemRed.withOpacity(0.3),
                ),
              ),
              child: Text(
                _error!,
                style: AppStyles.bodyTextStyle(
                  context,
                ).copyWith(color: CupertinoColors.systemRed, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
      actions: [
        // Only show cancel for non-completed states
        if (_currentStep != DraftProgressStep.completed && !info.isError)
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
}

// Helper function to show the enhanced draft progress flow
Future<bool> showEnhancedDraftGenerationFlow({
  required BuildContext context,
  required WidgetRef ref,
  required String contactId,
  required String instructions,
  required String language,
  String requestType = 'quick_draft',
  String? taskId, // For revisions
  String? revisionInstructions, // For revisions
}) async {
  // Show dialog immediately (like revisions do)
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return EnhancedDraftProgressDialog(
        contactId: contactId,
        instructions: instructions,
        language: language,
        requestType: requestType,
        taskId: taskId,
        revisionInstructions: revisionInstructions,
        parentContext: context,
      );
    },
  );

  return result ?? false;
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

  return Task(
    id: id,
    title: title,
    body: body,
    type: taskData['type'] as String? ?? 'message',
    status: taskData['status'] as String? ?? 'pending',
    userId: userId,
    contactId: contactId,
    createdBy: createdBy,
    createdOn:
        taskData['created_on'] != null
            ? DateTime.parse(taskData['created_on'] as String)
            : DateTime.now(),
    updatedOn:
        taskData['updated_on'] != null
            ? DateTime.parse(taskData['updated_on'] as String)
            : null,
    sms_url: taskData['sms_url'] as String?,
    contactDisplayName: taskData['contact_display_name'] as String?,
    assistant_message: taskData['assistant_message'] as String?,
    llm_provider: taskData['llm_provider'] as String?,
    accountId: taskData['account_id'] as String?,
  );
}
