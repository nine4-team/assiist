import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // For AnimatedSize etc.
// ADD explicit import for core widgets
// import 'package:flutter_ui/services/highlevel_service.dart'; // REMOVE: No longer used
// Corrected import
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:assiist_front_end/theme/app_styles.dart'; // Correct package name
import 'package:assiist_front_end/core/models/contact.dart'; // ADD BACK Contact model import
// REMOVE dummy data import
// import 'package:assiist_front_end/core/dummy_data/dummy_contacts.dart';
import 'package:assiist_front_end/utils/formatting_utils.dart'; // IMPORT formatting utils

// --- Configuration --- TODO: Move to a config file or provider
// REMOVE dummy data flag
// const bool _useDummyData = true;
// --- End Configuration ---

// Callback for providing search results
typedef ContactSearchProvider = Future<List<Contact>> Function(String query);

// Define a Riverpod provider for the search logic (Placeholder)
// This would typically live in a providers/ directory
// final contactSearchProvider = Provider<ContactSearchProvider>((ref) {
//   final firestoreService = ref.watch(firestoreServiceProvider); // Assuming you have a Firestore service
//   return firestoreService.searchContacts;
// });

class ContactSearchField extends StatefulWidget {
  // final HighLevelService highLevelService; // REMOVE: No longer used
  final Function(Contact) onContactSelected;
  final Function(bool)? onToggleAdd; // Callback for add/cancel toggle
  final bool isAddingContact; // Input state for add/cancel button
  final String? initialSearchText;
  final bool showAddToggleButton; // Whether to show the +/- button
  final Function(String)? onSearchTextChanged; // Callback for text changes
  // ADD: Callback to provide the search function
  final ContactSearchProvider contactSearcher;

  const ContactSearchField({
    super.key,
    // required this.highLevelService, // REMOVE: No longer used
    required this.onContactSelected,
    required this.contactSearcher, // Require the search provider
    this.onToggleAdd,
    this.isAddingContact = false,
    this.initialSearchText,
    this.showAddToggleButton = true,
    this.onSearchTextChanged,
  });

  @override
  State<ContactSearchField> createState() => _ContactSearchFieldState();
}

