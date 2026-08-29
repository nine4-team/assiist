import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:assiist_front_end/theme/app_styles.dart';
import 'package:assiist_front_end/widgets/standard_modal_sheet.dart';
import 'package:assiist_front_end/widgets/notes_input_field.dart';
import 'package:assiist_front_end/core/models/feedback.dart';
import 'package:assiist_front_end/providers/repository_providers.dart';

class FeedbackModal extends ConsumerStatefulWidget {
  const FeedbackModal({super.key});

  @override
  ConsumerState<FeedbackModal> createState() => _FeedbackModalState();
}

class _FeedbackModalState extends ConsumerState<FeedbackModal> {
  final _feedbackController = TextEditingController();
  final _feedbackFocusNode = FocusNode();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _feedbackController.dispose();
    _feedbackFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    final feedbackText = _feedbackController.text.trim();
    if (feedbackText.isEmpty) {
      _showErrorDialog('Please enter your feedback before submitting.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final feedbackRepo = ref.read(feedbackRepositoryProvider);

      // Get platform and app version info
      final platform = _getPlatform();
      final appVersion = await _getAppVersion();

      final request = FeedbackSubmissionRequest(
        feedbackText: feedbackText,
        feedbackType: 'general',
        platform: platform,
        screenContext: _getScreenContext(),
        appVersion: appVersion,
      );

      await feedbackRepo.submitFeedback(request);

      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Failed to submit feedback. Please try again.');
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _getPlatform() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return 'unknown';
    }
  }

  String _getScreenContext() {
    // Determine which screen the feedback was submitted from
    final route = ModalRoute.of(context);
    return route?.settings.name ?? 'unknown';
  }

  Future<String?> _getAppVersion() async {
    // TODO: Add package_info_plus dependency to get actual app version
    // For now, return null
    return null;
  }

  void _showErrorDialog(String message) {
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

  void _showSuccessDialog() {
    showCupertinoDialog(
      context: context,
      builder:
          (context) => CupertinoAlertDialog(
            title: const Text('Thank You!'),
            content: const Text(
              'Your feedback has been submitted successfully.',
            ),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                child: const Text('OK'),
                onPressed: () {
                  Navigator.pop(context); // Close success dialog
                  Navigator.pop(context); // Close feedback modal
                },
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StandardModalSheet(
      title: 'Send Feedback',
      icon: CupertinoIcons.chat_bubble_text,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Instructions text
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: AppStyles.subtleBackgroundColor(context),
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Text(
              'We\'d love to hear your thoughts! Share your feedback, suggestions, or report any issues. You can type or use the microphone to record your message.',
              style: AppStyles.captionTextStyle(context),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          // Feedback input field with audio functionality
          NotesInputField(
            notesController: _feedbackController,
            notesFocusNode: _feedbackFocusNode,
            placeholder:
                'Share your feedback, suggestions, or report issues...',
            minLines: 4,
            maxLines: 8,
          ),
        ],
      ),
      cancelText: 'Cancel',
      saveText: _isSubmitting ? 'Submitting...' : 'Submit Feedback',
      onCancel: () => Navigator.pop(context),
      onSave: _isSubmitting ? () {} : _submitFeedback,
    );
  }
}

// Function to show the feedback modal
Future<void> showFeedbackModal(BuildContext context) async {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (BuildContext modalContext) {
      return const FeedbackModal();
    },
  );
}
