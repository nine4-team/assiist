import 'dart:async'; // Added for Timer
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // Needed for Theme.of(context)
import 'package:speech_to_text/speech_recognition_result.dart'; // Added
import 'package:speech_to_text/speech_to_text.dart'; // Added
import 'package:audio_waveforms/audio_waveforms.dart'; // Added
import 'package:assiist_front_end/theme/app_styles.dart';
import 'audio_controls_decorator.dart'; // Added
import 'package:assiist_front_end/services/audio_service.dart';
import 'vip_components.dart'; // Import VIP components

// Convert to StatefulWidget
class AddContactForm extends StatefulWidget {
  // BASIC controllers passed from SelectOrAddContact
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController companyController; // For business_name
  final TextEditingController addressedAsController;
  final TextEditingController businessTypeController;
  final TextEditingController relationshipInfoController;

  final Map<String, String>? labels; // Add labels parameter

  const AddContactForm({
    super.key,
    required this.firstNameController,
    required this.lastNameController,
    required this.phoneController,
    required this.emailController,
    required this.companyController,
    required this.addressedAsController,
    required this.businessTypeController,
    required this.relationshipInfoController,
    this.labels, // Make labels optional
    // REMOVE initialContact, onDateOfBirthChanged and other complex parameters
  });

  @override
  State<AddContactForm> createState() => _AddContactFormState();
}

class _AddContactFormState extends State<AddContactForm> {
  // --- Speech Recognition State (Only for relationshipInfoController) ---
  bool _isListening = false;
  // REMOVE: bool _isProcessing = false; // Not used here
  bool _isInitializing = true;
  Timer? _recordingTimer;
  Duration _elapsedTime = Duration.zero;
  late final RecorderController _recorderController;
  final FocusNode _relationshipInfoFocusNode = FocusNode();
  final String _fieldId =
      'add_contact_form_relationship_${DateTime.now().millisecondsSinceEpoch}';

  // REMOVE state variables for complex fields: _selectedDateOfBirth, _phoneEntries, _emailEntries, _addressEntries etc.
  // REMOVE FocusNodes for fields other than relationshipInfo (if they existed and are not needed for basic form flow)

  @override
  void initState() {
    super.initState();
    _recorderController = AudioService().getRecorderController(_fieldId);
    _initializeInBackground();
    // REMOVE initialization logic for complex fields
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _relationshipInfoFocusNode.dispose();
    AudioService().dispose(_fieldId);
    // REMOVE disposal of controllers for complex fields (as they are owned by parent or removed)
    super.dispose();
  }

  Future<void> _initializeInBackground() async {
    // Initialize AudioService for speech-to-text
    try {
      final audioService = AudioService();
      await audioService.initialize();
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    } catch (e) {
      print("Error during audio service initialization: $e");
      if (mounted) {
        setState(() => _isInitializing = false); // Still allow form to build
      }
    }
  }

