import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:intl/intl.dart';

import 'package:assiist_front_end/core/models/contact.dart';
import 'package:assiist_front_end/theme/app_styles.dart';
import 'package:assiist_front_end/services/audio_service.dart';
import 'audio_controls_decorator.dart'; // For speech-to-text UI

// Entry types for dynamic fields
enum _EntryType { phone, email, address }

class EditContactForm extends StatefulWidget {
  final Contact contact;
  final Function(Contact updatedContact)
  onSave; // Callback when save is pressed
  final Map<String, String>? labels; // Optional labels for fields

  const EditContactForm({
    super.key,
    required this.contact,
    required this.onSave,
    this.labels,
  });

  @override
  State<EditContactForm> createState() => EditContactFormState();
}

class EditContactFormState extends State<EditContactForm> {
  // --- Main Contact Field Controllers ---
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _addressedAsController;
  late TextEditingController _businessNameController; // Formerly company
  late TextEditingController _businessTypeController;
  late TextEditingController _sourceController;
  // TODO: Add tags controller if needed (e.g., comma-separated string or chip input)

  // --- Date of Birth ---
  DateTime? _selectedDateOfBirth;
  late TextEditingController _dateOfBirthController;

  // --- Dynamic Entry Lists (Phone, Email, Address) ---
  // Each entry will have its own set of controllers
  final List<_PhoneEntry> _phoneEntries = [];
  final List<_EmailEntry> _emailEntries = [];
  final List<_AddressEntry> _addressEntries = [];
  final List<_BusinessOpportunityEntry> _businessOpportunityEntries =
      []; // New list for business opportunities

  // --- Personal Details Controllers ---
  late TextEditingController _personalFamilyController;
  late TextEditingController _personalOccupationController;
  late TextEditingController _personalRecreationController;
  late TextEditingController _personalDreamsController;
  late TextEditingController _personalAdditionalInfoController;

  // --- Relationship Details Controller (assuming one main relationship notes field per user for now) ---
  // For simplicity, we might only allow editing relationship notes for the current user.
  // If multiple users' notes are to be edited, this needs a more complex UI.
  late TextEditingController _relationshipDetailsController;

  // --- Business Details Controllers ---
  late TextEditingController _bizOppDescriptionController;
  late TextEditingController _bizOppLatestDevController;

  // --- Speech Recognition State (example for one field, can be reused) ---
  final Map<String, _SpeechState> _speechStates = {};

  // Focus Nodes (add as needed for better UX)
  final FocusNode _notesFocusNode = FocusNode(); // Example

  @override
  void initState() {
    super.initState();
    _initializeControllers(widget.contact);
  }

