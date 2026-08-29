import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // For AnimatedSize etc.
import 'dart:async'; // May be needed for future logic
import 'package:flutter_riverpod/flutter_riverpod.dart'; // IMPORT Riverpod

import 'package:assiist_front_end/core/models/contact.dart'; // Import Contact model
import 'contact_search_field.dart';
import 'add_contact_form.dart';
import 'vip_components.dart'; // ADD: Import VIP components
import 'package:assiist_front_end/theme/app_styles.dart'; // For styling consistency
import 'package:assiist_front_end/utils/formatting_utils.dart'; // For buildSubtitleText
import 'package:assiist_front_end/providers/repository_providers.dart'; // IMPORT Repository Provider
import 'package:assiist_front_end/utils/unfocus_helper.dart'; // Use UnfocusHelper instead of UnfocusScope

// Callback signature for when a contact is selected
typedef ContactSelectedCallback = void Function(Contact contact);
// Callback for when the user toggles the add mode (optional, parent might not need it)
typedef AddModeToggledCallback = void Function(bool isAdding);
// Callback for when text in the search field changes (optional)
typedef SearchTextChangedCallback = void Function(String query);
// Callback for when the navigate chevron is tapped on a selected contact
typedef NavigateToContactCallback = void Function();
// ADD Callback for when the explicit 'Create Contact' button is pressed
typedef CreateContactCallback = void Function();
// ADD Callback for when save is pressed FROM WITHIN the add contact form
typedef SaveContactAttemptCallback =
    void Function(Map<String, String> contactDetails);

class SelectOrAddContact extends ConsumerStatefulWidget {
  final ContactSelectedCallback onContactSelected;
  final AddModeToggledCallback? onAddModeToggled; // Optional
  final SearchTextChangedCallback? onSearchTextChanged; // Optional
  final NavigateToContactCallback?
  onNavigateToSelectedContact; // ADD BACK Callback
  final bool showNavigateChevron; // NEW parameter
  final bool showCreateButton; // ADD BACK parameter
  final CreateContactCallback?
  onCreateContactButtonPressed; // ADD BACK callback
  final bool
  showEditableFieldsOnSelect; // NEW: Control editable fields visibility
  final bool initialIsAdding; // ADDED for programmatic initial state
  final SaveContactAttemptCallback? onSaveAttempt; // ADDED for internal save
  final bool showSearchField; // ADDED to control search field visibility
  final String?
  initialEmail; // ADDED for pre-filling email from pending contacts

  const SelectOrAddContact({
    super.key,
    required this.onContactSelected,
    this.onAddModeToggled,
    this.onSearchTextChanged,
    this.onNavigateToSelectedContact, // ADD BACK to constructor
    this.showNavigateChevron = false, // Default to false
    this.showCreateButton = false, // ADD BACK to constructor (default false)
    this.onCreateContactButtonPressed, // ADD BACK to constructor
    this.showEditableFieldsOnSelect = true, // Default to true
    this.initialIsAdding = false, // ADDED default
    this.onSaveAttempt, // ADDED
    this.showSearchField = true, // ADDED default
    this.initialEmail, // ADDED
  });

  @override
  ConsumerState<SelectOrAddContact> createState() => SelectOrAddContactState();
}

class SelectOrAddContactState extends ConsumerState<SelectOrAddContact> {
  // --- State Variables (Moved from log_interaction_screen) ---
  Contact? _selectedContact;
  bool _showAddContactFields = false;
  String? _currentSearchText; // Tracks text in the search field
  bool _isVip = false; // ADD: VIP toggle state

  // --- Public Getter for Parent Access ---
  bool get isAddingContact => _showAddContactFields;
  Contact? get selectedContact =>
      _selectedContact; // ADD getter for selected contact