  void _startListening() async {
    if (_isInitializing || !AudioService().isReady || _isListening || !mounted)
      return;

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
      setState(
        () => _elapsedTime = Duration(seconds: _elapsedTime.inSeconds + 1),
      );
    });

    try {
      await AudioService().startListening(
        fieldId: _fieldId,
        onResult: _onSpeechResult, // Corrected callback name
      );
    } catch (e) {
      print("Error starting speech recognition: $e");
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
      print("Error stopping speech recognition: $e");
    }
    if (mounted) {
      setState(() => _isListening = false);
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (result.finalResult && result.recognizedWords.isNotEmpty && mounted) {
      setState(() {
        // Target the relationshipInfoController
        final currentText = widget.relationshipInfoController.text;
        final selection = widget.relationshipInfoController.selection;
        final newText = currentText.replaceRange(
          selection.start,
          selection.end,
          '${result.recognizedWords} ', // Add a space after insertion
        );
        widget.relationshipInfoController.text = newText;
        widget
            .relationshipInfoController
            .selection = TextSelection.fromPosition(
          TextPosition(
            offset: selection.start + result.recognizedWords.length + 1,
          ),
        );
      });
    }
  }

  void _handleMicPressed() async {
    if (_isInitializing || !AudioService().isReady) return;
    if (!_isListening) {
      _startListening();
      _relationshipInfoFocusNode
          .requestFocus(); // Focus on the field being transcribed
    } else {
      _stopListening();
    }
  }

  void _cancelListening() {
    _stopListening();
    // No need to clear text here as it's a simple append/replace
  }

  // REMOVE methods related to complex field management: _addPhoneEntry, _removePhoneEntry, _updateAddress, _showDatePicker, etc.

  @override
  Widget build(BuildContext context) {
    const double verticalSpacing = 16.0;
    const double horizontalSpacing = 12.0;

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: First Name / Last Name
          Row(
            children: [
              Expanded(
                child: _buildModernTextField(
                  context: context,
                  controller: widget.firstNameController,
                  placeholder: 'First name',
                  isRequired: true,
                ),
              ),
              const SizedBox(width: horizontalSpacing),
              Expanded(
                child: _buildModernTextField(
                  context: context,
                  controller: widget.lastNameController,
                  placeholder: 'Last name',
                ),
              ),
            ],
          ),
          const SizedBox(height: verticalSpacing),

          // Addressed As (Full width)
          _buildModernTextField(
            context: context,
            controller: widget.addressedAsController,
            placeholder: 'Addressed As (e.g., nickname)',
          ),
          const SizedBox(height: verticalSpacing),

          // Row 2: Phone / Email
          Row(
            children: [
              Expanded(
                child: _buildModernTextField(
                  context: context,
                  controller: widget.phoneController,
                  placeholder: 'Phone',
                  keyboardType: TextInputType.phone,
                  isRequired:
                      true, // Assuming phone is required for a basic new contact
                ),
              ),
              const SizedBox(width: horizontalSpacing),
              Expanded(
                child: _buildModernTextField(
                  context: context,
                  controller: widget.emailController,
                  placeholder: 'Email',
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
            ],
          ),
          const SizedBox(height: verticalSpacing),

          // Row 3: Company / Business Type
          Row(
            children: [
              Expanded(
                child: _buildModernTextField(
                  context: context,
                  controller: widget.companyController, // For business_name
                  placeholder: 'Business Name',
                ),
              ),
              const SizedBox(width: horizontalSpacing),
              Expanded(
                child: _buildModernTextField(
                  context: context,
                  controller: widget.businessTypeController,
                  placeholder: 'Business Type',
                ),
              ),
            ],
          ),
          const SizedBox(height: verticalSpacing),

          // Relationship Info with Audio Controls (for the basic relationship/notes field)
          Material(
            // Ensures InkWell/splash effects work correctly if AudioControlsDecorator uses them
            type: MaterialType.transparency,
            child: AudioControlsDecorator(
              isListening: _isListening,
              elapsedTime: _elapsedTime,
              onMicPressed: _handleMicPressed,
              onCancelPressed: _cancelListening,
              recorderController: _recorderController,
              child: Stack(
                children: [
                  _buildModernTextField(
                    context: context,
                    controller: widget.relationshipInfoController,
                    focusNode: _relationshipInfoFocusNode,
                    placeholder: 'Contact / Relationship Notes',
                    maxLines: 8,
                    minLines: 4,
                    keyboardType: TextInputType.multiline,
                    padding: const EdgeInsets.only(
                      left: 12,
                      right: 12,
                      top:
                          60, // INCREASED top padding for more space below caption
                      bottom: 12,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 12,
                    right: 12,
                    child: Text(
                      'Add context about the contact and your relationship (where and how you met, their relevance to your business, info their family, occupation, etc.)',
                      style: AppStyles.placeholderTextStyle(context).copyWith(
                        fontSize: 12.0,
                        color: CupertinoColors.systemGrey,
                        height: 1.2, // Add line height for better readability
                      ),
                      maxLines: 3, // Allow up to 3 lines
                      overflow:
                          TextOverflow.ellipsis, // Handle overflow gracefully
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(
            height: verticalSpacing,
          ), // Add some spacing at the bottom if needed
          // REMOVE all UI for complex fields (Date of Birth, multiple phones/emails/addresses, PersonalDetails, BusinessDetails, etc.)
          // REMOVE Save Button if it was part of this form (usually handled by parent)
        ],
      ),
    );
  }

  // Helper Method: _buildModernTextField (general purpose, can be kept)
  Widget _buildModernTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String placeholder,
    bool isRequired = false,
    TextInputType? keyboardType,
    int? maxLines = 1,
    int? minLines,
    bool readOnly = false,
    FocusNode? focusNode,
    // REMOVE parameters specific to complex fields: type, fieldKey, index, isRemovable, onRemove, showMicButton, onMicPressed for non-relationship fields
    EdgeInsets padding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 12,
    ),
    TextStyle? styleOverride,
    Function(String)? onChanged,
  }) {
    final textField = CupertinoTextField(
      controller: controller,
      focusNode: focusNode,
      placeholder: placeholder + (isRequired ? ' *' : ''),
      placeholderStyle: AppStyles.placeholderTextStyle(context),
      maxLines: maxLines,
      minLines: minLines ?? maxLines,
      keyboardType: keyboardType,
      readOnly: readOnly,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(
          color: CupertinoColors.systemGrey2.resolveFrom(context),
          width: 0.5,
        ),
      ),
      style:
          styleOverride ??
          AppStyles.inputTextStyle(context).copyWith(
            color:
                readOnly
                    ? AppStyles.secondaryTextColor(context)
                    : AppStyles.primaryTextColor(context),
          ),
      padding: padding,
      textAlignVertical: TextAlignVertical.center,
      cursorColor: AppStyles.solidAccent, // Use AppStyles accent system
      onChanged: onChanged,
    );

    return textField;
  }

  // REMOVE other helper methods like _buildSectionTitle, _buildRemovableField, _buildAddressEntry, _buildLongTextFieldWithSpeech (if it was separate from relationship), etc.
}