  void _initializeControllers(Contact contact) {
    _firstNameController = TextEditingController(text: contact.first_name);
    _lastNameController = TextEditingController(text: contact.last_name);
    _addressedAsController = TextEditingController(text: contact.addressed_as);
    _businessNameController = TextEditingController(
      text: contact.business_name,
    );
    _businessTypeController = TextEditingController(
      text: contact.business_type,
    );
    _sourceController = TextEditingController(text: contact.source);

    _selectedDateOfBirth = contact.date_of_birth;
    _dateOfBirthController = TextEditingController(
      text:
          contact.date_of_birth != null
              ? DateFormat.yMd().format(contact.date_of_birth!)
              : '',
    );

    // Initialize dynamic entries
    _phoneEntries.clear();
    contact.phone_numbers?.forEach((pn) {
      _addPhoneEntry(label: pn.label, number: pn.number, isInitial: true);
    });
    if (_phoneEntries.isEmpty)
      _addPhoneEntry(isInitial: true); // Add one empty if none exist

    _emailEntries.clear();
    contact.emails?.forEach((em) {
      _addEmailEntry(label: em.label, address: em.address, isInitial: true);
    });
    if (_emailEntries.isEmpty) _addEmailEntry(isInitial: true);

    _addressEntries.clear();
    contact.addresses?.forEach((ad) {
      _addAddressEntry(
        label: ad.label,
        street: ad.street,
        city: ad.city,
        state: ad.state,
        zip: ad.zip,
        country: ad.country,
        isInitial: true,
      );
    });
    if (_addressEntries.isEmpty) _addAddressEntry(isInitial: true);

    // Business Opportunities
    _businessOpportunityEntries.clear();
    contact.business_details?.opportunities?.asMap().forEach((index, bo) {
      _addBusinessOpportunityEntry(
        description: bo.opportunity_description,
        latestDevelopment: bo.latest_development,
        isInitial: true,
        entryIndex: index, // Pass index for unique speech state key
      );
    });
    if (_businessOpportunityEntries.isEmpty) {
      _addBusinessOpportunityEntry(
        isInitial: true,
        entryIndex: 0,
      ); // Add one empty if none exist
    }

    // Personal Details
    _personalFamilyController = TextEditingController(
      text: contact.personal_details?.family,
    );
    _personalOccupationController = TextEditingController(
      text: contact.personal_details?.occupation,
    );
    _personalRecreationController = TextEditingController(
      text: contact.personal_details?.recreation,
    );
    _personalDreamsController = TextEditingController(
      text: contact.personal_details?.dreams,
    );
    _personalAdditionalInfoController = TextEditingController(
      text: contact.personal_details?.additional_info,
    );

    // Relationship Details (simplistic: assumes current user's details if available)
    // This might need to fetch current user ID to pick the right note.
    // For now, let's assume a generic relationship notes field or the first one.
    _relationshipDetailsController = TextEditingController(
      text: contact.relationship_details?.values.firstOrNull?.details,
    );

    // Business Details controllers are now part of _businessOpportunityEntries
    // _bizOppDescriptionController = TextEditingController( // Removed
    //   text: // Removed
    //       contact // Removed
    //           .business_details // Removed
    //           ?.business_opportunity // Removed
    //           ?.opportunity_description, // Removed
    // ); // Removed
    // _bizOppLatestDevController = TextEditingController( // Removed
    //   text: contact.business_details?.business_opportunity?.latest_development, // Removed
    // ); // Removed

    // Initialize speech states for fields that will use it
    _initSpeechState(
      'relationship',
      _relationshipDetailsController,
      _notesFocusNode,
    );
    _initSpeechState(
      'personal_additional_info',
      _personalAdditionalInfoController,
    );
    // _initSpeechState('biz_opp_description', _bizOppDescriptionController); // Removed
    // _initSpeechState('biz_opp_latest_dev', _bizOppLatestDevController); // Removed

    // Speech states for business opportunities are initialized within _addBusinessOpportunityEntry
  }

  _SpeechState _getSpeechState(String fieldKey) {
    return _speechStates[fieldKey]!;
  }

  void _initSpeechState(
    String key,
    TextEditingController controller, [
    FocusNode? focusNode,
  ]) {
    _speechStates[key] = _SpeechState(
      fieldId: 'edit_contact_${key}_${DateTime.now().millisecondsSinceEpoch}',
      textController: controller,
      focusNode: focusNode,
      onIsListeningChanged: (isListening) {
        if (mounted) setState(() {});
      },
      onElapsedTimeChanged: (elapsed) {
        if (mounted) setState(() {});
      },
      onResultText: (text) {
        // This callback will be triggered with the final speech result
        if (mounted) {
          final currentText = controller.text;
          final selection = controller.selection;
          final newText = currentText.replaceRange(
            selection.start,
            selection.end,
            text + ' ', // Add a space after insertion
          );
          controller.text = newText;
          controller.selection = TextSelection.fromPosition(
            TextPosition(offset: selection.start + text.length + 1),
          );
          setState(() {});
        }
      },
    );
    // Initialize AudioService for this specific field
    AudioService().getRecorderController(
      _speechStates[key]!.fieldId,
    ); // Initializes if not already
    _speechStates[key]!.initializeAudio(); // performs async init
  }