  // Controllers for AddContactForm (Owned by this widget now) - BASIC SET FOR ADDING
  final _addFirstNameController = TextEditingController();
  final _addLastNameController = TextEditingController();
  final _addPhoneController = TextEditingController(); // Basic phone
  final _addEmailController = TextEditingController(); // Basic email
  final _addCompanyController =
      TextEditingController(); // For business_name / company
  final _addAddressedAsController = TextEditingController();
  final _addBusinessTypeController =
      TextEditingController(); // Basic business type
  final _addRelationshipInfoController =
      TextEditingController(); // Basic relationship info

  // --- Controllers for Selected Contact's Editable Fields (LIMITED SET) ---
  final _selectedFirstNameController = TextEditingController(); // NEW
  final _selectedLastNameController = TextEditingController(); // NEW
  final _selectedContactAddressedAsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Initialize any state if needed
    _showAddContactFields =
        widget.initialIsAdding; // ADDED: Set initial add mode
    if (widget.initialIsAdding) {
      _selectedContact =
          null; // Ensure no contact is selected if starting in add mode
      _currentSearchText = null;
    }

    // Pre-fill email if provided
    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _addEmailController.text = widget.initialEmail!;
    }
  }

  @override
  void dispose() {
    // Dispose all controllers
    _addFirstNameController.dispose();
    _addLastNameController.dispose();
    _addPhoneController.dispose();
    _addEmailController.dispose();
    _addCompanyController.dispose();
    _addAddressedAsController.dispose();
    _addBusinessTypeController.dispose();
    _addRelationshipInfoController.dispose();

    // Dispose selected contact controllers
    _selectedFirstNameController.dispose(); // NEW
    _selectedLastNameController.dispose(); // NEW
    _selectedContactAddressedAsController.dispose();
    super.dispose();
  }

  // --- Logic Methods (Moved and adapted) ---

  // --- NEW: Public method for external selection ---
  void selectContactExternally(Contact contact) {
    // Use the existing internal handler
    _handleContactSelection(contact);
  }

  void _handleContactSelection(Contact contact) {
    // No need for explicit keyboard dismissal - handled by UnfocusHelper in parent screens
    setState(() {
      _selectedContact = contact;
      _currentSearchText = ''; // CLEAR search text visually
      _showAddContactFields = false; // Ensure add mode is off
      _clearAddContactFields(); // Clear add fields if user selects existing

      // --- Populate the controllers for the selected contact's editable fields ---
      _selectedFirstNameController.text = contact.first_name ?? ''; // NEW
      _selectedLastNameController.text = contact.last_name ?? ''; // NEW
      _selectedContactAddressedAsController.text = contact.addressed_as ?? '';
    });
    // Notify the parent widget
    widget.onContactSelected(contact);
  }

  void _handleToggleAddContact(bool isAdding) {
    // No need for explicit keyboard dismissal - handled by UnfocusHelper in parent screens
    print("DEBUG: Toggling add mode to: $isAdding"); // Debug print
    setState(() {
      _showAddContactFields = isAdding;
      if (isAdding) {
        _selectedContact = null; // Clear selection when entering add mode
        _currentSearchText = null; // Clear search text visually
        _clearSelectedContactFields(); // Clear selected fields as well
        // Don't clear add fields here, user might want to resume editing
      } else {
        // If cancelling add mode, clear the fields
        _clearAddContactFields();
      }
    });
    // Notify parent (optional)
    widget.onAddModeToggled?.call(isAdding);
  }

  // Handles text changes specifically from the ContactSearchField
  void _handleSearchTextChanged(String text) {
    setState(() {
      _currentSearchText = text;
      // --- REVERT: Comment out clearing selected contact again --- //
      // Clear selected contact if user starts typing again AFTER selecting one
      // This allows the user to easily search for someone else
      /*
      if (_selectedContact != null && text.isNotEmpty) {
        _selectedContact = null;
        _clearSelectedContactFields(); // Also clear editable fields
      }
      */
      // --- END REVERT --- //
    });
    // Notify parent screen (optional)
    widget.onSearchTextChanged?.call(text);
  }

  // Renamed for clarity - Clears BASIC ADD controllers
  void _clearAddContactFields() {
    _addFirstNameController.clear();
    _addLastNameController.clear();
    _addPhoneController.clear();
    _addEmailController.clear();
    _addCompanyController.clear();
    _addAddressedAsController.clear();
    _addBusinessTypeController.clear();
    _addRelationshipInfoController.clear();
  }

  // --- NEW: Clear selected contact editable fields ---
  void _clearSelectedContactFields() {
    _selectedFirstNameController.clear();
    _selectedLastNameController.clear();
    _selectedContactAddressedAsController.clear();
  }

  // --- Method for Parent to Get Form Data (Updated Keys) ---
  // Renamed for clarity - Returns data from BASIC ADD controllers
  Map<String, String> getNewContactDetails() {
    return {
      'first_name':
          _addFirstNameController.text
              .trim(), // ← FIXED: Use snake_case for backend
      'last_name':
          _addLastNameController.text
              .trim(), // ← FIXED: Use snake_case for backend
      'phone': _addPhoneController.text.trim(),
      'email': _addEmailController.text.trim(),
      'business_name':
          _addCompanyController.text
              .trim(), // ← FIXED: Use snake_case for backend
      'addressed_as':
          _addAddressedAsController.text
              .trim(), // ← FIXED: Use snake_case for backend
      'business_type':
          _addBusinessTypeController.text
              .trim(), // ← FIXED: Use snake_case for backend
      'relationshipInfo': _addRelationshipInfoController.text.trim(),
      'is_vip': _isVip.toString(), // ADD: Include VIP status
    };
  }

  // --- NEW: Public method to get edited selected contact data ---
  Map<String, String> getEditedSelectedContactDetails() {
    if (_selectedContact == null) {
      return {}; // Return empty if no contact is selected
    }
    return {
      'first_name':
          _selectedFirstNameController.text
              .trim(), // ← FIXED: Use snake_case for backend
      'last_name':
          _selectedLastNameController.text
              .trim(), // ← FIXED: Use snake_case for backend
      'addressed_as':
          _selectedContactAddressedAsController.text
              .trim(), // ← FIXED: Use snake_case for backend
    };
  }

  // --- NEW: Public method to reset the widget's state ---
  void reset() {
    setState(() {
      _selectedContact = null;
      _showAddContactFields = false;
      _currentSearchText = ''; // Clear internal search text state
      _isVip = false; // ADD: Reset VIP status
      // TODO: Ideally, also clear the text in the ContactSearchField's controller
      _clearAddContactFields(); // Ensure add form fields are cleared
      _clearSelectedContactFields(); // Ensure selected fields are cleared
    });
    // Keyboard dismissal is now handled by UnfocusHelper in parent screens
  }

  // --- NEW: Public method to enter add mode ---
  void enterAddMode() {
    // No need for explicit keyboard dismissal - handled by UnfocusHelper in parent screens
    print("DEBUG: enterAddMode called externally");
    if (!_showAddContactFields) {
      // Only toggle if not already in add mode
      _handleToggleAddContact(true);
    } else {
      // If already in add mode, ensure form is clear and ready (optional, depends on desired UX)
      _clearAddContactFields(); // Example: Clear fields if called again while already adding
      // Potentially also ensure focus is on the first field of AddContactForm
      // This might require passing a FocusNode to AddContactForm or having a method there.
    }
  }
  // --- END NEW ---

  // --- UI Building Methods (Moved and adapted) ---

  // Builds the display for a selected contact
  Widget _buildSelectedContactDisplay(BuildContext context, Contact contact) {
    final theme = CupertinoTheme.of(context);
    final String? firstEmail = contact.emails?.firstOrNull?.address;
    final String? firstPhone = contact.phone_numbers?.firstOrNull?.number;
    final subtitle = buildSubtitleText(firstEmail, firstPhone);

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: AppStyles.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Row(
          children: [
            // Left: Clear Button
            CupertinoButton(
              padding: const EdgeInsets.only(right: 12.0),
              minSize: 0,
              child: const Icon(
                CupertinoIcons.clear_circled_solid,
                color: CupertinoColors.systemGrey2,
                size: 22.0,
              ),
              onPressed: () {
                setState(() {
                  _selectedContact = null;
                  _currentSearchText =
                      null; // Or maybe keep search text? Debateable.
                  _clearSelectedContactFields(); // Clear the editable fields
                });
              },
            ),

            // Middle: Contact Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    contact.displayName, // Keep showing display name here
                    style: AppStyles.inputTextStyle(
                      context,
                    ).copyWith(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != 'No contact info') ...[
                    const SizedBox(height: 2.0),
                    Text(
                      subtitle, // Keep showing subtitle here
                      style: theme.textTheme.tabLabelTextStyle.copyWith(
                        color: CupertinoColors.systemGrey,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Right: Navigation Chevron Button (Conditionally shown)
            if (widget.showNavigateChevron)
              CupertinoButton(
                padding: const EdgeInsets.only(left: 8.0),
                minSize: 0,
                child: AppStyles.accentIcon(
                  icon: CupertinoIcons.right_chevron,
                  size: 20.0,
                ),
                onPressed: widget.onNavigateToSelectedContact, // Use callback
              ),
          ],
        ),
      ),
    );
  }

  // --- Need the _buildModernTextField helper here now ---
  Widget _buildModernTextField({
    required BuildContext context,
    TextEditingController? controller, // Make controller optional
    String? initialValue, // NEW: For read-only display
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

    // Use initialValue if readOnly, otherwise use controller
    final effectiveController =
        readOnly && initialValue != null
            ? TextEditingController(text: initialValue)
            : controller;
    // Ensure a controller exists if not read-only
    assert(
      readOnly || effectiveController != null,
      'Controller must be provided if not readOnly or initialValue is not set for readOnly.',
    );

    return CupertinoTextField(
      controller: effectiveController,
      focusNode: focusNode,
      placeholder:
          readOnly
              ? null
              : placeholder +
                  (isRequired ? ' *' : ''), // No placeholder if readOnly
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
      padding: const EdgeInsets.symmetric(
        vertical: 12.0,
        horizontal: 16.0,
      ), // Match AddContactForm padding
      textAlignVertical: TextAlignVertical.center,
      cursorColor: AppStyles.solidAccent, // Use AppStyles accent system
      onChanged: onChanged,
    );
  }

  // --- NEW Helper: Build Labeled Read-Only Field ---
  Widget _buildLabeledReadOnlyField(
    BuildContext context,
    String label,
    String value,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4.0, left: 4.0),
          child: Text(
            label + ':', // Add colon to label
            style: AppStyles.labelTextStyle(
              context,
            ).copyWith(fontSize: 13, color: CupertinoColors.systemGrey),
          ),
        ),
        _buildModernTextField(
          context: context,
          initialValue: value, // Use initialValue
          placeholder: '', // No placeholder needed
          readOnly: true,
        ),
        const SizedBox(height: 12.0), // Spacing after the field
      ],
    );
  }
  // --- END NEW Helper ---

  @override
  Widget build(BuildContext context) {
    // Access the repository using ref.watch
    final contactRepo = ref.watch(contactRepositoryProvider);

    // Use Column directly - UnfocusScope is now at the screen level
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Contact Search Field (Conditionally shown)
        if (widget.showSearchField)
          ContactSearchField(
            key: ValueKey(_showAddContactFields ? 'add_mode' : 'search_mode'),
            onContactSelected: _handleContactSelection,
            onToggleAdd: _handleToggleAddContact,
            isAddingContact: _showAddContactFields,
            initialSearchText: _currentSearchText,
            showAddToggleButton: true,
            onSearchTextChanged: _handleSearchTextChanged,
            // Pass the search function from the repository
            contactSearcher: contactRepo.searchContacts,
          ),

        // 2. Animated Container for Add Form OR (Selected Display + Optional Editable Fields)
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child:
              _showAddContactFields
                  // --- WHEN ADDING --- //
                  ? Builder(
                    builder: (context) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(
                            height: 8.0,
                          ), // Add space before divider
                          const Divider(
                            height: 1,
                            thickness: 0.5,
                          ), // Add divider
                          const SizedBox(
                            height: 12.0,
                          ), // Add space after divider
                          AddContactForm(
                            // This will be the SIMPLIFIED AddContactForm
                            // Pass BASIC controllers for adding
                            firstNameController: _addFirstNameController,
                            lastNameController: _addLastNameController,
                            phoneController: _addPhoneController,
                            emailController: _addEmailController,
                            companyController: _addCompanyController,
                            addressedAsController: _addAddressedAsController,
                            businessTypeController: _addBusinessTypeController,
                            relationshipInfoController:
                                _addRelationshipInfoController,
                          ),
                          // --- ADD Centered Create Button Below Form --- //
                          if (widget.showCreateButton) ...[
                            const SizedBox(
                              height: 16.0,
                            ), // REDUCED Spacing above button
                            // CHANGE: Use Row layout instead of Center for button and VIP toggle
                            Row(
                              children: [
                                // Left column - VIP toggle centered
                                Expanded(
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Mark as VIP',
                                          style: AppStyles.inputTextStyle(
                                            context,
                                          ).copyWith(fontSize: 16),
                                        ),
                                        const SizedBox(
                                          width: 8.0,
                                        ), // Minimal spacing
                                        CupertinoSwitch(
                                          value: _isVip,
                                          onChanged: (value) {
                                            setState(() {
                                              _isVip = value;
                                            });
                                          },
                                          activeColor: AppStyles.solidAccent,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Right column - Create Contact button centered
                                Expanded(
                                  child: Center(
                                    child: AppStyles.filledButton(
                                      context: context,
                                      text: 'Create Contact',
                                      onPressed: () {
                                        // MODIFIED
                                        if (widget.onSaveAttempt != null) {
                                          widget.onSaveAttempt!(
                                            getNewContactDetails(),
                                          );
                                        } else if (widget
                                                .onCreateContactButtonPressed !=
                                            null) {
                                          // Fallback to existing behavior if onSaveAttempt is not provided
                                          widget
                                              .onCreateContactButtonPressed!();
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8.0), // Padding below button
                          ],
                          // --- END Create Button ---
                        ],
                      );
                    },
                  )
                  // --- WHEN CONTACT IS SELECTED --- //
                  : _selectedContact != null
                  ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Display selected contact PREVIEW row (always shown if selected)
                      _buildSelectedContactDisplay(context, _selectedContact!),

                      // --- Conditionally show Editable Fields Below Preview ---
                      if (widget.showEditableFieldsOnSelect) ...[
                        const SizedBox(height: 16.0), // Spacing after preview
                        // --- Row for First and Last Name ---
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // --- First Name Column ---
                            Expanded(
                              child: _buildModernTextField(
                                context: context,
                                controller: _selectedFirstNameController,
                                placeholder: 'First Name',
                              ),
                            ),
                            const SizedBox(
                              width: 12.0,
                            ), // Spacing between fields
                            // --- Last Name Column ---
                            Expanded(
                              child: _buildModernTextField(
                                context: context,
                                controller: _selectedLastNameController,
                                placeholder: 'Last Name',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12.0), // Spacing below name row
                        // --- End Row for First and Last Name ---

                        // --- Addressed As Column with Label ---
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: 4.0,
                            left: 4.0,
                          ),
                          child: Text(
                            'Addressed As:',
                            style: AppStyles.labelTextStyle(context).copyWith(
                              fontSize: 13,
                              color: CupertinoColors.systemGrey,
                            ),
                          ),
                        ),
                        _buildModernTextField(
                          context: context,
                          controller: _selectedContactAddressedAsController,
                          placeholder: 'Addressed As',
                        ),
                        // --- End Addressed As Column ---
                      ],
                      // --- END Editable Fields ---
                    ],
                  )
                  : const SizedBox.shrink(), // Show nothing if not adding and nothing selected
        ),
      ],
    );
  }
}

// Note: The buildSubtitleText function might need to be moved here or imported correctly.
// Assuming it's in formatting_utils.dart as per the imports.
