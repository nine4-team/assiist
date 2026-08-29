import 'dart:async';
import 'dart:io'; // ADD for File type
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // For Theme, Card, etc.
import 'package:assiist_front_end/theme/app_styles.dart';
import 'package:image_picker/image_picker.dart'; // ADD image_picker
import 'package:file_picker/file_picker.dart'; // ADD file_picker
import 'package:assiist_front_end/core/models/contact.dart'; // Corrected path assuming lib/core/models
import 'package:assiist_front_end/widgets/select_or_add_contact.dart'; // IMPORT the new widget
import 'package:assiist_front_end/widgets/notes_input_field.dart'; // IMPORT the new notes widget
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Import Riverpod
import 'package:assiist_front_end/providers/repository_providers.dart'; // <<< IMPORT Repository Providers
import 'package:assiist_front_end/core/models/task.dart'; // <<< IMPORT Task model
import 'package:assiist_front_end/utils/navigation_helpers.dart'; // Import for template helpers
import 'package:assiist_front_end/core/models/attachment.dart'; // ADD attachment model
import 'package:assiist_front_end/providers/service_providers.dart'; // ADD for generationRequestServiceProvider
import 'package:assiist_front_end/core/errors/exceptions.dart'; // ADD for UnauthorizedException
import 'package:assiist_front_end/screens/contact_record_screen.dart'; // ADD for contactByIdProvider
import 'package:assiist_front_end/core/templates/note_templates.dart'; // ADD for NoteTemplates
import 'package:assiist_front_end/widgets/call_recording_widget.dart';

// --- State Enum ---
enum TextDraftOption { yes, skip } // Keep same enum

// ADD Attachment Type Enum
enum AttachmentType { none, image, document, link }

// RENAME class to LogNoteScreen
class LogNoteScreen extends ConsumerStatefulWidget {
  final Contact? initialContact;
  final String? potentialContactEmail; // ADD: Email from potential contact
  final String? appointmentTitle; // Appointment title
  final String? appointmentNotes; // Appointment description/notes
  final DateTime? appointmentTime; // ADDED: Current appointment time
  final String? completedTaskNotes; // ADD: Notes from a completed task
  final bool isDeleting; // ADD new parameter
  final Task? taskToModify; // ADD: Task to modify
  final bool isCompleting; // ADD: Whether we're completing the task
  final bool hideContactSelector; // ADD new parameter

  // Reschedule parameters
  final bool isRescheduled; // Whether this is a rescheduled appointment
  final DateTime? originalAppointmentTime; // Original time before reschedule
  final DateTime? newAppointmentTime; // New time after reschedule
  final String? rescheduleReason; // Reason for reschedule if available

  // Deep link parameters
  final String? deepLinkAppointmentId; // Appointment ID from deep link
  final List<String>? deepLinkContactIds; // Contact IDs from deep link
  final String? deepLinkPrefillType; // Prefill type from deep link

  const LogNoteScreen({
    super.key,
    this.initialContact,
    this.potentialContactEmail, // ADD to constructor
    this.appointmentTitle,
    this.appointmentNotes,
    this.appointmentTime, // ADDED
    this.completedTaskNotes, // ADD to constructor
    this.isDeleting = false, // Default to false
    this.taskToModify, // ADD to constructor
    this.isCompleting = false, // Default to false
    this.hideContactSelector = false, // Default to false
    this.isRescheduled = false, // Default to false
    this.originalAppointmentTime,
    this.newAppointmentTime,
    this.rescheduleReason,
    // Deep link parameters
    this.deepLinkAppointmentId,
    this.deepLinkContactIds,
    this.deepLinkPrefillType,
  }); // RENAME constructor

  @override
  // RENAME createState return type
  ConsumerState<LogNoteScreen> createState() => _LogNoteScreenState(); // RENAME state class instance

  // ---------------------------------------------------------------------------
  // Factory: Build LogNoteScreen from a deep-link URI
  // ---------------------------------------------------------------------------
  static LogNoteScreen fromDeepLink(Uri uri) {
    // Expect scheme assiist://log-note?.. query params
    final appointmentId = uri.queryParameters['appointment_id'];
    final contactIdsCsv = uri.queryParameters['contact_ids'];
    final prefillType = uri.queryParameters['prefill_type'];

    // Parse contact IDs from comma-separated string
    final contactIds =
        contactIdsCsv
            ?.split(',')
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toList();

    print(
      'Deep link parsed: appointmentId=$appointmentId, contactIds=$contactIds, prefillType=$prefillType',
    );

    return LogNoteScreen(
      // Pass deep link parameters to constructor
      deepLinkAppointmentId: appointmentId,
      deepLinkContactIds: contactIds,
      deepLinkPrefillType: prefillType,
      // Use deep link key for state management
      key: ValueKey('deeplink_$appointmentId'),
    );
  }
}

// RENAME state class
class _LogNoteScreenState extends ConsumerState<LogNoteScreen> {
  // RENAME state class type argument
  // --- State Variables (Copied from IosStyleLogInteractionScreen) ---
  final _notesController = TextEditingController();
  // If null, neither 'Yes' nor 'Skip' is selected initially
  TextDraftOption? _selectedTextDraftOption;

  bool _isSubmitting = false;

  // --- NEW Attachment State ---
  bool _isAttachmentSectionExpanded = false; // Default closed
  // TODO: Set initial value based on active task requirements if available
  final _attachmentUrlController = TextEditingController(); // RENAMED
  String? _pickedImageName; // Placeholder for picked image file info
  String? _pickedDocumentName; // Placeholder for picked document file info
  final _attachmentTitleController =
      TextEditingController(); // ADD title controller
  File? _pickedImageFile; // ADD state for picked image file
  File? _pickedDocumentFile; // ADD state for picked document file