class _ContactSearchFieldState extends State<ContactSearchField> {
  final _searchController = TextEditingController();
  List<Contact> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;
  Timer? _debounce;
  final Duration _debounceDuration = const Duration(milliseconds: 500);
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.initialSearchText != null) {
      _searchController.text = widget.initialSearchText!;
    }
    _searchController.addListener(_onSearchChanged);
    // TODO: Implement search logic methods (_onSearchChanged, _performSearch)
  }

  @override
  void didUpdateWidget(ContactSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the initial search text changes externally (e.g., parent clears selection)
    if (widget.initialSearchText != oldWidget.initialSearchText &&
        widget.initialSearchText != _searchController.text) {
      // Use addPostFrameCallback to avoid setting state during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchController.text = widget.initialSearchText ?? '';
          // Optionally clear results when text is externally reset
          if (widget.initialSearchText == null ||
              widget.initialSearchText!.isEmpty) {
            setState(() {
              _searchResults = [];
              _isSearching = false;
              _searchError = null;
            });
          }
        }
      });
    }
    // If the parent forces the add mode off (e.g., by selecting a contact),
    // ensure our internal state reflects no search results are relevant.
    if (!widget.isAddingContact && oldWidget.isAddingContact) {
      if (_searchResults.isNotEmpty || _isSearching || _searchError != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _searchResults = [];
              _isSearching = false;
              _searchError = null;
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // --- Search Logic (To be moved/implemented) ---
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(_debounceDuration, () {
      final searchTerm = _searchController.text.trim();
      widget.onSearchTextChanged?.call(
        searchTerm,
      ); // Notify parent of text change

      // Only search if term is long enough AND parent is not in 'Add Contact' mode
      if (searchTerm.length >= 3 && !widget.isAddingContact) {
        _performSearch(searchTerm);
      } else {
        // Clear results if search term is too short or parent IS in 'Add Contact' mode
        if (_searchResults.isNotEmpty || _isSearching || _searchError != null) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
            _searchError = null;
          });
        }
      }
    });
  }

  Future<void> _performSearch(String searchTerm) async {
    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _searchError = null;
      _searchResults = [];
    });

    try {
      // Use the provided search function
      print("Performing search for: '$searchTerm' using provided searcher.");
      final results = await widget.contactSearcher(searchTerm);

      // REMOVE old dummy/real logic split
      // if (_useDummyData) { ... } else { ... }

      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      print("Search Error: $e");
      if (!mounted) return;
      setState(() {
        _searchError = e.toString().replaceFirst('Exception: ', '');
        _isSearching = false;
        _searchResults = [];
      });
    }
  }

  // --- Contact Selection ---
  void _handleContactSelection(Contact contact) {
    // 1. Clear internal search state FIRST
    setState(() {
      _searchResults = [];
      _isSearching = false;
      _searchError = null;
    });

    // 2. Notify parent
    widget.onContactSelected(contact);

    // 3. Clear the search controller text WITHOUT triggering the listener
    //    that would call onSearchTextChanged and incorrectly clear the parent's selection.
    _searchController.removeListener(_onSearchChanged);
    _searchController.clear();
    _searchController.addListener(_onSearchChanged);

    // 4. Remove keyboard unfocus code - now handled by UnfocusScope in parent
    // FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // --- Search Bar Row ---
        Row(
          children: [
            Expanded(
              // Wrap the TextField in a GestureDetector // REMOVE GestureDetector wrapper
              // child: GestureDetector(
              //   onTap: () {
              //     // Request focus when the area is tapped
              //     _searchFocusNode.requestFocus();
              //   },
              child: CupertinoSearchTextField(
                controller: _searchController,
                focusNode: _searchFocusNode, // Assign the FocusNode
                // Use isAddingContact from widget to decide placeholder and behavior
                placeholder:
                    widget.isAddingContact
                        ? 'Adding New Contact'
                        : 'Search Contacts...',
                placeholderStyle: AppStyles.placeholderTextStyle(context),
                // Use consistent theming helper for input background
                backgroundColor: AppStyles.inputBackgroundColor(context),
                itemColor: AppStyles.secondaryTextColor(
                  context,
                ), // Theme-aware icon color
                style: AppStyles.inputTextStyle(context).copyWith(
                  color:
                      widget.isAddingContact
                          ? AppStyles.secondaryTextColor(
                            context,
                          ) // Dim color when adding
                          : AppStyles.primaryTextColor(
                            context,
                          ), // Use theme-aware text color
                ),
                onChanged: (value) {
                  // Listener handles debounced search
                  // If user types while in 'Add Contact' mode, maybe switch mode?
                  if (widget.isAddingContact && value.isNotEmpty) {
                    widget.onToggleAdd?.call(
                      false,
                    ); // Tell parent to switch mode
                  }
                },
                onSubmitted: (value) {
                  _debounce?.cancel();
                  final searchTerm = value.trim();
                  if (searchTerm.length >= 3 && !widget.isAddingContact) {
                    _performSearch(searchTerm);
                  } else {
                    // Clear results if submitted term is too short or adding contact
                    widget.onSearchTextChanged?.call(
                      searchTerm,
                    ); // Notify parent
                    setState(() {
                      _searchResults = [];
                      _isSearching = false;
                      _searchError = null;
                    });
                  }
                },
              ),
              // ),
            ),
            // --- Conditional Trailing Button --- //
            if (widget.showAddToggleButton)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: CupertinoButton(
                  padding: const EdgeInsets.all(4.0),
                  minSize: 0,
                  // color: theme.primaryColor.withOpacity(0.1), // Optional subtle background?
                  borderRadius: BorderRadius.circular(20.0),
                  onPressed: () {
                    print(
                      "DEBUG: Toggle button pressed, current isAddingContact: ${widget.isAddingContact}",
                    ); // Debug print
                    widget.onToggleAdd?.call(!widget.isAddingContact);
                  },
                  child: AppStyles.accentIcon(
                    icon:
                        widget.isAddingContact
                            ? CupertinoIcons.minus
                            : CupertinoIcons.add,
                    size: 24.0,
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 8.0), // Space before results
        // --- Search Results / Loading / Error ---
        _buildSearchResultsList(), // Call the build method directly
      ],
    );
  }

  // --- Builder for Search Results ---
  Widget _buildSearchResultsList() {
    // Handle loading state first
    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    // Handle error state next
    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Error: $_searchError',
            style: const TextStyle(
              color: CupertinoColors.systemRed,
              fontSize: 15.0,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // If not loading and no error, check results
    if (_searchResults.isNotEmpty) {
      // Display the results list
      return Container(
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemFill
              .resolveFrom(context)
              .withOpacity(0.5),
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true, // Keep shrinkWrap for Column layout
          itemCount: _searchResults.length,
          itemBuilder: (context, index) {
            final contact = _searchResults[index];
            final email = contact.emails?.firstOrNull?.address;
            final phone = contact.phone_numbers?.firstOrNull?.number;
            // Use the utility function for subtitle consistency
            final subtitle = buildSubtitleText(email, phone);

            // Wrap with GestureDetector for explicit hit testing (Re-applying this)
            return GestureDetector(
              key: ValueKey(contact.id), // REVERT back to ValueKey
              behavior: HitTestBehavior.opaque,
              onTap: () => _handleContactSelection(contact),
              // Restore CupertinoListTile
              child: CupertinoListTile(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                title: IgnorePointer(
                  child: Text(
                    contact.displayName, // Title
                    style: AppStyles.inputTextStyle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                subtitle:
                    subtitle !=
                            'No contact info' // Check if subtitle has content
                        ? IgnorePointer(
                          child: Text(
                            subtitle, // Subtitle
                            style: AppStyles.placeholderTextStyle(
                              context,
                            ).copyWith(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                        : null,
                backgroundColor:
                    Colors.transparent, // Make individual tiles transparent
              ),
            );
          },
        ),
      );
    } else {
      // Results are empty. Decide if it's because no search was done yet,
      // the search term was too short, or the search yielded no results.
      final currentText = _searchController.text.trim();
      if (currentText.length >= 3 && !widget.isAddingContact) {
        // A search was likely attempted for a valid term but found nothing.
        return const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'No contacts found.',
              style: TextStyle(
                color: CupertinoColors.systemGrey,
                fontSize: 15.0,
              ),
            ),
          ),
        );
      } else {
        // No search attempted or term too short, or in adding mode - show nothing.
        return Container(); // Or SizedBox.shrink()
      }
    }
  }
}

// --- Helper Functions ---
// REMOVED _formatPhoneNumber and _buildSubtitleText - Moved to formatting_utils.dart


 // Helper extension for CupertinoListTile if needed later for more styling
 // extension CupertinoListTileHelper on CupertinoListTile {
//   static CupertinoListTile create({ ... }) { ... }
// } 