import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // For Theme access if needed later
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:assiist_front_end/services/audio_service.dart';

import 'package:assiist_front_end/theme/app_styles.dart';
import '../widgets/audio_controls_decorator.dart'; // Will be used later
import 'package:assiist_front_end/utils/formatting_utils.dart'; // Might be needed

class NotesInputField extends StatefulWidget {
  final TextEditingController notesController;
  final FocusNode notesFocusNode;
  final String placeholder;
  final int minLines;
  final int? maxLines;

  const NotesInputField({
    super.key,
    required this.notesController,
    required this.notesFocusNode,
    this.placeholder = 'Record important details...',
    this.minLines = 4,
    this.maxLines = 6,
  });

  @override
  State<NotesInputField> createState() => _NotesInputFieldState();
}

class _NotesInputFieldState extends State<NotesInputField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isListening = false;
  bool _isProcessing = false;
  bool _isInitializing = true;
  Timer? _recordingTimer;
  Duration _elapsedTime = Duration.zero;
  late final RecorderController _recorderController;
  final String _fieldId =
      'notes_input_${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _recorderController = AudioService().getRecorderController(_fieldId);
    _initializeInBackground();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
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

  void _startListening() async {
    if (_isInitializing) {
      print("Still initializing speech recognition...");
      return;
    }

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
    // Use widget.notesController here
    if (result.finalResult && result.recognizedWords.isNotEmpty) {
      if (!mounted) return;

      // Use the controller passed via the widget
      final controller = widget.notesController;
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

      // No need for setState here as controller updates trigger rebuilds where needed.
    }
    // Consider handling partial results if needed for live feedback
  }

  // --- Handlers (Moved from LogInteractionScreen) ---
  void _handleMicPressed() async {
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
      _focusNode.requestFocus();
    } else {
      _stopListening();
    }
  }

  void _cancelListening() {
    print("CANCEL: Cancel requested. Calling _stopListening...");
    // TODO: Decide if cancelling should also clear the text field
    _stopListening();
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    // Wrap with Material for context needed by children (like InkWell in AudioControlsDecorator)
    return Material(
      type: MaterialType.transparency,
      child: _buildSectionCard(
        context: context,
        backgroundColor: AppStyles.cardBackgroundColor(context),
        child: AudioControlsDecorator(
          isListening: _isListening,
          elapsedTime: _elapsedTime,
          onMicPressed: _handleMicPressed,
          onCancelPressed: _cancelListening,
          recorderController: _recorderController,
          // The child is the actual text field built using the helper
          child: _buildModernTextField(
            context: context,
            controller: widget.notesController, // Use controller from widget
            focusNode: widget.notesFocusNode, // Use focus node from widget
            placeholder: widget.placeholder, // Use placeholder from widget
            maxLines: widget.maxLines, // Use maxLines from widget
            minLines: widget.minLines, // Use minLines from widget
            keyboardType: TextInputType.multiline,
          ),
        ),
      ),
    );
  }

  // --- Helper Widgets (Will be moved/adapted here) ---

  // Builds a styled card container for sections (Can be moved to a common place later if needed)
  Widget _buildSectionCard({
    required BuildContext context,
    required Widget child,
    required Color backgroundColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: child,
    );
  }

  // Custom TextField builder (Can be moved to a common place later if needed)
  Widget _buildModernTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String placeholder,
    int? maxLines = 1,
    int? minLines,
    TextInputType? keyboardType,
    bool isRequired = false,
    bool readOnly = false,
    FocusNode? focusNode,
    TextStyle? styleOverride,
    Function(String)? onChanged,
  }) {
    final theme = Theme.of(context);

    return CupertinoTextField(
      controller: controller,
      focusNode: focusNode,
      placeholder: placeholder + (isRequired ? ' *' : ''),
      placeholderStyle: AppStyles.placeholderTextStyle(context),
      maxLines: maxLines,
      minLines: minLines ?? maxLines,
      keyboardType: keyboardType,
      readOnly: readOnly,
      decoration: BoxDecoration(
        color: AppStyles.inputBackgroundColor(context),
        borderRadius: BorderRadius.circular(8.0),
      ),
      style:
          styleOverride ??
          AppStyles.inputTextStyle(context).copyWith(
            color:
                readOnly
                    ? AppStyles.secondaryTextColor(context)
                    : AppStyles.primaryTextColor(context),
          ),
      padding: AppStyles.defaultPadding,
      textAlignVertical: TextAlignVertical.center,
      cursorColor: theme.textSelectionTheme.cursorColor,
      onChanged: onChanged,
    );
  }
}
