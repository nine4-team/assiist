import 'package:flutter/cupertino.dart';
import 'package:assiist_front_end/theme/app_styles.dart'; // Assuming styles might be needed
import 'package:assiist_front_end/widgets/nav_bar_back_button.dart';
import 'package:assiist_front_end/services/auth_service.dart'; // IMPORT
import 'package:assiist_front_end/services/native_calendar_service.dart'; // IMPORT
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:assiist_front_end/core/models/calendar_connection.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // ENSURE THIS IMPORT IS PRESENT
import 'package:app_settings/app_settings.dart';
import 'package:permission_handler/permission_handler.dart';
// TODO: Import services needed for step 2 (AuthService, NativeCalendarService)

class AddCalendarWizardScreen extends StatefulWidget {
  final List<String> connectedGoogleEmails;
  const AddCalendarWizardScreen({
    super.key,
    required this.connectedGoogleEmails,
  });

  @override
  State<AddCalendarWizardScreen> createState() =>
      _AddCalendarWizardScreenState();
}

class _AddCalendarWizardScreenState extends State<AddCalendarWizardScreen> {
  // State for the wizard
  int _currentStep = 1;
  String? _selectedSource; // e.g., 'Google', 'Outlook', iCal'
  bool _isLoading = false; // For Step 2 processing
  String _loadingMessage = ''; // Message during loading
  // State for Step 3 Confirmation
  String? _confirmedSourceType;
  String? _confirmedSourceName;
  String? _icsUrl; // Add state for iCal URL

  // Instantiate services
  final AuthService _authService = AuthService();
  final NativeCalendarService _nativeCalendarService = NativeCalendarService();

  // Add new state variables
  List<Map<String, String>>? _availableCalendars;
  Set<String> _selectedCalendarIds = {};