  @override
  void dispose() {
    // Dispose all controllers
    _firstNameController.dispose();
    _lastNameController.dispose();
    _addressedAsController.dispose();
    _businessNameController.dispose();
    _businessTypeController.dispose();
    _sourceController.dispose();
    _dateOfBirthController.dispose();

    for (var entry in _phoneEntries) {
      entry.labelController.dispose();
      entry.numberController.dispose();
    }
    for (var entry in _emailEntries) {
      entry.labelController.dispose();
      entry.addressController.dispose();
    }
    for (var entry in _addressEntries) {
      entry.labelController.dispose();
      entry.streetController.dispose();
      entry.cityController.dispose();
      entry.stateController.dispose();
      entry.zipController.dispose();
      entry.countryController.dispose();
    }

    for (var entry in _businessOpportunityEntries) {
      entry.descriptionController.dispose();
      entry.latestDevelopmentController.dispose();
      // Speech states are disposed via their own dispose method called from _SpeechState
      _speechStates['biz_opp_description_${entry.keySuffix}']?.dispose();
      _speechStates['biz_opp_latest_dev_${entry.keySuffix}']?.dispose();
    }

    _personalFamilyController.dispose();
    _personalOccupationController.dispose();
    _personalRecreationController.dispose();
    _personalDreamsController.dispose();
    _personalAdditionalInfoController.dispose();
    _relationshipDetailsController.dispose();
    // _bizOppDescriptionController.dispose(); // Removed
    // _bizOppLatestDevController.dispose(); // Removed

    _speechStates.values.forEach((state) => state.dispose());
    _notesFocusNode.dispose();

    super.dispose();
  }

  // --- Dynamic Entry Management ---
  void _addPhoneEntry({String? label, String? number, bool isInitial = false}) {
    final entry = _PhoneEntry(
      labelController: TextEditingController(text: label),
      numberController: TextEditingController(text: number),
    );
    setState(() => _phoneEntries.add(entry));
    if (!isInitial && mounted) {
      // Scroll to new entry, etc.
      // TODO: Consider if scroll is needed for web/desktop
    }
  }

  void _removePhoneEntry(int index) {
    if (_phoneEntries.length > 1) {
      // Keep at least one entry
      _phoneEntries[index].labelController.dispose();
      _phoneEntries[index].numberController.dispose();
      setState(() => _phoneEntries.removeAt(index));
    } else {
      // Clear the last one instead of removing
      _phoneEntries[index].labelController.clear();
      _phoneEntries[index].numberController.clear();
    }
  }

  void _addEmailEntry({
    String? label,
    String? address,
    bool isInitial = false,
  }) {
    final entry = _EmailEntry(
      labelController: TextEditingController(text: label),
      addressController: TextEditingController(text: address),
    );
    setState(() => _emailEntries.add(entry));
  }

  void _removeEmailEntry(int index) {
    if (_emailEntries.length > 1) {
      _emailEntries[index].labelController.dispose();
      _emailEntries[index].addressController.dispose();
      setState(() => _emailEntries.removeAt(index));
    } else {
      _emailEntries[index].labelController.clear();
      _emailEntries[index].addressController.clear();
    }
  }

  void _addAddressEntry({
    String? label,
    String? street,
    String? city,
    String? state,
    String? zip,
    String? country,
    bool isInitial = false,
  }) {
    final entry = _AddressEntry(
      labelController: TextEditingController(text: label),
      streetController: TextEditingController(text: street),
      cityController: TextEditingController(text: city),
      stateController: TextEditingController(text: state),
      zipController: TextEditingController(text: zip),
      countryController: TextEditingController(text: country),
    );
    setState(() => _addressEntries.add(entry));
  }

  void _removeAddressEntry(int index) {
    if (_addressEntries.length > 1) {
      _addressEntries[index].labelController.dispose();
      _addressEntries[index].streetController.dispose();
      _addressEntries[index].cityController.dispose();
      _addressEntries[index].stateController.dispose();
      _addressEntries[index].zipController.dispose();
      _addressEntries[index].countryController.dispose();
      setState(() => _addressEntries.removeAt(index));
    } else {
      // Clear the last one
      _addressEntries[index].labelController.clear();
      _addressEntries[index].streetController.clear();
      _addressEntries[index].cityController.clear();
      _addressEntries[index].stateController.clear();
      _addressEntries[index].zipController.clear();
      _addressEntries[index].countryController.clear();
    }
  }

