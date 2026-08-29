// lib/screens/settings_screen.dart (Refactored with Cupertino)
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // ADDED Material import
import 'package:flutter_riverpod/flutter_riverpod.dart'; // ADDED: Riverpod import
import 'package:assiist_front_end/theme/app_styles.dart'; // Import AppStyles
import 'package:assiist_front_end/providers/theme_provider.dart'; // NEW: Theme provider
import 'add_calendar_wizard_screen.dart'; // IMPORT
import 'configure_contact_sync_wizard_screen.dart'; // IMPORT
import 'package:flutter_slidable/flutter_slidable.dart'; // <<< ADD Import
import 'package:assiist_front_end/widgets/pending_contact_item.dart';
import 'package:assiist_front_end/core/models/pending_contact.dart';
import 'package:assiist_front_end/widgets/slidable_pending_contact_item.dart';
import 'package:assiist_front_end/utils/navigation_helpers.dart';
import 'package:assiist_front_end/core/models/text_message_example.dart';
import 'package:assiist_front_end/core/models/calendar_connection.dart';
// Import providers
import 'package:assiist_front_end/providers/auth_providers.dart'; // For authServiceProvider, baseUrlProvider
import 'package:assiist_front_end/providers/repository_providers.dart'; // For various repository providers
import 'package:assiist_front_end/providers/service_providers.dart'; // For contactSyncServiceProvider
// Keep NativeCalendarService for now, can be refactored to a provider later if complex
import 'package:assiist_front_end/services/native_calendar_service.dart';

// Import specific repository implementations that might not have dedicated providers yet (or if we need their type)
import 'package:assiist_front_end/data/repositories/api/api_text_message_examples_repository.dart';
import 'package:assiist_front_end/data/repositories/api/api_calendar_connections_repository.dart';
import 'package:assiist_front_end/core/repositories/account_repository.dart';
import 'package:assiist_front_end/data/repositories/api/api_account_repository.dart';
import 'package:assiist_front_end/core/repositories/user_settings_repository.dart';
import 'package:assiist_front_end/data/repositories/api/api_user_settings_repository.dart';
import 'package:assiist_front_end/core/models/account_details.dart'; // ADDED
import 'package:assiist_front_end/widgets/standard_modal_sheet.dart';
import 'package:assiist_front_end/widgets/notes_input_field.dart';

// CHANGED: to ConsumerStatefulWidget
class SettingsScreen extends ConsumerStatefulWidget {
  @override
  // CHANGED: to ConsumerState
  _SettingsScreenState createState() => _SettingsScreenState();
}

// CHANGED: to ConsumerState
class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with TickerProviderStateMixin {
  final NativeCalendarService _nativeCalendarService =
      NativeCalendarService(); // Kept for now, as in HEAD

  // KEEP Native permission state (as in HEAD)
  bool _hasNativeCalendarPerms = false;
  bool _hasNativeContactsPerms =
      false; // Placeholder in HEAD, proper check needed

  // State for contact sync - matches HEAD's `_configuredContactSyncSource`
  String? _configuredContactSyncSource;
  // These were added for Riverpod version for more detailed display, HEAD is simpler.
  String? _configuredContactSyncPriority;
  // bool _loadingContactSyncSettings = false;
  // String? _contactSyncSettingsError;
  // bool _isSyncingContacts = false;
  // String? _syncStatusMessage;

  // State for Ignored Emails - matches HEAD
  List<PendingContact> _ignoredEmails = [];
  bool _loadingIgnoredEmails = false;
  String? _ignoredEmailsError;
  final Set<String> _ignoreItemsBeingProcessed = {}; // As in HEAD

  // SlidableController management for ignore list
  final Map<String, SlidableController> _ignoreSlidableControllers = {};

  // State for text message examples - matches HEAD
  List<TextMessageExample> _textExamples = [];
  bool _loadingExamples = true;
  String? _examplesError;

  // State for calendar connections - matches HEAD
  List<CalendarConnection> _connectedCalendars = [];
  bool _loadingCalendars = true;
  String? _calendarsError;

  // State for business description
  String? _businessDescription;
  bool _loadingBusinessDescription =
      true; // Will be controlled by _loadingAccountDetails
  String? _businessDescriptionError;
  String? _tempBusinessDescription; // ADDED for editing

  // State for business type
  String? _businessType;
  bool _loadingBusinessType =
      true; // Will be controlled by _loadingAccountDetails
  String? _businessTypeError;
  String? _tempSelectedBusinessType;

  // ADDED: Combined loading and error for account details
  bool _loadingAccountDetails = true;
  String? _accountDetailsError;