  // --- Dialog Helper --- //
  void _showInfoDialog(String title, String message, {List<Widget>? actions}) {
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder:
          (context) => CupertinoAlertDialog(
            title: Text(title),
            content: Text(message),
            actions:
                actions ??
                [
                  CupertinoDialogAction(
                    isDefaultAction: true,
                    child: const Text('OK'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
          ),
    );
  }

  // --- Step Navigation & Logic --- //
  void _goToStep2() {
    if (_selectedSource == null || _isLoading) return;
    setState(() {
      _currentStep = 2;
      _isLoading = true;
      _loadingMessage = _getLoadingMessage(_selectedSource!);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleAuthenticationOrPermission();
    });
  }

  String _getLoadingMessage(String source) {
    switch (source) {
      case 'Google':
        return 'Connecting to Google...';
      case 'Outlook':
        return 'Connecting to Outlook...';
      case 'Device':
        return 'Requesting calendar permissions...';
      case 'iCal':
        return 'Validating iCal feed...';
      default:
        return 'Processing...';
    }
  }

  // Add new method to show calendar selection
  void _showCalendarSelection(List<Map<String, String>> calendars) {
    setState(() {
      _availableCalendars = calendars;
      _selectedCalendarIds = {};
    });

    showCupertinoModalPopup(
      context: context,
      builder:
          (context) => CupertinoActionSheet(
            title: const Text('Select Calendars to Sync'),
            message: const Text(
              'Choose which calendars you want to sync with Assiist',
            ),
            actions: [
              ...calendars
                  .map(
                    (calendar) => CupertinoActionSheetAction(
                      onPressed: () {
                        setState(() {
                          if (_selectedCalendarIds.contains(calendar['id'])) {
                            _selectedCalendarIds.remove(calendar['id']);
                          } else {
                            _selectedCalendarIds.add(calendar['id']!);
                          }
                        });
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(calendar['name'] ?? 'Unknown Calendar'),
                          if (_selectedCalendarIds.contains(calendar['id']))
                            AppStyles.accentIcon(
                              icon: CupertinoIcons.check_mark,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              CupertinoActionSheetAction(
                isDefaultAction: true,
                onPressed: () {
                  Navigator.pop(context);
                  if (_selectedCalendarIds.isNotEmpty) {
                    _syncSelectedCalendars();
                  } else {
                    _showInfoDialog(
                      'No Selection',
                      'Please select at least one calendar to sync.',
                    );
                  }
                },
                child: const Text('Sync Selected'),
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _currentStep = 1;
                  _isLoading = false;
                });
              },
              child: const Text('Cancel'),
            ),
          ),
    );
  }

  // Add new method to sync selected calendars
  Future<void> _syncSelectedCalendars() async {
    if (_availableCalendars == null) return;

    final user = await FirebaseAuth.instance.currentUser;
    final userToken = await user?.getIdToken();
    if (user == null || userToken == null) {
      _showInfoDialog('Error', 'User not signed in. Please sign in again.');
      if (mounted) {
        setState(() {
          _currentStep = 1;
          _isLoading = false;
        });
      }
      return;
    }

    int successCount = 0;
    for (var calendar in _availableCalendars!) {
      if (_selectedCalendarIds.contains(calendar['id'])) {
        final response = await http.post(
          Uri.parse('${dotenv.env['API_URL']}/api/v1/calendars'),
          headers: {
            'Authorization': 'Bearer $userToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'provider': 'ical',
            'email': calendar['name'],
            'ics_url': calendar['url'],
          }),
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          print('Successfully added calendar: ${calendar['name']}');
          successCount++;
        } else {
          print('Failed to add calendar: ${calendar['name']}');
        }
      }
    }

    if (successCount > 0) {
      if (mounted) {
        setState(() {
          _confirmedSourceType = 'iPhone';
          _confirmedSourceName = 'iPhone Calendars';
          _currentStep = 3;
          _isLoading = false;
        });
      }
    } else {
      _showInfoDialog(
        'Error',
        'Failed to add any calendars. Please try again.',
      );
      if (mounted) {
        setState(() {
          _currentStep = 1;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleAuthenticationOrPermission() async {
    bool success = false;
    String? nameResult;
    try {
      switch (_selectedSource) {
        case 'Google':
          await _handleGoogleCalendarAdd();
          return;
        case 'Outlook':
        case 'Android':
          await Future.delayed(const Duration(seconds: 1));
          _showInfoDialog(
            'Coming Soon',
            '${_selectedSource} integration is not yet implemented.',
          );
          if (mounted) {
            setState(() {
              _currentStep = 1;
              _isLoading = false;
            });
          }
          return;
        case 'iPhone':
          bool hasPerms = await _nativeCalendarService.hasPermissions();
          if (!hasPerms) {
            hasPerms = await _nativeCalendarService.requestPermissions();
          }
          if (hasPerms) {
            // Get iCal URLs from native calendars
            final calendarUrls =
                await _nativeCalendarService.getNativeCalendarICalUrls();
            if (calendarUrls.isNotEmpty) {
              _showCalendarSelection(calendarUrls);
            } else {
              _showInfoDialog(
                'No Calendars Found',
                'No calendars were found on your device.',
              );
              if (mounted) {
                setState(() {
                  _currentStep = 1;
                  _isLoading = false;
                });
              }
            }
          } else {
            _showInfoDialog(
              'Permission Denied',
              'Calendar access is required to sync your calendars. Please enable it in Settings.',
              actions: [
                CupertinoDialogAction(
                  child: const Text('Open Settings'),
                  onPressed: () async {
                    Navigator.pop(context);
                    await openAppSettings();
                  },
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  child: const Text('OK'),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            );
            if (mounted) {
              setState(() {
                _currentStep = 1;
                _isLoading = false;
              });
            }
          }
          return;
      }

      if (success) {
        setState(() {
          _confirmedSourceType = _selectedSource;
          _confirmedSourceName = nameResult ?? '${_selectedSource} Calendar';
          _currentStep = 3;
          _isLoading = false;
        });
      } else {
        if (mounted) {
          _showInfoDialog('Failed', _getFailureMessage(_selectedSource!));
          setState(() {
            _currentStep = 1;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print("Error during auth/permission: $e");
      if (mounted) {
        _showInfoDialog('Error', 'An unexpected error occurred: $e');
        setState(() {
          _currentStep = 1;
          _isLoading = false;
        });
      }
    }
    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleCalendarAdd() async {
    setState(() {
      _isLoading = true;
    });

    // Load configuration from .env file
    final String googleWebServerClientId = dotenv.env['GOOGLE_CLIENT_ID'] ?? '';
    final String apiUrl = dotenv.env['API_URL'] ?? '';
    // Remove '/api/v1' suffix if present since we need the base URL
    final String backendBaseUrl = apiUrl.replaceAll('/api/v1', '');

    if (googleWebServerClientId.isEmpty) {
      print(
        'FATAL ERROR: GOOGLE_CLIENT_ID not found in .env file. '
        'Google Calendar linking will not work.',
      );
      _showInfoDialog(
        'Configuration Error',
        'Google Calendar integration is not configured (client ID missing). Please contact support.',
      );
      if (mounted) {
        setState(() {
          _currentStep = 1;
          _isLoading = false;
        });
      }
      return;
    }

    if (apiUrl.isEmpty) {
      print(
        'FATAL ERROR: API_URL not found in .env file. Cannot connect to backend.',
      );
      _showInfoDialog(
        'Configuration Error',
        'API URL is not configured. Please contact support.',
      );
      if (mounted) {
        setState(() {
          _currentStep = 1;
          _isLoading = false;
        });
      }
      return;
    }

    final GoogleSignIn _googleSignIn = GoogleSignIn(
      serverClientId: googleWebServerClientId,
      scopes: [
        'email',
        'https://www.googleapis.com/auth/calendar.readonly',
        'https://www.googleapis.com/auth/calendar.freebusy',
      ],
    );

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        if (mounted) {
          setState(() {
            _currentStep = 1;
            _isLoading = false;
          });
        }
        return;
      }

      final email = googleUser.email;
      if (widget.connectedGoogleEmails.contains(email)) {
        _showInfoDialog(
          'Already Connected',
          'This Google account is already connected. Please select a different account.',
        );
        if (mounted) {
          setState(() {
            _currentStep = 1;
            _isLoading = false;
          });
        }
        await _googleSignIn.signOut();
        return;
      }

      final String? serverAuthCode = googleUser.serverAuthCode;

      if (serverAuthCode == null) {
        _showInfoDialog(
          'Error',
          'Could not retrieve Google Auth Code. Please ensure you have a stable internet connection and try again.',
        );
        if (mounted) {
          setState(() {
            _currentStep = 1;
            _isLoading = false;
          });
        }
        await _googleSignIn.signOut();
        return;
      }

      final user = await FirebaseAuth.instance.currentUser;
      final userToken = await user?.getIdToken();
      if (user == null || userToken == null) {
        _showInfoDialog('Error', 'User not signed in. Please sign in again.');
        if (mounted) {
          setState(() {
            _currentStep = 1;
            _isLoading = false;
          });
        }
        await _googleSignIn.signOut();
        return;
      }

      // Exchange the auth code for tokens
      final response = await http.post(
        Uri.parse('$backendBaseUrl/api/v1/oauth/google/exchange-code'),
        headers: {
          'Authorization': 'Bearer $userToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'auth_code': serverAuthCode}),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (mounted) {
          setState(() {
            _confirmedSourceType = 'Google';
            _confirmedSourceName = email;
            _currentStep = 3;
            _isLoading = false;
          });
        }
      } else {
        String errorMessage = 'Failed to connect calendar.';
        try {
          final Map<String, dynamic> errorBody = jsonDecode(response.body);
          errorMessage = errorBody['detail'] ?? errorMessage;
        } catch (_) {
          /* Ignore parsing error, use default message */
        }
        _showInfoDialog(
          'Error',
          '$errorMessage (Status: ${response.statusCode})',
        );
        if (mounted) {
          setState(() {
            _currentStep = 1;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print("Error during Google Calendar add: $e");
      _showInfoDialog('Error', 'An unexpected error occurred: $e');
      if (mounted) {
        setState(() {
          _currentStep = 1;
          _isLoading = false;
        });
      }
      try {
        await _googleSignIn.signOut();
      } catch (signOutError) {
        print("Error signing out of Google after an exception: $signOutError");
      }
    }
  }

  String _getFailureMessage(String source) {
    switch (source) {
      case 'Google':
        return 'Could not connect to Google Calendar.';
      case 'Outlook':
      case 'Android':
      case 'iPhone':
        return '${source} integration is not yet implemented.';
      case 'iCal':
        return 'Could not validate iCal feed.';
      default:
        return 'Operation failed.';
    }
  }

  // --- Step 3 Logic --- //
  void _confirmAndPop() {
    if (_confirmedSourceType == null || _confirmedSourceName == null) {
      print("Error: Confirmation details missing.");
      setState(() => _currentStep = 1);
      return;
    }
    // Pop and return confirmed data as a CalendarConnection
    Navigator.pop(
      context,
      CalendarConnection(
        provider: _confirmedSourceType!,
        email: _confirmedSourceName!,
        accessToken: '',
        idToken: null,
        createdOn: null,
        icsUrl:
            _confirmedSourceType == 'iCal'
                ? _icsUrl
                : null, // Add iCal URL if applicable
      ),
    );
  }

  // --- Build Helpers --- //
  Widget _buildSourceOptionRow({
    required IconData icon,
    required String label,
    required String sourceValue,
    bool disabled = false,
    String? subtitle,
  }) {
    final theme = CupertinoTheme.of(context);
    final bool isSelected = _selectedSource == sourceValue;

    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed:
            disabled
                ? null
                : () {
                  setState(() {
                    if (_selectedSource == sourceValue) {
                      _selectedSource = null; // Allow deselection
                    } else {
                      _selectedSource = sourceValue;
                    }
                  });
                },
        child:
            isSelected
                ? AppStyles.gradientBorder(
                  context: context,
                  borderRadius: BorderRadius.circular(10.0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12.5,
                      horizontal: 14.5,
                    ), // Compensated for border
                    child: Row(
                      children: [
                        AppStyles.accentIcon(icon: icon, size: 24),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: AppStyles.inputTextStyle(context),
                              ),
                              if (subtitle != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2.0),
                                  child: Text(
                                    subtitle,
                                    style: AppStyles.captionTextStyle(context),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          AppStyles.accentIcon(
                            icon: CupertinoIcons.check_mark,
                            size: 22,
                          ),
                      ],
                    ),
                  ),
                )
                : Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14.0,
                    horizontal: 16.0,
                  ),
                  decoration: BoxDecoration(
                    color: AppStyles.cardBackgroundColor(context),
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Row(
                    children: [
                      AppStyles.accentIcon(icon: icon, size: 24),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: AppStyles.inputTextStyle(context),
                            ),
                            if (subtitle != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  subtitle,
                                  style: AppStyles.captionTextStyle(context),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        AppStyles.accentIcon(
                          icon: CupertinoIcons.check_mark,
                          size: 22,
                        ),
                    ],
                  ),
                ),
      ),
    );
  }

  void _showIcalUrlInput() {
    final textController = TextEditingController(text: _icsUrl);
    showCupertinoDialog(
      context: context,
      builder:
          (context) => CupertinoAlertDialog(
            title: const Text('Enter iCal Feed URL'),
            content: Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: CupertinoTextField(
                controller: textController,
                placeholder: 'https://example.com/calendar.ics',
                keyboardType: TextInputType.url,
                autofocus: true,
              ),
            ),
            actions: [
              CupertinoDialogAction(
                isDestructiveAction: true,
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => _selectedSource = null);
                },
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                child: const Text('Add'),
                onPressed: () {
                  final url = textController.text.trim();
                  if (url.isNotEmpty) {
                    setState(() => _icsUrl = url);
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);

    // Determine trailing button based on step
    Widget? trailingButton;
    if (_currentStep == 1) {
      trailingButton = CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: (_selectedSource != null && !_isLoading) ? _goToStep2 : null,
        child:
            (_selectedSource != null && !_isLoading)
                ? AppStyles.accentText(
                  context,
                  'Next',
                  style: TextStyle(fontWeight: FontWeight.bold),
                )
                : Text(
                  'Next',
                  style: TextStyle(
                    color: CupertinoColors.inactiveGray,
                    fontWeight: FontWeight.bold,
                  ),
                ),
      );
    } else if (_currentStep == 3) {
      trailingButton = CupertinoButton(
        padding: EdgeInsets.zero,
        child: AppStyles.accentText(
          context,
          'Confirm',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: _isLoading ? null : _confirmAndPop,
      );
    }
    // No trailing button for Step 2 (Loading)

    return CupertinoPageScaffold(
      backgroundColor: AppStyles.subtleBackgroundColor(context),
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          'Add Calendar - Step $_currentStep of 3',
        ), // Show total steps
        leading: _isLoading ? null : const NavBarBackButton(),
        trailing: trailingButton, // Assign the determined button
      ),
      child: SafeArea(
        child:
            _currentStep == 1
                ? _buildStep1(context)
                : _currentStep == 2
                ? _buildStep2(context)
                : _buildStep3(context), // Assumes _buildStep3 exists
      ),
    );
  }

  // Extracted Step 1 Builder
  Widget _buildStep1(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
      children: [
        Text(
          'Select calendar source:',
          style: AppStyles.labelTextStyle(context),
        ),
        const SizedBox(height: 16),
        _buildSourceOptionRow(
          icon: CupertinoIcons.calendar,
          label: 'Google Calendar',
          sourceValue: 'Google',
        ),
        const SizedBox(height: 12),
        _buildSourceOptionRow(
          icon: CupertinoIcons.envelope_fill,
          label: 'Outlook Calendar',
          sourceValue: 'Outlook',
          disabled: true,
          subtitle: 'Coming soon',
        ),
        const SizedBox(height: 12),
        _buildSourceOptionRow(
          icon: CupertinoIcons.device_phone_portrait,
          label: 'iPhone Native (iCal)',
          sourceValue: 'iPhone',
          disabled: true,
          subtitle: 'Coming soon',
        ),
        const SizedBox(height: 12),
        _buildSourceOptionRow(
          icon: CupertinoIcons.device_phone_portrait,
          label: 'Android Native',
          sourceValue: 'Android',
          disabled: true,
          subtitle: 'Coming soon',
        ),
      ],
    );
  }

  // Extracted Step 2 Builder (Loading indicator)
  Widget _buildStep2(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CupertinoActivityIndicator(radius: 14),
          const SizedBox(height: 16),
          Text(_loadingMessage, style: AppStyles.labelTextStyle(context)),
        ],
      ),
    );
  }

  // Extracted Step 3 Builder
  Widget _buildStep3(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              AppStyles.accentIcon(icon: CupertinoIcons.calendar, size: 32),
              const SizedBox(width: 12),
              Text(
                'Review and Add Calendar',
                style: AppStyles.h1TextStyle(context),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            "You're about to add this calendar to your account. Tap Confirm to finish.",
            style: AppStyles.bodyTextStyle(context),
          ),
          const SizedBox(height: 28),
          Text('Source', style: AppStyles.labelTextStyle(context)),
          Text(
            _confirmedSourceType ?? '',
            style: AppStyles.inputTextStyle(
              context,
            ).copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text('Account', style: AppStyles.labelTextStyle(context)),
          Text(
            _confirmedSourceName ?? '',
            style: AppStyles.inputTextStyle(
              context,
            ).copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