  // Business Opportunity Dynamic Entry Management
  void _addBusinessOpportunityEntry({
    String? description,
    String? latestDevelopment,
    bool isInitial = false,
    required int entryIndex, // Used to create unique keys for speech states
  }) {
    final keySuffix =
        isInitial ? entryIndex : DateTime.now().millisecondsSinceEpoch;
    final descriptionController = TextEditingController(text: description);
    final latestDevController = TextEditingController(text: latestDevelopment);

    final entry = _BusinessOpportunityEntry(
      descriptionController: descriptionController,
      latestDevelopmentController: latestDevController,
      keySuffix: keySuffix.toString(),
    );

    // Initialize speech states for this new entry
    _initSpeechState(
      'biz_opp_description_${entry.keySuffix}',
      descriptionController,
    );
    _initSpeechState(
      'biz_opp_latest_dev_${entry.keySuffix}',
      latestDevController,
    );

    setState(() => _businessOpportunityEntries.add(entry));
  }

  void _removeBusinessOpportunityEntry(int index) {
    if (_businessOpportunityEntries.length > 1) {
      final entry = _businessOpportunityEntries[index];
      entry.descriptionController.dispose();
      entry.latestDevelopmentController.dispose();
      // Dispose associated speech states
      _speechStates.remove('biz_opp_description_${entry.keySuffix}')?.dispose();
      _speechStates.remove('biz_opp_latest_dev_${entry.keySuffix}')?.dispose();
      setState(() => _businessOpportunityEntries.removeAt(index));
    } else {
      // Clear the last one
      final entry = _businessOpportunityEntries[index];
      entry.descriptionController.clear();
      entry.latestDevelopmentController.clear();
      // Optionally reset speech state text here if needed, though clearing controller should be enough
    }
  }