  // Define business types
  static const List<String> _businessTypes = [
    'Real Estate Agent',
    'Loan Officer',
    'Roofer',
    'HVAC Technician',
    'Plumber',
    'Electrician',
    'General Contractor',
    'Landscaper',
    'Auto Mechanic',
    'Personal Trainer',
    'Photographer',
    'Event Planner',
    'Cleaning Service',
    'Moving Company',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _performInitialFetches();
      }
    });
  }

  @override
  void dispose() {
    // Dispose all slidable controllers
    for (final controller in _ignoreSlidableControllers.values) {
      controller.dispose();
    }
    _ignoreSlidableControllers.clear();
    super.dispose();
  }

  Future<void> _performInitialFetches() async {
    if (!mounted) return;
    // Show a general loading indicator for the whole screen perhaps, or for relevant sections
    setState(() {
      _loadingAccountDetails = true; // Start loading account details
      // Other loading flags can be managed as well if they are still separate
    });

    _checkPermissions();
    _fetchContactSyncSettings();
    _fetchTextExamples();
    _fetchConnectedCalendars();
    await _fetchAccountDetails(); // This line should already exist or be fine if added here

    if (mounted) {
      setState(() {
        // Once all fetches are initiated, specific loading flags are managed by their respective methods
        // _loadingAccountDetails might be set to false at the end of _fetchAccountDetails
      });
    }
  }

  // ADDED: Fetch combined account details
  Future<void> _fetchAccountDetails() async {
    if (!mounted) return;
    setState(() {
      _loadingAccountDetails = true;
      _accountDetailsError = null;
      _businessDescriptionError = null;
      _businessTypeError = null;
    });
    try {
      final accountRepo = ref.read(accountRepositoryProvider);
      final details = await accountRepo.getAccountDetails();
      if (mounted) {
        setState(() {
          if (details != null) {
            _businessDescription = details.businessDescription;
            _businessType = details.businessType;
            _tempBusinessDescription = details.businessDescription;
            _tempSelectedBusinessType = details.businessType;
          } else {
            _businessDescription = null;
            _businessType = null;
            _tempBusinessDescription = null;
            _tempSelectedBusinessType = null;
          }
          _loadingAccountDetails = false;
          _loadingBusinessDescription = false;
          _loadingBusinessType = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _accountDetailsError =
              "Failed to load account details: ${e.toString()}";
          _loadingAccountDetails = false;
          _loadingBusinessDescription = false;
          _loadingBusinessType = false;
        });
      }
    }
  }

  // ADDED: Save combined account details
  Future<void> _saveAccountDetails() async {
    if (!mounted) return;

    bool hasChanges =
        (_tempSelectedBusinessType != _businessType ||
            _tempBusinessDescription != _businessDescription);

    // If nothing was ever loaded (all null) and temps are still null, nothing to save.
    bool isInitialNullState =
        _businessType == null &&
        _businessDescription == null &&
        _tempSelectedBusinessType == null &&
        _tempBusinessDescription == null;

    if (isInitialNullState) {
      // Potentially show a message that there's nothing to save yet.
      // print("Nothing to save, initial state is empty.");
      return;
    }

    if (!hasChanges) {
      // No actual value changes from persistent state
      // print("No changes to save in account details.");
      // Optionally, show a toast or snackbar: "No changes to save"
      return;
    }

    setState(() {
      _loadingAccountDetails = true;
      _accountDetailsError = null;
    });

    try {
      final accountRepo = ref.read(accountRepositoryProvider);
      final request = AccountDetailsUpdateRequest(
        businessType: _tempSelectedBusinessType,
        businessDescription: _tempBusinessDescription,
      );
      final updatedDetails = await accountRepo.updateAccountDetails(request);

      if (mounted) {
        setState(() {
          _businessDescription = updatedDetails.businessDescription;
          _businessType = updatedDetails.businessType;
          _tempBusinessDescription = updatedDetails.businessDescription;
          _tempSelectedBusinessType = updatedDetails.businessType;
          _loadingAccountDetails = false;
          // Optionally, show a success message: "Account details saved!"
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _accountDetailsError =
              "Failed to save account details: ${e.toString()}";
          _loadingAccountDetails = false;
        });
      }
    }
  }

  // Simplified version to align with HEAD's needs (primarily _configuredContactSyncSource)
  Future<void> _fetchContactSyncSettings() async {
    try {
      final settingsRepo = ref.read(userSettingsRepositoryProvider);
      final settings = await settingsRepo.getContactSyncSettings();
      if (mounted) {
        setState(() {
          if (settings != null) {
            _configuredContactSyncSource = settings['source'];
            _configuredContactSyncPriority = settings['priority'];
          } else {
            _configuredContactSyncSource = null;
            _configuredContactSyncPriority = 'local_wins';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        print('Failed to load contact sync settings: $e');
      }
    }
  }

  // _saveContactSyncSettings would be called from the wizard, which updates the source.
  // The button in HEAD primarily navigates. Direct save from here isn't part of HEAD's main screen UI.

  Future<void> _checkPermissions() async {
    // As in HEAD (with placeholder for contacts)
    final hasCalPerms = await _nativeCalendarService.hasPermissions();
    final hasContactPerms = false; // Placeholder as in HEAD
    if (mounted) {
      setState(() {
        _hasNativeCalendarPerms = hasCalPerms;
        _hasNativeContactsPerms = hasContactPerms;
        if (hasContactPerms && _configuredContactSyncSource == null) {
          // Logic from HEAD
          _configuredContactSyncSource = 'ios';
        }
      });
    }
  }

  Future<void> _fetchTextExamples() async {
    // Using Riverpod providers
    if (!mounted) return;
    setState(() {
      _loadingExamples = true;
      _examplesError = null;
    });
    try {
      // Instantiate repository directly using Riverpod providers for baseUrl and authService
      final baseUrl = ref.read(baseUrlProvider);
      final authService = ref.read(authServiceProvider);
      if (baseUrl == null) throw Exception("Base URL not available");
      final textMessageExamplesRepo = ApiTextMessageExamplesRepository(
        baseUrl: baseUrl,
        authService: authService,
      );
      final examples = await textMessageExamplesRepo.fetchExamples();
      if (mounted) {
        setState(() {
          _textExamples = examples;
          _loadingExamples = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _examplesError = e.toString();
          _loadingExamples = false;
        });
      }
    }
  }

  Future<void> _fetchConnectedCalendars() async {
    // Using Riverpod providers
    if (!mounted) return;
    setState(() {
      _loadingCalendars = true;
      _calendarsError = null;
    });
    try {
      // Instantiate repository directly using Riverpod providers for baseUrl and authService
      final baseUrl = ref.read(baseUrlProvider);
      final authService = ref.read(authServiceProvider);
      if (baseUrl == null) throw Exception("Base URL not available");
      final calendarConnectionsRepo = ApiCalendarConnectionsRepository(
        baseUrl: baseUrl,
        authService: authService,
      );
      final calendars = await calendarConnectionsRepo.fetchCalendars();
      if (mounted) {
        setState(() {
          _connectedCalendars = calendars;
          _loadingCalendars = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _calendarsError = e.toString();
          _loadingCalendars = false;
        });
      }
    }
  }

  Future<void> _addTextExample(String text) async {
    // Using Riverpod providers
    try {
      // Instantiate repository directly using Riverpod providers for baseUrl and authService
      final baseUrl = ref.read(baseUrlProvider);
      final authService = ref.read(authServiceProvider);
      if (baseUrl == null) throw Exception("Base URL not available");
      final textMessageExamplesRepo = ApiTextMessageExamplesRepository(
        baseUrl: baseUrl,
        authService: authService,
      );
      final newExample = await textMessageExamplesRepo.addExample(text);
      if (mounted) {
        setState(() {
          _textExamples.insert(0, newExample);
        });
      }
    } catch (e) {
      if (mounted) {
        _showInfoDialog('Error', 'Failed to add text example: $e');
      }
    }
  }

  Future<void> _removeTextExample(String id) async {
    // Using Riverpod providers
    try {
      // Instantiate repository directly using Riverpod providers for baseUrl and authService
      final baseUrl = ref.read(baseUrlProvider);
      final authService = ref.read(authServiceProvider);
      if (baseUrl == null) throw Exception("Base URL not available");
      final textMessageExamplesRepo = ApiTextMessageExamplesRepository(
        baseUrl: baseUrl,
        authService: authService,
      );
      await textMessageExamplesRepo.deleteExample(id);
      if (mounted) {
        setState(() {
          _textExamples.removeWhere((ex) => ex.id == id);
        });
      }
    } catch (e) {
      if (mounted) {
        _showInfoDialog('Error', 'Failed to remove text example: $e');
      }
    }
  }

  void _showInfoDialog(String title, String message) {
    // As in HEAD
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder:
          (context) => CupertinoAlertDialog(
            title: Text(title),
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

  Future<void> _handleNativeCalendarRequest() async {
    // As in HEAD
    if (await _nativeCalendarService.requestPermissions()) {
      if (mounted) setState(() => _hasNativeCalendarPerms = true);
      _showInfoDialog(
        'Permission Granted',
        'Device calendar access granted. You can now add it via \'Add Calendar\'.',
      );
    } else {
      _showInfoDialog(
        'Permission Required',
        'Calendar permission is required to add the device calendar.',
      );
    }
  }

  // _handleNativeCalendarSync not present in HEAD's UI flow from settings screen directly

  Future<void> _handleNativeContactsRequest() async {
    // As in HEAD (placeholder logic)
    print("Request Native Contacts Perms Tapped");
    await Future.delayed(const Duration(milliseconds: 500));
    bool granted = true;
    if (mounted) {
      setState(() => _hasNativeContactsPerms = granted);
      if (granted) {
        _configuredContactSyncSource =
            'ios'; // Matches HEAD's optimistic update
        _showInfoDialog(
          'Permission Granted',
          'Device contacts access granted. Sync is now configured.',
        );
      } else {
        _showInfoDialog(
          'Permission Required',
          'Contacts permission is required to sync device contacts.',
        );
      }
    }
  }

  // _handleNativeContactsSync not present in HEAD's UI flow from settings screen directly

  // Define a provider for ignored pending contacts with autoDispose
  final ignoredPendingContactsProvider =
      FutureProvider.autoDispose<List<PendingContact>>((ref) async {
        final pendingContactRepo = ref.read(pendingContactRepositoryProvider);
        return await pendingContactRepo.getPendingContacts(status: 'ignored');
      });

  List<String> _getConnectedGoogleEmails() {
    // Helper used in HEAD's AddCalendarWizard navigation
    return _connectedCalendars
        .where((cal) => cal.provider == 'google' && cal.email.isNotEmpty)
        .map((cal) => cal.email)
        .toList();
  }

  // Manual contact sync button and logic from Riverpod version is NOT part of HEAD's visual structure for this screen.
  // Future<void> _handleManualContactSync() async { ... }

  // --- Helper Widgets from HEAD --- //

  // ADDED BACK: _buildSectionTitle from HEAD
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 12.0, top: 8.0),
      child: Text(
        title,
        style: AppStyles.labelTextStyle(
          context,
        ).copyWith(color: AppStyles.primaryTextColor(context)),
      ),
    );
  }

  // REMOVED _buildToggleItem, _buildActionItem, _buildDetailItem as they are not part of HEAD's structure.

  // MODIFIED: _buildContactSyncButton to match HEAD (CupertinoButton)
  Widget _buildContactSyncButton() {
    String title = 'Sync Contacts'; // Title is simpler in HEAD
    bool configured = _configuredContactSyncSource != null;
    IconData icon = CupertinoIcons.arrow_2_circlepath_circle;
    if (configured) {
      // title = 'Sync Contacts'; // Already set
      icon = CupertinoIcons.checkmark_seal_fill;
    }
    return AppStyles.filledButton(
      context: context,
      text: title,
      icon: icon,
      iconSize: 22.0,
      onPressed: () async {
        // Navigation logic from HEAD
        // print("Navigate to Contact Sync Wizard"); // Already in HEAD
        final result = await Navigator.push<Map<String, String?>>(
          // MODIFIED: Expect Map<String, String?>
          context,
          CupertinoPageRoute(
            builder:
                (_) => ConfigureContactSyncWizardScreen(
                  initialSource: _configuredContactSyncSource,
                  initialPriority: _configuredContactSyncPriority, // ADDED
                ),
          ),
        );

        // Wizard now returns a map or null (if cancelled without saving)
        if (result != null && mounted) {
          setState(() {
            _configuredContactSyncSource = result['source'];
            _configuredContactSyncPriority = result['priority'];
          });
          // _fetchContactSyncSettings(); // Re-fetch to confirm (optional, as wizard returns the saved values)
        }
        // Always re-fetch settings when wizard closes, to get latest confirmed state
        // especially if user cancelled or if there was an error saving in wizard not reflected in pop result.
        _fetchContactSyncSettings();
      },
    );
  }

  // _navigateToConfigureContactSync is folded into _buildContactSyncButton's onPressed

  // MODIFIED: _buildIgnoreListSection to match HEAD structure
  Widget _buildIgnoreListSection() {
    return Consumer(
      builder: (context, ref, _) {
        final ignoredContactsAsync = ref.watch(ignoredPendingContactsProvider);
        return ignoredContactsAsync.when(
          data: (ignoredContacts) {
            // Clean up controllers for contacts that no longer exist
            final currentIds =
                ignoredContacts.map((contact) => contact.id).toSet();
            final controllersToRemove =
                _ignoreSlidableControllers.keys
                    .where((id) => !currentIds.contains(id))
                    .toList();
            for (final id in controllersToRemove) {
              final controller = _ignoreSlidableControllers.remove(id);
              controller?.dispose();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('CALENDAR IGNORE LIST'),
                ignoredContacts.isEmpty
                    ? Container(
                      padding: const EdgeInsets.all(16),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No emails in ignore list',
                        style: AppStyles.labelTextStyle(
                          context,
                        ).copyWith(color: AppStyles.primaryTextColor(context)),
                        textAlign: TextAlign.left,
                      ),
                    )
                    : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: ignoredContacts.length,
                      itemBuilder: (context, index) {
                        final contact = ignoredContacts[index];
                        final controller = _ignoreSlidableControllers
                            .putIfAbsent(
                              contact.id,
                              () => SlidableController(this),
                            );

                        return SlidablePendingContactItem(
                          pendingContact: contact,
                          onAdd: (context, contact) {
                            final pendingContactRepo = ref.read(
                              pendingContactRepositoryProvider,
                            );
                            pendingContactRepo
                                .updatePendingContactStatus(contact.id, 'added')
                                .then((_) {
                                  // Invalidate the ignored contacts provider to refresh the list
                                  ref.invalidate(
                                    ignoredPendingContactsProvider,
                                  );
                                });
                            NavigationHelpers.navigateToLogNoteScreen(
                              context,
                              potentialContactEmail: contact.email,
                              appointmentTitle:
                                  contact.sourceEventTitle ??
                                  contact.displayName,
                              appointmentNotes: contact.appointmentNotes,
                              appointmentTime: contact.appointmentTime,
                            );
                          },
                          onIgnore: null,
                          controller: controller,
                          showSubtitle: false,
                          onTap: () {
                            if (controller.actionPaneType.value !=
                                ActionPaneType.none) {
                              controller.close();
                            } else {
                              controller.openEndActionPane();
                            }
                          },
                          isProcessing: _ignoreItemsBeingProcessed.contains(
                            contact.id,
                          ),
                        );
                      },
                    ),
              ],
            );
          },
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error:
              (err, _) => Center(
                child: Text(
                  'Error loading ignore list: $err',
                  // Error text styling - keeping red color for error states
                  style: AppStyles.labelTextStyle(
                    context,
                  ).copyWith(color: CupertinoColors.systemRed),
                ),
              ),
        );
      },
    );
  }

  // MODIFIED: _buildConnectedCalendarsList to match calendar ignore list styling
  Widget _buildConnectedCalendarsList() {
    if (_loadingCalendars) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_calendarsError != null) {
      return Center(
        child: Text(
          'Error loading calendars: $_calendarsError',
          // Error text styling - keeping red color for error states
          style: AppStyles.labelTextStyle(
            context,
          ).copyWith(color: CupertinoColors.systemRed),
        ),
      );
    }
    if (_connectedCalendars.isEmpty) {
      return const SizedBox.shrink(); // As in HEAD
    }
    // Updated to match ignore list styling
    return Column(
      children:
          _connectedCalendars.map((cal) {
            // Logic for icon and display message from HEAD
            bool needsReAuth = cal.syncStatus == 'needs_reauthentication';
            IconData statusIcon = CupertinoIcons.calendar;
            Color iconColor = AppStyles.accentTextColor(context);
            String? displayMessage;

            if (cal.provider == 'google')
              statusIcon =
                  CupertinoIcons.globe; // Simplified from HEAD for this example

            if (needsReAuth) {
              statusIcon = CupertinoIcons.exclamationmark_circle_fill;
              iconColor = CupertinoColors.systemYellow.resolveFrom(context);
              displayMessage = "Error. Please remove and re-add.";
            } else if (cal.syncStatus != null &&
                cal.syncStatus != 'active' &&
                cal.syncStatusMessage != null &&
                cal.syncStatusMessage!.isNotEmpty) {
              statusIcon = CupertinoIcons.info_circle;
              iconColor = CupertinoColors.systemBlue.resolveFrom(context);
              displayMessage = cal.syncStatusMessage;
            }

            return Container(
              // Match BasicListItem styling
              margin: const EdgeInsets.only(bottom: 8.0),
              padding: const EdgeInsets.only(
                top: 12.0,
                bottom: 12.0,
                left: 12.0,
                right: 12.0,
              ),
              decoration: BoxDecoration(
                color: AppStyles.cardBackgroundColor(context),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: Icon(statusIcon, color: iconColor, size: 28.0),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          cal.email,
                          style: AppStyles.inputTextStyle(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (displayMessage != null &&
                            displayMessage.isNotEmpty) ...[
                          const SizedBox(height: 2.0),
                          Text(
                            displayMessage,
                            style: AppStyles.captionTextStyle(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minSize: 0,
                    child: AppStyles.accentIcon(
                      icon: CupertinoIcons.delete,
                      size: 22,
                    ),
                    onPressed: () {
                      // Logic from HEAD
                      showCupertinoDialog(
                        context: context,
                        builder:
                            (context) => CupertinoAlertDialog(
                              title: const Text('Remove this calendar sync?'),
                              content: Text(cal.email),
                              actions: [
                                CupertinoDialogAction(
                                  isDestructiveAction: true,
                                  child: const Text('Remove'),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _removeCalendarIntegration(
                                      cal.email,
                                    ); // Call to method below
                                  },
                                ),
                                CupertinoDialogAction(
                                  isDefaultAction: true,
                                  child: const Text('Cancel'),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                      );
                    },
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }

  // ADDED: _removeCalendarIntegration method from HEAD (uses Riverpod provider)
  Future<void> _removeCalendarIntegration(String email) async {
    try {
      // Instantiate repository directly using Riverpod providers for baseUrl and authService
      final baseUrl = ref.read(baseUrlProvider);
      final authService = ref.read(authServiceProvider);
      if (baseUrl == null) throw Exception("Base URL not available");
      final calendarConnectionsRepo = ApiCalendarConnectionsRepository(
        baseUrl: baseUrl,
        authService: authService,
      );
      await calendarConnectionsRepo.removeCalendar(email);
      if (mounted) {
        setState(() {
          _connectedCalendars.removeWhere((cal) => cal.email == email);
        });
      }
      // print('Removed calendar integration: $email'); // From HEAD
    } catch (e) {
      _showInfoDialog('Error', 'Failed to remove calendar: $e');
    }
  }

  // MODIFIED: _buildLogoutButton to match HEAD (CupertinoButton)
  Widget _buildLogoutButton() {
    // As in HEAD (styling and action)
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: AppStyles.accentText(
        context,
        'Logout',
        style: AppStyles.inputTextStyle(context),
      ),
      onPressed: () async {
        final authService = ref.read(authServiceProvider); // Using Riverpod
        await authService.signOut();
        if (mounted) {
          // Ensure mounted check before navigation
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/login', (Route<dynamic> route) => false);
        }
      },
    );
  }

  // MODIFIED: _buildTextMessageExamplesList to match HEAD structure
  Widget _buildTextMessageExamplesList() {
    if (_loadingExamples) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_examplesError != null) {
      return Center(
        child: Text(
          'Error loading examples: $_examplesError',
          style: AppStyles.labelTextStyle(
            context,
          ).copyWith(color: CupertinoColors.systemRed),
        ),
      );
    }
    final examples = _textExamples;
    // Structure from HEAD: Column with Button then ListView.builder of Container(Row(...))
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start, // Matches HEAD's implied Column behavior
      children: [
        AppStyles.filledButton(
          context: context,
          text: 'Add Text Message Example',
          icon: CupertinoIcons.chat_bubble_2,
          iconSize: 22.0,
          onPressed: () => _showAddTextExampleDialog(),
        ),
        const SizedBox(height: 12), // As in HEAD
        if (examples.isNotEmpty)
          ListView.builder(
            // As in HEAD
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: examples.length,
            itemBuilder: (context, index) {
              final example = examples[index];
              return Container(
                // Match BasicListItem styling
                margin: const EdgeInsets.only(bottom: 8.0),
                decoration: BoxDecoration(
                  color: AppStyles.cardBackgroundColor(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  // As in HEAD
                  children: [
                    Padding(
                      // As in HEAD
                      padding: EdgeInsets.only(
                        top: 12.0,
                        bottom: 12.0,
                        left: 12.0,
                        right: 12.0,
                      ),
                      child: AppStyles.accentIcon(
                        icon: CupertinoIcons.chat_bubble_2,
                        size: 22,
                      ),
                    ),
                    Expanded(
                      // As in HEAD
                      child: GestureDetector(
                        // As in HEAD
                        onTap: () {
                          // Dialog logic from HEAD
                          showCupertinoDialog(
                            context: context,
                            builder:
                                (context) => CupertinoAlertDialog(
                                  content: Padding(
                                    padding: const EdgeInsets.only(top: 12.0),
                                    child: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          AppStyles.accentIcon(
                                            icon: CupertinoIcons.chat_bubble_2,
                                            size: 20.0,
                                          ),
                                          const SizedBox(height: 12.0),
                                          Text(
                                            'Text Example',
                                            style: AppStyles.h3TextStyle(
                                              context,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 12.0),
                                          Text(
                                            example.exampleText,
                                            style: AppStyles.bodyTextStyle(
                                              context,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  actions: [
                                    CupertinoDialogAction(
                                      isDestructiveAction: true,
                                      child: const Text('Delete'),
                                      onPressed: () async {
                                        await _removeTextExample(
                                          example.id,
                                        ); // Uses Riverpod
                                        if (context.mounted)
                                          Navigator.pop(context);
                                      },
                                    ),
                                    CupertinoDialogAction(
                                      isDefaultAction: true,
                                      child: const Text('Close'),
                                      onPressed: () => Navigator.pop(context),
                                    ),
                                  ],
                                ),
                          );
                        },
                        child: Padding(
                          // As in HEAD
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            example.exampleText,
                            style: AppStyles.bodyTextStyle(context),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    CupertinoButton(
                      // As in HEAD
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minSize: 0,
                      child: AppStyles.accentIcon(
                        icon: CupertinoIcons.delete,
                        size: 22,
                      ),
                      onPressed:
                          () => _removeTextExample(example.id), // Uses Riverpod
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  // ADDED: _showAddTextExampleDialog from HEAD
  Future<void> _showAddTextExampleDialog() async {
    final textController = TextEditingController();
    final focusNode = FocusNode();

    return showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return StandardModalSheet(
          title: 'Add Text Example',
          icon: CupertinoIcons.chat_bubble_2,
          content: NotesInputField(
            notesController: textController,
            notesFocusNode: focusNode,
            placeholder: 'Enter your text example',
            minLines: 3,
            maxLines: 5,
          ),
          onCancel: () => Navigator.pop(sheetContext),
          onSave: () async {
            final text = textController.text.trim();
            if (text.isNotEmpty) {
              await _addTextExample(text);
            }
            if (sheetContext.mounted) Navigator.pop(sheetContext);
          },
        );
      },
    );
  }

  // --- Restored Business Description Dialog and Section ---
  Future<void> _showEditBusinessDescriptionDialog() async {
    final textController = TextEditingController(
      text: _tempBusinessDescription ?? _businessDescription,
    );
    final focusNode = FocusNode();

    return showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return StandardModalSheet(
          title: 'Business Description',
          icon: CupertinoIcons.briefcase_fill,
          content: NotesInputField(
            notesController: textController,
            notesFocusNode: focusNode,
            placeholder: 'E.g., Full-service residential real estate agent',
            minLines: 3,
            maxLines: 5,
          ),
          onCancel: () => Navigator.pop(sheetContext),
          onSave: () async {
            final text = textController.text.trim();
            setState(() {
              _tempBusinessDescription = text.isNotEmpty ? text : null;
            });
            await _saveAccountDetails();
            if (sheetContext.mounted) Navigator.pop(sheetContext);
          },
        );
      },
    );
  }

  Widget _buildBusinessDescriptionSection() {
    if (_loadingAccountDetails) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_businessDescription != null && _businessDescription!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 6.0),
            child: Text(
              _businessDescription!,
              style: AppStyles.bodyTextStyle(context),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              onPressed: _showEditBusinessDescriptionDialog,
              child: AppStyles.accentText(context, 'Edit'),
            ),
          ),
        ],
      );
    } else {
      return Align(
        alignment: Alignment.centerLeft,
        child: AppStyles.filledButton(
          context: context,
          text: 'Add Business Description',
          onPressed: _showEditBusinessDescriptionDialog,
        ),
      );
    }
  }

  // --- Modified Business Type Section (Picker with Save in Modal) ---
  Future<void> _showEditBusinessTypeDialog() async {
    final textController = TextEditingController(
      text: _tempSelectedBusinessType,
    );
    return showCupertinoDialog(
      context: context,
      builder:
          (context) => CupertinoAlertDialog(
            title: const Text('Business Type'),
            content: Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: CupertinoTextField(
                controller: textController,
                placeholder: 'Enter your business type',
                autofocus: true,
                style: CupertinoTheme.of(context).textTheme.textStyle,
              ),
            ),
            actions: [
              CupertinoDialogAction(
                isDestructiveAction: true,
                child: AppStyles.accentText(context, 'Cancel'),
                onPressed: () => Navigator.pop(context),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                child: AppStyles.accentText(context, 'Save'),
                onPressed: () async {
                  final text = textController.text.trim();
                  setState(() {
                    _tempSelectedBusinessType = text.isNotEmpty ? text : null;
                  });
                  await _saveAccountDetails();
                  if (mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
    );
  }

  // Helper to show the business type picker modal
  Future<void> _showBusinessTypePickerModal() async {
    int initialIndex =
        _tempSelectedBusinessType != null
            ? _businessTypes.indexOf(_tempSelectedBusinessType!)
            : (_businessType != null
                ? _businessTypes.indexOf(_businessType!)
                : 0);
    if (initialIndex < 0) initialIndex = 0;

    // Initialize _tempSelectedBusinessType if it's null - this ensures that
    // if the user just hits "Save" without changing selection, we save the displayed value
    if (_tempSelectedBusinessType == null) {
      setState(() {
        _tempSelectedBusinessType = _businessTypes[initialIndex];
      });
    }

    await showCupertinoModalPopup<void>(
      context: context,
      builder:
          (BuildContext modalContext) => Container(
            height: 280,
            padding: const EdgeInsets.only(top: 6.0),
            color: CupertinoColors.systemBackground.resolveFrom(modalContext),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: CupertinoColors.separator.resolveFrom(
                          modalContext,
                        ),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CupertinoButton(
                        child: AppStyles.accentText(modalContext, 'Cancel'),
                        onPressed: () {
                          setState(() {
                            _tempSelectedBusinessType = _businessType;
                          });
                          Navigator.pop(modalContext);
                        },
                      ),
                      CupertinoButton(
                        child: AppStyles.accentText(modalContext, 'Save'),
                        onPressed: () {
                          Navigator.pop(modalContext);
                          if (_tempSelectedBusinessType == 'Other') {
                            _showEditBusinessTypeDialog();
                          } else {
                            _saveAccountDetails();
                          }
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    magnification: 1.22,
                    squeeze: 1.2,
                    useMagnifier: true,
                    itemExtent: 32.0,
                    scrollController: FixedExtentScrollController(
                      initialItem: initialIndex,
                    ),
                    onSelectedItemChanged: (int selectedItem) {
                      setState(() {
                        _tempSelectedBusinessType =
                            _businessTypes[selectedItem];
                      });

                      // If "Other" is selected, show the text input dialog immediately
                      if (_businessTypes[selectedItem] == 'Other') {
                        // We need to delay the dialog slightly to allow the picker to update
                        Future.delayed(const Duration(milliseconds: 200), () {
                          Navigator.pop(modalContext);
                          _showEditBusinessTypeDialog();
                        });
                      }
                    },
                    children:
                        _businessTypes
                            .map(
                              (type) => Center(
                                child: Text(
                                  type,
                                  style:
                                      CupertinoTheme.of(
                                        context,
                                      ).textTheme.textStyle,
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildBusinessTypeSection() {
    if (_loadingAccountDetails) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_businessType != null && _businessType!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 6.0),
            child: Text(
              _businessType!,
              style: AppStyles.bodyTextStyle(context),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              onPressed: () {
                // Open picker modal to change type, or text dialog for 'Other'
                _showBusinessTypePickerModal();
              },
              child: AppStyles.accentText(context, 'Edit'),
            ),
          ),
        ],
      );
    } else {
      return Align(
        alignment: Alignment.centerLeft,
        child: AppStyles.filledButton(
          context: context,
          text: 'Set Business Type',
          onPressed: _showBusinessTypePickerModal,
        ),
      );
    }
  }

  // ---------------- Appearance ----------------------------------------- //

  Widget _buildAppearanceSection() {
    final themeMode = ref.watch(themeModeProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: CupertinoSlidingSegmentedControl<AppThemeMode>(
        groupValue: themeMode,
        backgroundColor: AppStyles.segmentedTrackColor(context),
        thumbColor: AppStyles.segmentedThumbColor(context),
        children: const {
          AppThemeMode.system: Text('System'),
          AppThemeMode.light: Text('Light'),
          AppThemeMode.dark: Text('Dark'),
        },
        onValueChanged: (AppThemeMode? mode) {
          if (mode != null) {
            ref.read(themeModeProvider.notifier).set(mode);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);

    return CupertinoPageScaffold(
      backgroundColor: AppStyles.subtleBackgroundColor(context),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Settings & Sync'),
        backgroundColor: theme.barBackgroundColor.withOpacity(0.7),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
          children: [
            _buildSectionTitle('BUSINESS TYPE'),
            _buildBusinessTypeSection(),
            const SizedBox(height: 24),

            _buildSectionTitle('BUSINESS DESCRIPTION'),
            _buildBusinessDescriptionSection(),
            const SizedBox(height: 24),

            _buildSectionTitle('TRAIN ASSISTANT'),
            _buildTextMessageExamplesList(),
            const SizedBox(height: 24),

            _buildSectionTitle('CONTACTS'),
            Align(
              alignment: Alignment.centerLeft,
              child: _buildContactSyncButton(),
            ),
            const SizedBox(height: 24),

            _buildSectionTitle('CALENDARS'),
            Align(
              alignment: Alignment.centerLeft,
              child: AppStyles.filledButton(
                context: context,
                text: 'Add Calendar',
                icon: CupertinoIcons.calendar,
                iconSize: 20.0,
                onPressed: () async {
                  final result = await Navigator.push<CalendarConnection>(
                    context,
                    CupertinoPageRoute(
                      builder:
                          (_) => AddCalendarWizardScreen(
                            connectedGoogleEmails: _getConnectedGoogleEmails(),
                          ),
                    ),
                  );
                  if (result != null && mounted) {
                    setState(() {
                      _connectedCalendars.add(result);
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            _buildConnectedCalendarsList(),
            const SizedBox(height: 24),

            // --- Ignore List Section --- //
            _buildIgnoreListSection(),
            const SizedBox(height: 24),

            // --- Logout Button at Bottom --- //
            _buildLogoutButton(),
            const SizedBox(height: 24),

            // --- Appearance (Theme) Section --- //
            _buildSectionTitle('APPEARANCE'),
            _buildAppearanceSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// Define pendingContactsProvider directly in the file
final pendingContactsProvider = FutureProvider<List<PendingContact>>((
  ref,
) async {
  final pendingContactRepo = ref.read(pendingContactRepositoryProvider);
  return await pendingContactRepo.getPendingContacts();
});