  // NEW: Track uploaded attachments
  Attachment? _uploadedImageAttachment;
  Attachment? _uploadedDocumentAttachment;
  bool _isUploadingImage = false;
  bool _isUploadingDocument = false;
  // --- END NEW Attachment State ---

  // ADD State for selected attachment type
  AttachmentType _selectedAttachmentType = AttachmentType.none;

  // Focus Nodes for better UX potentially
  final FocusNode _notesFocusNode = FocusNode();

  // --- NEW State for Selected Contact (from Child Widget) ---
  Contact? _selectedContactForLog;
  // Global Key to access SelectOrAddContact state
  final GlobalKey<SelectOrAddContactState> _selectOrAddContactKey =
      GlobalKey<SelectOrAddContactState>();

  // Removed: Firestore listener state - using optimistic approach now

  @override
  void initState() {
    super.initState();
    // Do not default select any option for Immediate Follow Up

    // --- Prefill Notes ---
    if (widget.completedTaskNotes != null) {
      // PRIORITY 1: Notes from completed task
      _notesController.text = widget.completedTaskNotes!;
    } else if (widget.deepLinkAppointmentId != null) {
      // PRIORITY 2: Deep link from post-appointment notification
      _handleDeepLinkPrefill();
    } else if (widget.potentialContactEmail != null &&
        widget.appointmentTitle != null) {
      // PRIORITY 3: Potential contact add
      if (widget.isRescheduled && widget.originalAppointmentTime != null) {
        // Rescheduled appointment template
        _notesController
            .text = NavigationHelpers.buildRescheduledAppointmentNotes(
          widget.appointmentTitle!,
          widget.potentialContactEmail!,
          widget.originalAppointmentTime!,
          widget.newAppointmentTime ?? DateTime.now(),
          widget.rescheduleReason,
          widget.appointmentNotes,
        );
      } else {
        // New appointment template
        _notesController.text = NavigationHelpers.buildNewAppointmentNotes(
          widget.appointmentTitle!,
          widget.potentialContactEmail!,
          appointmentTime: widget.appointmentTime,
          appointmentNotes: widget.appointmentNotes,
        );
      }
    }
    // --- END Prefill ---

    // --- Handle initialContact passed directly ---
    if (widget.initialContact != null) {
      // Set the contact immediately
      _selectedContactForLog = widget.initialContact;

      // Also try to set it in the SelectOrAddContact widget
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectOrAddContactKey.currentState != null) {
          _selectOrAddContactKey.currentState!.selectContactExternally(
            widget.initialContact!,
          );
        }
      });
    }
    // --- END Handle initialContact ---
  }

  // Handle deep link prefill by fetching appointment data
  Future<void> _handleDeepLinkPrefill() async {
    if (widget.deepLinkAppointmentId == null) return;

    try {
      print(
        'Fetching appointment data for deep link: ${widget.deepLinkAppointmentId}',
      );

      // Fetch appointment data
      final appointmentRepo = ref.read(appointmentRepositoryProvider);
      final appointment = await appointmentRepo.getAppointmentById(
        widget.deepLinkAppointmentId!,
      );

      if (appointment != null) {
        print('Appointment data fetched: ${appointment.title}');

        // Pre-fill note content with post-appointment template
        final noteContent = NoteTemplates.postAppointmentTemplate(
          appointmentTitle: appointment.title,
          startTime: appointment.startTime ?? DateTime.now(),
          endTime: appointment.endTime ?? DateTime.now(),
          appointmentDescription: appointment.description,
        );

        if (mounted) {
          setState(() {
            _notesController.text = noteContent;
          });
        }

        // Pre-select contacts if available
        if (widget.deepLinkContactIds != null &&
            widget.deepLinkContactIds!.isNotEmpty) {
          _handleDeepLinkContactSelection();
        }
      } else {
        print('Appointment not found for ID: ${widget.deepLinkAppointmentId}');
        // Show error or fallback message
        if (mounted) {
          setState(() {
            _notesController.text =
                'Appointment not found. Please add your notes below:\n\n';
          });
        }
      }
    } catch (e) {
      print('Error fetching appointment data: $e');
      // Show error message but still allow user to enter notes
      if (mounted) {
        setState(() {
          _notesController.text =
              'Error loading appointment details. Please add your notes below:\n\n';
        });
      }
    }
  }

  // Handle contact selection from deep link
  Future<void> _handleDeepLinkContactSelection() async {
    if (widget.deepLinkContactIds == null || widget.deepLinkContactIds!.isEmpty)
      return;

    try {
      final contactRepo = ref.read(contactRepositoryProvider);
      final String firstContactId = widget.deepLinkContactIds!.first;

      print('Fetching contact data for deep link: $firstContactId');

      // Fetch the first contact (most deep links will have only one contact)
      final contact = await contactRepo.getContactById(firstContactId);

      if (contact != null && mounted) {
        setState(() {
          _selectedContactForLog = contact;
        });

        // Also try to set it in the SelectOrAddContact widget
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectOrAddContactKey.currentState != null) {
            _selectOrAddContactKey.currentState!.selectContactExternally(
              contact,
            );
          }
        });

        print('Contact selected from deep link: ${contact.displayName}');
      } else {
        print('Contact not found for ID: $firstContactId');
      }
    } catch (e) {
      print('Error fetching contact data: $e');
      // Continue without pre-selecting contact
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _notesFocusNode.dispose();
    _attachmentUrlController.dispose(); // RENAMED
    _attachmentTitleController.dispose(); // Dispose title controller
    super.dispose();
  }

  Future<void> updateAssistant() async {
    if (_isSubmitting) return;

    // Validate that a contact is selected
    if (_selectedContactForLog == null) {
      // Attempt to create a new contact from the add-contact form
      final contactCreated = await _createContactFromForm();
      if (!contactCreated) {
        // User didn't fill required fields or creation failed
        return;
      }
    }

    // Validate that notes are not empty
    if (_notesController.text.trim().isEmpty) {
      _showErrorDialog("Please enter some notes before logging.");
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Handle task state changes if we have a task to modify
      await _handleTaskModifications();

      // Check if we need to add the potential email to the selected contact
      await _addPotentialEmailToContact();

      // Build enhanced note content with attachments
      String enhancedNoteContent = _buildEnhancedNoteContent();

      print('📝 Enhanced note content: $enhancedNoteContent');
      print(
        '👤 Contact: ${_selectedContactForLog!.displayName} (${_selectedContactForLog!.id})',
      );

      // Submit optimistically - no listener needed
      final generationService = ref.read(generationRequestServiceProvider);
      final result = await generationService.submitNoteOptimistically(
        contactId: _selectedContactForLog!.id!,
        noteContent: enhancedNoteContent,
      );

      if (result.isSuccess) {
        print(
          '✅ Note submitted successfully for ${_selectedContactForLog!.displayName}',
        );

        // Invalidate providers to refresh timeline
        _invalidateProviders();

        // Show optimistic success dialog
        _showOptimisticSuccessDialog();
      } else {
        _showErrorDialog(
          'Failed to submit note: ${result.errorMessage ?? "Unknown error"}',
        );
      }
    } catch (e) {
      print("Error submitting log: $e");
      if (mounted) {
        String userFriendlyMessage = 'Failed to submit note';

        // Provide specific error messages based on error type
        if (e is UnauthorizedException) {
          userFriendlyMessage =
              'Authentication failed. Please check your internet connection and try again.';
        } else if (e.toString().contains('network-request-failed') ||
            e.toString().contains('timeout') ||
            e.toString().contains('unreachable') ||
            e.toString().contains('connection')) {
          userFriendlyMessage =
              'Network error. Please check your internet connection and try again.';
        } else if (e.toString().contains('User not authenticated')) {
          userFriendlyMessage =
              'Session expired. Please close the app and sign in again.';
        } else {
          userFriendlyMessage = 'Failed to submit note: ${e.toString()}';
        }

        _showErrorDialog(userFriendlyMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  // Helper method to handle task modifications (delete/complete)
  Future<void> _handleTaskModifications() async {
    if (widget.taskToModify != null) {
      final taskRepo = ref.read(taskRepositoryProvider);

      if (widget.isDeleting) {
        // Delete the task
        await taskRepo.deleteTask(
          widget.taskToModify!.id!,
          widget.taskToModify!.contactId!,
        );
      } else if (widget.isCompleting) {
        // Complete the task
        final updates = {
          'status': 'completed',
          'completed_at': DateTime.now().toIso8601String(),
        };
        await taskRepo.updateTask(
          widget.taskToModify!.id!,
          widget.taskToModify!.contactId!,
          updates,
        );
      }

      // Invalidate providers
      ref.invalidate(dashboardTasksProvider);
      ref.invalidate(tasksForContactProvider(widget.taskToModify!.contactId!));
    }
  }

  // Helper method to add potential email to selected contact if needed
  Future<void> _addPotentialEmailToContact() async {
    // Only proceed if we have both a selected contact and a potential email
    if (_selectedContactForLog == null ||
        widget.potentialContactEmail == null) {
      return;
    }

    final contact = _selectedContactForLog!;
    final emailToAdd = widget.potentialContactEmail!.trim();

    // Check if the contact already has this email
    final existingEmails = contact.emails ?? <EmailAddress>[];
    final hasEmail = existingEmails.any(
      (email) => email.address?.toLowerCase() == emailToAdd.toLowerCase(),
    );

    if (hasEmail) {
      // Contact already has this email, no need to add it
      return;
    }

    try {
      // Create a new email address with a default label
      final newEmail = EmailAddress(
        address: emailToAdd,
        label: 'Secondary', // Default label for emails from calendar events
      );

      // Create updated emails list
      final updatedEmails = [...existingEmails, newEmail];

      // Update the contact via repository
      final contactRepo = ref.read(contactRepositoryProvider);
      final updates = {'emails': updatedEmails.map((e) => e.toJson()).toList()};

      final updatedContact = await contactRepo.updateContact(
        contact.id,
        updates,
      );

      if (updatedContact != null) {
        // Update our local reference to the contact
        setState(() {
          _selectedContactForLog = updatedContact;
        });

        // Invalidate contact providers to refresh UI
        ref.invalidate(contactRepositoryProvider);
        ref.invalidate(contactByIdProvider(contact.id));

        print('✅ Added email $emailToAdd to contact ${contact.displayName}');
      }
    } catch (e) {
      print('❌ Failed to add email to contact: $e');
      // Don't throw here - we don't want to block note submission if email update fails
      // The note will still be logged, just without the email being added
    }
  }

  // Helper method to build enhanced note content with attachments
  String _buildEnhancedNoteContent() {
    String enhancedNoteContent = _notesController.text;

    // Append attachment URLs if any with structured format for better rendering
    List<Map<String, String>> attachments = [];
    if (_uploadedImageAttachment != null) {
      String imageTitle =
          _attachmentTitleController.text.isNotEmpty
              ? _attachmentTitleController.text
              : _uploadedImageAttachment!.originalFilename;
      attachments.add({
        'filename': imageTitle,
        'url': _uploadedImageAttachment!.publicUrl,
        'type': 'image',
      });
    }
    if (_uploadedDocumentAttachment != null) {
      String documentTitle =
          _attachmentTitleController.text.isNotEmpty
              ? _attachmentTitleController.text
              : _uploadedDocumentAttachment!.originalFilename;
      attachments.add({
        'filename': documentTitle,
        'url': _uploadedDocumentAttachment!.publicUrl,
        'type': 'document',
      });
    }
    if (_attachmentUrlController.text.isNotEmpty) {
      String linkTitle =
          _attachmentTitleController.text.isNotEmpty
              ? _attachmentTitleController.text
              : 'Link';
      attachments.add({
        'filename': linkTitle,
        'url': _attachmentUrlController.text,
        'type': 'link',
      });
    }

    if (attachments.isNotEmpty) {
      enhancedNoteContent += '\n\n---\nAttached Files:\n';
      for (Map<String, String> attachment in attachments) {
        // Use markdown-style link format for better rendering
        enhancedNoteContent +=
            '- [${attachment['filename']}](${attachment['url']})\n';
      }
    }

    // -------------------------------------------------------------------
    // Fill in deep-link contact IDs if the template placeholder is present
    // -------------------------------------------------------------------
    if (_selectedContactForLog?.id != null &&
        enhancedNoteContent.contains('{contact_ids}')) {
      enhancedNoteContent = enhancedNoteContent.replaceAll(
        '{contact_ids}',
        _selectedContactForLog!.id!,
      );
    }

    return enhancedNoteContent;
  }

  // Helper method to invalidate providers for UI refresh
  void _invalidateProviders() {
    ref.invalidate(notesForContactProvider(_selectedContactForLog!.id!));
    ref.invalidate(tasksForContactProvider(_selectedContactForLog!.id!));
    ref.invalidate(
      timelineEventsForContactProvider(_selectedContactForLog!.id!),
    );
  }

  // Show optimistic success dialog with auto-close
  void _showOptimisticSuccessDialog() {
    Timer? autoCloseTimer;

    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => CupertinoAlertDialog(
            title: const Text('Note Submitted'),
            content: Text(
              'Note submitted successfully for ${_selectedContactForLog!.displayName}. '
              'Your timeline will be updated shortly with AI insights.',
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () {
                  autoCloseTimer?.cancel(); // Cancel the auto-close timer
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context, true); // Close screen with success
                },
              ),
            ],
          ),
    );

    // Auto-close after 2 seconds (matching quick actions pattern)
    autoCloseTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pop(context); // Close dialog
        Navigator.pop(context, true); // Close screen with success
      }
    });
  }

  // Removed: Old Firestore listener methods - using optimistic approach now

  void _showErrorDialog(String message) {
    // Ensure it runs after the build phase if called during submit
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Enhance message if it's a known network error
        String enhancedMessage = message;
        if (message.contains('network-request-failed') ||
            message.contains('timeout') ||
            message.contains('unreachable') ||
            message.contains('connection')) {
          enhancedMessage =
              'Network error. Please check your internet connection and try again.';
        } else if (message.contains('User not authenticated') ||
            message.contains('token refresh failed')) {
          enhancedMessage =
              'Authentication failed. Please check your internet connection and try again.';
        }

        showCupertinoDialog(
          context: context,
          builder:
              (context) => CupertinoAlertDialog(
                title: const Text('Error'),
                content: Text(enhancedMessage),
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
    });
  }

  // --- Handlers ---

  // --- Placeholder Attachment Functions ---
  Future<void> _pickImage(ImageSource source) async {
    print("Attempting to pick image...");
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source);

      if (image != null && mounted) {
        print("Image picked: ${image.path}");
        final imageFile = File(image.path);

        setState(() {
          _pickedImageFile = imageFile;
          _pickedImageName = image.name;
          _pickedDocumentFile = null; // Clear other selections
          _pickedDocumentName = null;
          _uploadedDocumentAttachment = null;
          _attachmentUrlController.clear();
          _attachmentTitleController.clear();
          _selectedAttachmentType = AttachmentType.image;
          _isUploadingImage = true; // Show upload progress
        });

        // Upload the file to backend
        try {
          final attachmentService = ref.read(attachmentServiceProvider);
          final uploadedAttachment = await attachmentService.uploadFile(
            imageFile,
          );

          if (mounted) {
            setState(() {
              _uploadedImageAttachment = uploadedAttachment;
              _isUploadingImage = false;
            });
            print(
              "✅ Image uploaded successfully: ${uploadedAttachment.publicUrl}",
            );
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _isUploadingImage = false;
              _pickedImageFile = null;
              _pickedImageName = null;
            });
            _showErrorDialog("Failed to upload image: $e");
          }
        }
      } else {
        print("Image picking cancelled or failed.");
      }
    } catch (e) {
      print("Error picking image: $e");
      if (mounted) _showErrorDialog("Could not pick image: $e");
    }
  }

  Future<void> _pickDocument() async {
    print("Attempting to pick document...");
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'txt',
          'csv',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
        ],
      );

      if (result != null && result.files.single.path != null && mounted) {
        PlatformFile file = result.files.first;
        print("Document picked: ${file.name}");
        print("Path: ${file.path}");

        final documentFile = File(file.path!);

        setState(() {
          _pickedDocumentFile = documentFile;
          _pickedDocumentName = file.name;
          _pickedImageFile = null; // Clear other selections
          _pickedImageName = null;
          _uploadedImageAttachment = null;
          _attachmentUrlController.clear();
          _attachmentTitleController.clear();
          _selectedAttachmentType = AttachmentType.document;
          _isUploadingDocument = true; // Show upload progress
        });

        // Upload the file to backend
        try {
          final attachmentService = ref.read(attachmentServiceProvider);
          final uploadedAttachment = await attachmentService.uploadFile(
            documentFile,
          );

          if (mounted) {
            setState(() {
              _uploadedDocumentAttachment = uploadedAttachment;
              _isUploadingDocument = false;
            });
            print(
              "✅ Document uploaded successfully: ${uploadedAttachment.publicUrl}",
            );
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _isUploadingDocument = false;
              _pickedDocumentFile = null;
              _pickedDocumentName = null;
            });
            _showErrorDialog("Failed to upload document: $e");
          }
        }
      } else {
        print("Document picking cancelled or failed.");
      }
    } catch (e) {
      print("Error picking document: $e");
      if (mounted) _showErrorDialog("Could not pick document: $e");
    }
  }
  // --- END Placeholder Attachment Functions ---

  // --- NEW: Callback for SelectOrAddContact ---
  void _onContactSelectedForLog(Contact contact) {
    setState(() {
      _selectedContactForLog = contact;
      // We might want to clear the notes field when a new contact is selected?
      // _notesController.clear(); // Optional: Decide on UX
    });
    print("Log Screen: Contact Selected - ${contact.displayName}");
  }

  // --- Build Method (Redesigned) ---
  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    return CupertinoPageScaffold(
      backgroundColor: AppStyles.subtleBackgroundColor(context),
      child: SafeArea(
        bottom:
            false, // Allow content to go near bottom edge before scroll padding
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16.0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // --- Contact Section ---
                  if (!widget.hideContactSelector) // Only show if not hidden
                    _buildSectionCard(
                      context: context,
                      backgroundColor: AppStyles.cardBackgroundColor(context),
                      child: SelectOrAddContact(
                        key: _selectOrAddContactKey,
                        onContactSelected: _onContactSelectedForLog,
                        initialEmail: widget.potentialContactEmail,
                      ),
                    ),
                  if (!widget
                      .hideContactSelector) // Only show spacing if section is visible
                    const SizedBox(height: 20),

                  // --- Conditionally Display Potential Contact Email ---
                  if (widget.potentialContactEmail != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ADD Explanatory Text
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: 12.0,
                              left: 4.0,
                              right: 4.0,
                            ), // Added right padding
                            child: Text(
                              'Search above to add this email to an existing contact or click the \'+\' button to create a new contact.',
                              style: AppStyles.labelTextStyle(context),
                            ),
                          ),
                          // END ADD Explanatory Text
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: 4.0,
                              left: 4.0,
                            ),
                            child: Text(
                              'Email from Calendar Invite:', // Label
                              style: AppStyles.captionTextStyle(context),
                            ),
                          ),
                          SizedBox(
                            // MAKE SCREEN WIDTH
                            width: double.infinity,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 12.0,
                              ),
                              decoration: BoxDecoration(
                                color: CupertinoColors.tertiarySystemFill
                                    .resolveFrom(context),
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(
                                  color: CupertinoColors.systemGrey3
                                      .resolveFrom(context),
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                widget.potentialContactEmail!,
                                style: AppStyles.bodyTextStyle(context),
                              ),
                            ),
                          ), // END MAKE SCREEN WIDTH
                        ],
                      ),
                    ),
                  // --- END Conditional Display ---

                  // --- Notes Section ---
                  // Replace the old structure with the new widget
                  NotesInputField(
                    notesController: _notesController,
                    notesFocusNode: _notesFocusNode,
                    // Optional: Customize placeholder, min/max lines if needed
                    // placeholder: 'Log your notes here...',
                    minLines: 4, // CHANGE minLines back to 4
                    maxLines: null, // SET maxLines to null for auto-resizing
                  ),
                  const SizedBox(height: 20),

                  // --- Call Recording Transcription Widget ---
                  CallRecordingWidget(
                    contactId: _selectedContactForLog?.id,
                    onTranscriptionComplete: (transcription, audioUrl) {
                      setState(() {
                        _notesController.text +=
                            '\n\n---\nCall Recording Notes:\n$transcription\n\n[Audio Recording]($audioUrl)';
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  // --- NEW Attachment Section ---
                  // Wrap with Material for context if child widgets need it (e.g., InkWell)
                  Material(
                    type: MaterialType.transparency,
                    child:
                        _buildAttachmentSection(), // Add the new section here
                  ),
                  const SizedBox(height: 20),
                  // --- END NEW ---

                  // --- Follow Up Section ---
                  _buildSectionCard(
                    context: context,
                    backgroundColor: AppStyles.cardBackgroundColor(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Include Immediate Follow Up',
                            style: AppStyles.labelTextStyle(context).copyWith(
                              color: theme.primaryContrastingColor.withOpacity(
                                0.8,
                              ),
                            ),
                          ),
                          _buildTextDraftSelector(),
                        ],
                      ),
                    ),
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
                          ? Container(
                            padding: AppStyles.filledButtonPadding,
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemGrey4,
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: Text(
                              widget.isDeleting
                                  ? 'Delete'
                                  : widget.isCompleting
                                  ? 'Complete'
                                  : 'Log',
                              style: AppStyles.filledButtonTextStyle(
                                context,
                              ).copyWith(color: CupertinoColors.systemGrey),
                            ),
                          )
                          : AppStyles.filledButton(
                            context: context,
                            text:
                                widget.isDeleting
                                    ? 'Delete'
                                    : widget.isCompleting
                                    ? 'Complete'
                                    : 'Log',
                            onPressed: () {
                              updateAssistant();
                            },
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
    );
  }

  // --- Helper Widgets for Modern Design ---

  // Builds a styled card container for sections
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
          // Subtle shadow for depth (optional)
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

  // Custom TextField builder for modern look
  Widget _buildModernTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String placeholder,
    int? maxLines = 1,
    int? minLines,
    TextInputType? keyboardType,
    bool isRequired = false,
    bool readOnly = false,
    FocusNode? focusNode, // Default padding
    TextStyle? styleOverride,
    Function(String)? onChanged,
  }) {
    final theme = Theme.of(context);
    // final cupertinoTheme = CupertinoTheme.of(context); // No longer needed for placeholder color

    return CupertinoTextField(
      controller: controller,
      focusNode: focusNode,
      placeholder: placeholder + (isRequired ? ' *' : ''),
      placeholderStyle: AppStyles.placeholderTextStyle(
        context,
      ), // USE AppStyles directly
      maxLines: maxLines,
      minLines: minLines ?? maxLines,
      keyboardType: keyboardType,
      readOnly: readOnly,
      // Update decoration for rounded border
      decoration: BoxDecoration(
        color: AppStyles.inputBackgroundColor(context),
        borderRadius: BorderRadius.circular(8.0), // ADD rounded corners
      ),
      // Use AppStyles but allow overrides
      style:
          styleOverride ??
          AppStyles.inputTextStyle(context).copyWith(
            color:
                readOnly
                    ? AppStyles.secondaryTextColor(context)
                    : AppStyles.primaryTextColor(context),
          ),
      padding: AppStyles.defaultPadding, // Keep using default padding
      textAlignVertical: TextAlignVertical.center,
      // Cursor color from Material Theme wrapper in main.dart
      cursorColor: theme.textSelectionTheme.cursorColor,
      onChanged: onChanged,
    );
  }

  // ADD Original Text Draft Selector from iOS Style screen
  Widget _buildTextDraftSelector() {
    final theme = CupertinoTheme.of(context);
    // Use smart accent color system
    final Color selectedColor =
        AppStyles.useGradientAccent
            ? AppStyles.solidAccent
            : AppStyles.accentTextColor(context);
    final Color unselectedColor = CupertinoColors.systemGrey2;
    final Color selectedTextColor =
        AppStyles.useGradientAccent
            ? AppStyles.solidAccent
            : AppStyles.accentTextColor(context);
    final Color unselectedTextColor = CupertinoColors.systemGrey;

    return Row(
      children:
          TextDraftOption.values.map((option) {
            bool isSelected = _selectedTextDraftOption == option;
            return CupertinoButton(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 5.0,
              ),
              minSize: 0,
              // color: isSelected ? theme.primaryColor.withOpacity(0.2) : null,
              color:
                  isSelected
                      ? selectedColor.withOpacity(0.2)
                      : null, // Use defined color
              borderRadius: BorderRadius.circular(20.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSelected
                        ? CupertinoIcons.checkmark_alt_circle_fill
                        : CupertinoIcons.circle,
                    size: 16.0,
                    color:
                        isSelected
                            // ? theme.primaryColor
                            // : CupertinoColors.systemGrey2,
                            ? selectedColor
                            : unselectedColor,
                  ),
                  const SizedBox(width: 5.0),
                  Text(
                    option == TextDraftOption.yes ? 'Yes' : 'Skip',
                    style: AppStyles.captionTextStyle(context).copyWith(
                      color:
                          isSelected ? selectedTextColor : unselectedTextColor,
                      fontWeight:
                          isSelected ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
              onPressed: () {
                setState(() {
                  _selectedTextDraftOption = option;
                });
              },
            );
          }).toList(),
    );
  }

  // --- NEW: Build Attachment Section ---
  Widget _buildAttachmentSection() {
    final theme = CupertinoTheme.of(context);
    final bool isDarkMode = theme.brightness == Brightness.dark;

    // Helper widget to build file preview with better styling
    Widget buildFilePreview({
      required String fileName,
      required IconData icon,
      required VoidCallback onRemove,
      Color? iconColor,
      bool isUploading = false,
      bool isUploaded = false,
    }) {
      return Container(
        margin: const EdgeInsets.only(top: 12.0),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: const Color(
            0xFF2C2C2F,
          ), // Match unselected attachment type containers
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(
            color:
                isUploaded
                    ? CupertinoColors.systemGrey4.resolveFrom(context)
                    : CupertinoColors.systemGrey5.resolveFrom(context),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: CupertinoColors.tertiarySystemFill.resolveFrom(
                  context,
                ), // Match larger surrounding container
                borderRadius: BorderRadius.circular(8.0),
              ),
              child:
                  isUploading
                      ? const CupertinoActivityIndicator()
                      : isUploaded
                      ? AppStyles.accentIcon(
                        icon: CupertinoIcons.checkmark_circle_fill,
                        size: 20.0,
                      )
                      : Icon(
                        icon,
                        size: 20,
                        color:
                            iconColor ??
                            (AppStyles.useGradientAccent
                                ? AppStyles.solidAccent
                                : AppStyles.accentTextColor(context)),
                      ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: AppStyles.bodyTextStyle(
                      context,
                    ).copyWith(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  isUploaded
                      ? AppStyles.accentText(
                        context,
                        'Uploaded successfully',
                        style: AppStyles.captionTextStyle(context),
                      )
                      : Text(
                        isUploading ? 'Uploading...' : 'Tap to remove',
                        style: AppStyles.captionTextStyle(context).copyWith(
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                ],
              ),
            ),
            if (!isUploading)
              CupertinoButton(
                padding: const EdgeInsets.all(4.0),
                minSize: 0,
                child: Container(
                  padding: const EdgeInsets.all(4.0),
                  decoration: BoxDecoration(
                    color: CupertinoColors.tertiarySystemFill.resolveFrom(
                      context,
                    ), // Match larger surrounding container
                    borderRadius: BorderRadius.circular(6.0),
                  ),
                  child: AppStyles.accentIcon(
                    icon: CupertinoIcons.xmark,
                    size: 14.0,
                  ),
                ),
                onPressed: onRemove,
              ),
          ],
        ),
      );
    }

    // Enhanced upload button
    Widget buildUploadButton({
      required String label,
      required IconData icon,
      required VoidCallback onPressed,
      Color? backgroundColor,
    }) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
          decoration: BoxDecoration(
            color:
                backgroundColor, // Remove default background, only use if explicitly provided
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(
              color: CupertinoColors.systemGrey2.resolveFrom(
                context,
              ), // Match Link URL text box border
              width:
                  AppStyles
                      .dividerThickness, // Match text input border width (0.5)
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppStyles.accentIcon(icon: icon, size: 22),
              const SizedBox(width: 12),
              AppStyles.accentText(
                context,
                label,
                style: AppStyles.buttonTextStyle(
                  context,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    // Helper widget to build the input area based on selected type
    Widget buildInputArea() {
      switch (_selectedAttachmentType) {
        case AttachmentType.image:
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              if (_pickedImageName == null)
                buildUploadButton(
                  label: 'Choose Image',
                  icon: CupertinoIcons.photo_camera_solid,
                  onPressed: () => _pickImage(ImageSource.gallery),
                )
              else ...[
                buildFilePreview(
                  fileName: _pickedImageName!,
                  icon: CupertinoIcons.photo_fill,
                  iconColor: CupertinoColors.systemBlue,
                  isUploading: _isUploadingImage,
                  isUploaded: _uploadedImageAttachment != null,
                  onRemove:
                      () => setState(() {
                        _pickedImageName = null;
                        _pickedImageFile = null;
                        _uploadedImageAttachment = null;
                        _attachmentTitleController.clear();
                      }),
                ),
                const SizedBox(height: 12),
                _buildModernTextField(
                  context: context,
                  controller: _attachmentTitleController,
                  placeholder: 'Attachment Title (Optional)',
                ),
              ],
            ],
          );
        case AttachmentType.document:
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              if (_pickedDocumentName == null)
                buildUploadButton(
                  label: 'Choose Document',
                  icon: CupertinoIcons.doc_fill,
                  onPressed: _pickDocument,
                )
              else ...[
                buildFilePreview(
                  fileName: _pickedDocumentName!,
                  icon: CupertinoIcons.doc_text_fill,
                  iconColor: CupertinoColors.systemOrange,
                  isUploading: _isUploadingDocument,
                  isUploaded: _uploadedDocumentAttachment != null,
                  onRemove:
                      () => setState(() {
                        _pickedDocumentName = null;
                        _pickedDocumentFile = null;
                        _uploadedDocumentAttachment = null;
                        _attachmentTitleController.clear();
                      }),
                ),
                const SizedBox(height: 12),
                _buildModernTextField(
                  context: context,
                  controller: _attachmentTitleController,
                  placeholder: 'Attachment Title (Optional)',
                ),
              ],
            ],
          );
        case AttachmentType.link:
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              _buildModernTextField(
                context: context,
                controller: _attachmentUrlController,
                placeholder: 'Paste URL (https://...)',
                keyboardType: TextInputType.url,
                onChanged: (value) {
                  if (value.isNotEmpty &&
                      (_pickedImageName != null ||
                          _pickedDocumentName != null)) {
                    setState(() {
                      _pickedImageName = null;
                      _pickedDocumentName = null;
                      _pickedImageFile = null;
                      _pickedDocumentFile = null;
                    });
                  }
                  setState(() {});
                },
              ),
              if (_attachmentUrlController.text.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildModernTextField(
                  context: context,
                  controller: _attachmentTitleController,
                  placeholder: 'Link Title (Optional)',
                ),
              ],
            ],
          );
        case AttachmentType.none:
        default:
          return const SizedBox.shrink();
      }
    }

    return _buildSectionCard(
      context: context,
      backgroundColor: AppStyles.cardBackgroundColor(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Enhanced Collapsible Header
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () {
              setState(() {
                _isAttachmentSectionExpanded = !_isAttachmentSectionExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6.0),
                        decoration: BoxDecoration(
                          color: CupertinoColors.black.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: AppStyles.accentIcon(
                          icon: CupertinoIcons.paperclip,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Attachment',
                            style: AppStyles.h3StandardTextStyle(context),
                          ),
                          Text(
                            'Optional - Images, documents, or links',
                            style: AppStyles.captionTextStyle(context).copyWith(
                              color: CupertinoColors.secondaryLabel.resolveFrom(
                                context,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(4.0),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGrey5.resolveFrom(context),
                      borderRadius: BorderRadius.circular(6.0),
                    ),
                    child: Icon(
                      _isAttachmentSectionExpanded
                          ? CupertinoIcons.chevron_up
                          : CupertinoIcons.chevron_down,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Animated Collapsible Content
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: Visibility(
              visible: _isAttachmentSectionExpanded,
              child: Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Enhanced Attachment Type Selector
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: CupertinoSlidingSegmentedControl<AttachmentType>(
                        backgroundColor: AppStyles.segmentedTrackColor(context),
                        thumbColor: AppStyles.segmentedThumbColor(context),
                        groupValue: _selectedAttachmentType,
                        onValueChanged: (AttachmentType? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _selectedAttachmentType = newValue;
                              // Clear irrelevant fields when switching
                              if (newValue != AttachmentType.image) {
                                _pickedImageFile = null;
                                _pickedImageName = null;
                              }
                              if (newValue != AttachmentType.document) {
                                _pickedDocumentFile = null;
                                _pickedDocumentName = null;
                              }
                              if (newValue != AttachmentType.link) {
                                _attachmentUrlController.clear();
                              }
                              _attachmentTitleController.clear();
                            });
                          }
                        },
                        children: <AttachmentType, Widget>{
                          AttachmentType.none: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Text(
                              'None',
                              style: TextStyle(
                                color:
                                    _selectedAttachmentType ==
                                            AttachmentType.none
                                        ? CupertinoColors.white
                                        : CupertinoColors.label.resolveFrom(
                                          context,
                                        ),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          AttachmentType.image: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _selectedAttachmentType == AttachmentType.image
                                    ? Icon(
                                      CupertinoIcons.photo_fill,
                                      size: 16,
                                      color: CupertinoColors.white,
                                    )
                                    : AppStyles.accentIcon(
                                      icon: CupertinoIcons.photo_fill,
                                      size: 16,
                                    ),
                                const SizedBox(width: 6),
                                Text(
                                  'Img',
                                  style: TextStyle(
                                    color:
                                        _selectedAttachmentType ==
                                                AttachmentType.image
                                            ? CupertinoColors.white
                                            : CupertinoColors.label.resolveFrom(
                                              context,
                                            ),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AttachmentType.document: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _selectedAttachmentType ==
                                        AttachmentType.document
                                    ? Icon(
                                      CupertinoIcons.doc_fill,
                                      size: 16,
                                      color: CupertinoColors.white,
                                    )
                                    : AppStyles.accentIcon(
                                      icon: CupertinoIcons.doc_fill,
                                      size: 16,
                                    ),
                                const SizedBox(width: 6),
                                Text(
                                  'Doc',
                                  style: TextStyle(
                                    color:
                                        _selectedAttachmentType ==
                                                AttachmentType.document
                                            ? CupertinoColors.white
                                            : CupertinoColors.label.resolveFrom(
                                              context,
                                            ),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AttachmentType.link: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _selectedAttachmentType == AttachmentType.link
                                    ? Icon(
                                      CupertinoIcons.link,
                                      size: 16,
                                      color: CupertinoColors.white,
                                    )
                                    : AppStyles.accentIcon(
                                      icon: CupertinoIcons.link,
                                      size: 16,
                                    ),
                                const SizedBox(width: 6),
                                Text(
                                  'Link',
                                  style: TextStyle(
                                    color:
                                        _selectedAttachmentType ==
                                                AttachmentType.link
                                            ? CupertinoColors.white
                                            : CupertinoColors.label.resolveFrom(
                                              context,
                                            ),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        },
                      ),
                    ),
                    // Conditional Input Area based on selection
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: buildInputArea(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- END NEW ---

  // Tries to create a new contact using data from SelectOrAddContact form.
  // Returns true if a contact is now available.
  Future<bool> _createContactFromForm() async {
    // Access the child widget state
    final selectOrAddState = _selectOrAddContactKey.currentState;
    if (selectOrAddState == null) {
      _showErrorDialog("Unable to access contact form.");
      return false;
    }

    final details = selectOrAddState.getNewContactDetails();

    // Basic validation – require first name & phone OR email
    final firstName = details['first_name']?.trim();
    final phone = details['phone']?.trim();
    final email = details['email']?.trim();

    if (firstName == null ||
        firstName.isEmpty ||
        ((phone?.isEmpty ?? true) && (email?.isEmpty ?? true))) {
      _showErrorDialog(
        "Please enter at least a first name and a phone or email for the new contact.",
      );
      return false;
    }

    try {
      final contactRepo = ref.read(contactRepositoryProvider);

      final newContact = Contact(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        first_name: firstName,
        last_name: details['last_name']?.nullIfEmpty,
        addressed_as: details['addressed_as']?.nullIfEmpty,
        business_name: details['business_name']?.nullIfEmpty,
        business_type: details['business_type']?.nullIfEmpty,
        emails:
            (email != null && email.isNotEmpty)
                ? [EmailAddress(address: email)]
                : <EmailAddress>[],
        phone_numbers:
            (phone != null && phone.isNotEmpty)
                ? [PhoneNumber(number: phone)]
                : <PhoneNumber>[],
        is_deleted: false,
      );

      final created = await contactRepo.createContact(newContact);

      setState(() {
        _selectedContactForLog = created;
      });

      return true;
    } catch (e) {
      _showErrorDialog("Failed to create contact: $e");
      return false;
    }
  }
}

// --- Helper to Build Subtitle Text --- //
// FIX: Update function signature and logic to handle lists
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

// --- ADD String extension for nullIfEmpty ---
extension StringExtension on String {
  String? get nullIfEmpty => trim().isEmpty ? null : this;
}