  // --- Date Picker ---
  Future<void> _showDatePicker(BuildContext context) async {
    final DateTime? picked = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (BuildContext builderContext) {
        // Use a local variable for the date being changed in the picker
        DateTime? dateInPicker = _selectedDateOfBirth ?? DateTime.now();
        return Container(
          height: MediaQuery.of(context).copyWith().size.height / 3,
          color: CupertinoColors.systemBackground.resolveFrom(context),
          child: Column(
            children: [
              Container(
                color: CupertinoColors.secondarySystemBackground.resolveFrom(
                  context,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      child: const Text('Cancel'),
                      onPressed: () => Navigator.of(builderContext).pop(null),
                    ),
                    CupertinoButton(
                      child: const Text('Done'),
                      onPressed:
                          () => Navigator.of(builderContext).pop(dateInPicker),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: _selectedDateOfBirth ?? DateTime.now(),
                  onDateTimeChanged: (DateTime newDate) {
                    dateInPicker = newDate; // Update the local variable
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null && picked != _selectedDateOfBirth) {
      setState(() {
        _selectedDateOfBirth = picked;
        _dateOfBirthController.text = DateFormat.yMd().format(picked);
      });
    }
  }

  // --- Build Contact from Form Data ---
  Contact _getUpdatedContact() {
    final List<PhoneNumber> phoneNumbers =
        _phoneEntries
            .where((e) => e.numberController.text.trim().isNotEmpty)
            .map(
              (e) => PhoneNumber(
                label: e.labelController.text.trim(),
                number: e.numberController.text.trim(),
              ),
            )
            .toList();

    final List<EmailAddress> emails =
        _emailEntries
            .where((e) => e.addressController.text.trim().isNotEmpty)
            .map(
              (e) => EmailAddress(
                label: e.labelController.text.trim(),
                address: e.addressController.text.trim(),
              ),
            )
            .toList();

    final List<Address> addresses =
        _addressEntries
            .where(
              (e) =>
                  e.streetController.text.trim().isNotEmpty ||
                  e.cityController.text.trim().isNotEmpty,
            ) // Basic check
            .map(
              (e) => Address(
                label: e.labelController.text.trim(),
                street: e.streetController.text.trim(),
                city: e.cityController.text.trim(),
                state: e.stateController.text.trim(),
                zip: e.zipController.text.trim(),
                country: e.countryController.text.trim(),
              ),
            )
            .toList();

    final List<BusinessOpportunity> businessOpportunities =
        _businessOpportunityEntries
            .where(
              (e) =>
                  e.descriptionController.text.trim().isNotEmpty ||
                  e.latestDevelopmentController.text.trim().isNotEmpty,
            )
            .map(
              (e) => BusinessOpportunity(
                opportunity_description: e.descriptionController.text.trim(),
                latest_development: e.latestDevelopmentController.text.trim(),
              ),
            )
            .toList();

    // This is a simplified update. A real app might want to merge with existing contact
    // or use a more sophisticated way to handle unchanged fields (e.g. using copyWith and only sending changed fields).
    return widget.contact.copyWith(
      first_name: _firstNameController.text.trim(),
      last_name: _lastNameController.text.trim(),
      addressed_as: _addressedAsController.text.trim(),
      business_name: _businessNameController.text.trim(),
      business_type: _businessTypeController.text.trim(),
      source: _sourceController.text.trim(),
      date_of_birth: _selectedDateOfBirth,
      phone_numbers: phoneNumbers.isNotEmpty ? phoneNumbers : null,
      emails: emails.isNotEmpty ? emails : null,
      addresses: addresses.isNotEmpty ? addresses : null,
      personal_details: PersonalDetails(
        // Create new or update existing
        family: _personalFamilyController.text.trim(),
        occupation: _personalOccupationController.text.trim(),
        recreation: _personalRecreationController.text.trim(),
        dreams: _personalDreamsController.text.trim(),
        additional_info: _personalAdditionalInfoController.text.trim(),
      ),
      // For relationship_details, this is a simplification.
      // We'd need to know which user's detail we are editing.
      // This example updates/creates a detail for a placeholder user ID or the first existing one.
      // A more robust solution would involve passing the relevant user ID or managing a map of controllers.
      relationship_details: {
        widget.contact.relationship_details?.keys.firstOrNull ??
            'currentUser': RelationshipDetail(
          details: _relationshipDetailsController.text.trim(),
          // user_id would be set appropriately here
        ),
      },
      business_details: BusinessDetails(
        // Create new or update existing
        opportunities:
            businessOpportunities.isNotEmpty ? businessOpportunities : null,
      ),
      // TODO: Handle tags, assigned_user etc. if they are editable
    );
  }

  // PUBLIC method to be called by parent screen via GlobalKey
  void triggerSave() {
    // Basic validation can be added here
    // e.g. if (_firstNameController.text.isEmpty) { showError("First name is required"); return; }
    final updatedContact = _getUpdatedContact();
    widget.onSave(updatedContact);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSectionTitle('Primary Information'),
          _buildTextField(_firstNameController, 'First Name', isRequired: true),
          _buildTextField(_lastNameController, 'Last Name'),
          _buildTextField(_addressedAsController, 'Addressed As'),
          _buildTextField(_businessNameController, 'Business Name'), // Company
          _buildTextField(_businessTypeController, 'Business Type'),

          _buildDatePickerField(context),

          _buildSectionTitle('Contact Methods'),
          ..._buildDynamicEntryList(
            context,
            _EntryType.phone,
            _phoneEntries,
            (index) => _removePhoneEntry(index),
            () => _addPhoneEntry(),
          ),
          ..._buildDynamicEntryList(
            context,
            _EntryType.email,
            _emailEntries,
            (index) => _removeEmailEntry(index),
            () => _addEmailEntry(),
          ),
          ..._buildDynamicEntryList(
            context,
            _EntryType.address,
            _addressEntries,
            (index) => _removeAddressEntry(index),
            () => _addAddressEntry(),
          ),

          _buildSectionTitle('Personal Details'),
          _buildTextField(_personalFamilyController, 'Family', maxLines: 8),
          _buildTextField(_personalOccupationController, 'Occupation'),
          _buildTextField(
            _personalRecreationController,
            'Recreation',
            maxLines: 8,
          ),
          _buildTextField(
            _personalDreamsController,
            'Dreams/Aspirations',
            maxLines: 8,
          ),
          _buildLongTextFieldWithSpeech(
            _speechStates['personal_additional_info']!,
            'Additional Personal Info',
            maxLines: 8,
          ),

          _buildSectionTitle('Relationship Notes'),
          _buildLongTextFieldWithSpeech(
            _speechStates['relationship']!,
            'Notes',
            maxLines: 8,
          ),

          _buildSectionTitle('Business Details'),
          ..._buildDynamicBusinessOpportunityList(
            context,
            _businessOpportunityEntries,
            (index) => _removeBusinessOpportunityEntry(index),
            () => _addBusinessOpportunityEntry(
              entryIndex: _businessOpportunityEntries.length,
            ), // Pass new index
          ),

          _buildTextField(_sourceController, 'Source'),

          // TODO: Tags input
          const SizedBox(height: 24),
          CupertinoButton.filled(
            onPressed: triggerSave,
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  // --- UI Helper Methods ---
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
      child: Text(
        title,
        style: AppStyles.h2TextStyle(
          context,
        ).copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool isRequired = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    final String displayLabel =
        widget.labels?[label.toLowerCase().replaceAll(' ', '_')] ?? label;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayLabel + (isRequired ? ' *' : ''),
            style: AppStyles.labelTextStyle(context),
          ),
          const SizedBox(height: 4),
          CupertinoTextField(
            controller: controller,
            placeholder: 'Enter $displayLabel',
            maxLines: maxLines,
            keyboardType: keyboardType,
            style: AppStyles.inputTextStyle(context),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(
                color: CupertinoColors.systemGrey4.resolveFrom(context),
                width: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePickerField(BuildContext context) {
    final String displayLabel =
        widget.labels?['date_of_birth'] ?? 'Date of Birth';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(displayLabel, style: AppStyles.labelTextStyle(context)),
          const SizedBox(height: 4),
          CupertinoTextField(
            controller: _dateOfBirthController,
            placeholder: 'Select Date',
            readOnly: true,
            style: AppStyles.inputTextStyle(context),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(
                color: CupertinoColors.systemGrey4.resolveFrom(context),
                width: 0.5,
              ),
            ),
            onTap: () => _showDatePicker(context),
            suffix: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: AppStyles.accentIcon(
                icon: CupertinoIcons.calendar,
                size: 24.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDynamicEntryList(
    BuildContext context,
    _EntryType type,
    List<dynamic>
    entries, // List<_PhoneEntry>, List<_EmailEntry>, or List<_AddressEntry>
    Function(int) onRemove,
    Function() onAdd,
  ) {
    List<Widget> children = [];
    for (int i = 0; i < entries.length; i++) {
      children.add(
        _buildDynamicEntryItem(context, type, entries[i], i, onRemove),
      );
    }
    children.add(
      Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppStyles.accentIcon(icon: CupertinoIcons.add_circled, size: 20),
              const SizedBox(width: 6),
              AppStyles.accentText(context, 'Add ${type.name}'),
            ],
          ),
          onPressed: () => onAdd(),
        ),
      ),
    );
    return children;
  }

  Widget _buildDynamicEntryItem(
    BuildContext context,
    _EntryType type,
    dynamic entry, // _PhoneEntry, _EmailEntry, or _AddressEntry
    int index,
    Function(int) onRemove,
  ) {
    final bool canRemove =
        (type == _EntryType.phone && _phoneEntries.length > 1) ||
        (type == _EntryType.email && _emailEntries.length > 1) ||
        (type == _EntryType.address && _addressEntries.length > 1);

    Widget itemContent;
    switch (type) {
      case _EntryType.phone:
        final phoneEntry = entry as _PhoneEntry;
        itemContent = Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildTextField(phoneEntry.labelController, 'Label'),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: _buildTextField(
                phoneEntry.numberController,
                'Phone Number',
                keyboardType: TextInputType.phone,
              ),
            ),
          ],
        );
        break;
      case _EntryType.email:
        final emailEntry = entry as _EmailEntry;
        itemContent = Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildTextField(emailEntry.labelController, 'Label'),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: _buildTextField(
                emailEntry.addressController,
                'Email Address',
                keyboardType: TextInputType.emailAddress,
              ),
            ),
          ],
        );
        break;
      case _EntryType.address:
        final addressEntry = entry as _AddressEntry;
        itemContent = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTextField(addressEntry.labelController, 'Label'),
            _buildTextField(addressEntry.streetController, 'Street'),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(addressEntry.cityController, 'City'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTextField(
                    addressEntry.stateController,
                    'State/Province',
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    addressEntry.zipController,
                    'ZIP/Postal Code',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTextField(
                    addressEntry.countryController,
                    'Country',
                  ),
                ),
              ],
            ),
          ],
        );
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(
            color: CupertinoColors.systemGrey5.resolveFrom(context),
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            itemContent,
            if (index > 0 ||
                canRemove) // Show remove button if not the first item OR if it's the first but others exist (meaning it CAN be removed)
              Align(
                alignment: Alignment.centerRight,
                child: CupertinoButton(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Remove ${type.name}',
                    style: TextStyle(
                      color: CupertinoColors.destructiveRed,
                      fontSize: 14,
                    ),
                  ),
                  onPressed: () => onRemove(index),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLongTextFieldWithSpeech(
    _SpeechState speechState,
    String label, {
    int maxLines = 3,
    bool isRequired = false,
  }) {
    final String displayLabel =
        widget.labels?[label.toLowerCase().replaceAll(' ', '_')] ?? label;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayLabel + (isRequired ? ' *' : ''),
            style: AppStyles.labelTextStyle(context),
          ),
          const SizedBox(height: 4),
          AudioControlsDecorator(
            isListening: speechState.isListening,
            elapsedTime: speechState.elapsedTime,
            onMicPressed: speechState.handleMicPressed,
            onCancelPressed: speechState.cancelListening,
            recorderController: AudioService().getRecorderController(
              speechState.fieldId,
            ),
            child: CupertinoTextField(
              controller: speechState.textController,
              focusNode: speechState.focusNode,
              placeholder: 'Enter $displayLabel or use mic',
              maxLines: maxLines,
              minLines: maxLines, // Ensure it takes up the space
              keyboardType: TextInputType.multiline,
              style: AppStyles.inputTextStyle(context),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(
                  color: CupertinoColors.systemGrey4.resolveFrom(context),
                  width: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI Helper Methods for Business Opportunities ---
  List<Widget> _buildDynamicBusinessOpportunityList(
    BuildContext context,
    List<_BusinessOpportunityEntry> entries,
    Function(int) onRemove,
    Function() onAdd,
  ) {
    List<Widget> children = [];
    for (int i = 0; i < entries.length; i++) {
      children.add(
        _buildBusinessOpportunityItem(context, entries[i], i, onRemove),
      );
    }
    children.add(
      Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppStyles.accentIcon(icon: CupertinoIcons.add_circled, size: 20),
              const SizedBox(width: 6),
              AppStyles.accentText(context, 'Add Business Opportunity'),
            ],
          ),
          onPressed: onAdd,
        ),
      ),
    );
    return children;
  }

  Widget _buildBusinessOpportunityItem(
    BuildContext context,
    _BusinessOpportunityEntry entry,
    int index,
    Function(int) onRemove,
  ) {
    final bool canRemove = _businessOpportunityEntries.length > 1;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(
            color: CupertinoColors.systemGrey5.resolveFrom(context),
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLongTextFieldWithSpeech(
              _speechStates['biz_opp_description_${entry.keySuffix}']!,
              'Opportunity Description',
              maxLines: 5,
            ),
            const SizedBox(height: 8),
            _buildLongTextFieldWithSpeech(
              _speechStates['biz_opp_latest_dev_${entry.keySuffix}']!,
              'Latest Development',
              maxLines: 5,
            ),
            if (index > 0 || canRemove)
              Align(
                alignment: Alignment.centerRight,
                child: CupertinoButton(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: const Text(
                    'Remove Opportunity',
                    style: TextStyle(
                      color: CupertinoColors.destructiveRed,
                      fontSize: 14,
                    ),
                  ),
                  onPressed: () => onRemove(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- Helper classes for dynamic entries ---
class _PhoneEntry {
  final TextEditingController labelController;
  final TextEditingController numberController;
  _PhoneEntry({required this.labelController, required this.numberController});
}

class _EmailEntry {
  final TextEditingController labelController;
  final TextEditingController addressController;
  _EmailEntry({required this.labelController, required this.addressController});
}

class _AddressEntry {
  final TextEditingController labelController;
  final TextEditingController streetController;
  final TextEditingController cityController;
  final TextEditingController stateController;
  final TextEditingController zipController;
  final TextEditingController countryController;
  _AddressEntry({
    required this.labelController,
    required this.streetController,
    required this.cityController,
    required this.stateController,
    required this.zipController,
    required this.countryController,
  });
}

// New helper class for business opportunity entries
class _BusinessOpportunityEntry {
  final TextEditingController descriptionController;
  final TextEditingController latestDevelopmentController;
  final String keySuffix; // For unique speech state keys

  _BusinessOpportunityEntry({
    required this.descriptionController,
    required this.latestDevelopmentController,
    required this.keySuffix,
  });
}

// Helper class to manage speech recognition state per field
class _SpeechState {
  final String fieldId;
  final TextEditingController textController;
  final FocusNode? focusNode;
  final Function(bool) onIsListeningChanged;
  final Function(Duration) onElapsedTimeChanged;
  final Function(String) onResultText;

  bool _isListening = false;
  bool _isInitializing = true;
  Timer? _recordingTimer;
  Duration _elapsedTime = Duration.zero;
  // RecorderController is managed globally by AudioService via fieldId

  bool get isListening => _isListening;
  Duration get elapsedTime => _elapsedTime;

  _SpeechState({
    required this.fieldId,
    required this.textController,
    this.focusNode,
    required this.onIsListeningChanged,
    required this.onElapsedTimeChanged,
    required this.onResultText,
  });

  Future<void> initializeAudio() async {
    try {
      await AudioService().initialize(); // Ensures SpeechToText is ready
      if (AudioService().isReady) _isInitializing = false;
    } catch (e) {
      print("[$fieldId] Error during audio service initialization: $e");
      _isInitializing = false; // Allow form to build
    }
  }

  void handleMicPressed() async {
    if (_isInitializing || !AudioService().isReady) return;
    if (!_isListening) {
      _startListening();
      focusNode?.requestFocus();
    } else {
      _stopListening();
    }
  }

  void _startListening() async {
    if (!AudioService().isReady || _isListening) return;

    _isListening = true;
    _elapsedTime = Duration.zero;
    onIsListeningChanged(_isListening);
    onElapsedTimeChanged(_elapsedTime);

    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedTime = Duration(seconds: _elapsedTime.inSeconds + 1);
      onElapsedTimeChanged(_elapsedTime);
    });

    try {
      await AudioService().startListening(
        fieldId: fieldId,
        onResult: _onSpeechResult,
      );
    } catch (e) {
      print("[$fieldId] Error starting speech recognition: $e");
      _isListening = false;
      onIsListeningChanged(_isListening);
      _recordingTimer?.cancel();
    }
  }

  void _stopListening() async {
    _recordingTimer?.cancel();
    try {
      await AudioService().stopListening(fieldId);
    } catch (e) {
      print("[$fieldId] Error stopping speech recognition: $e");
    }
    _isListening = false;
    onIsListeningChanged(_isListening);
  }

  void cancelListening() {
    _stopListening();
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (result.finalResult && result.recognizedWords.isNotEmpty) {
      onResultText(result.recognizedWords);
    }
  }

  void dispose() {
    _recordingTimer?.cancel();
    AudioService().dispose(fieldId); // Dispose specific recorder controller
  }
}

extension ContactFirstOrNullRelationship on Map<String, RelationshipDetail> {
  RelationshipDetail? get firstOrNull =>
      values.isNotEmpty ? values.first : null;
}
