import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_contacts/flutter_contacts.dart'
    as native; // Renamed to avoid conflict
import 'package:app_settings/app_settings.dart';
import 'package:assiist_front_end/theme/app_styles.dart';
import 'package:assiist_front_end/providers/repository_providers.dart';
import 'package:assiist_front_end/services/contact_sync_service.dart'; // For ContactSyncService and SyncPreviewData
import 'package:assiist_front_end/providers/service_providers.dart'; // For contactSyncServiceProvider
import 'package:assiist_front_end/core/repositories/user_settings_repository.dart';
import 'package:assiist_front_end/services/native_contact_access_service.dart';

class ConfigureContactSyncWizardScreen extends ConsumerStatefulWidget {
  final String? initialSource; // Expected to be "ios" for iOS, or null
  final String? initialPriority;

  const ConfigureContactSyncWizardScreen({
    super.key,
    this.initialSource,
    this.initialPriority,
  });

  @override
  ConsumerState<ConfigureContactSyncWizardScreen> createState() =>
      _ConfigureContactSyncWizardScreenState();
}

class _ConfigureContactSyncWizardScreenState
    extends ConsumerState<ConfigureContactSyncWizardScreen> {
  int _currentStep = 1;
  String? _selectedUITarget; // UI selection state: "iPhone", or null

  // Define UI option strings for clarity
  static const String _uiTargetIPhone = 'iPhone';
  static const String _uiTargetAndroid = 'Android'; // For display only
  bool _isProcessing =
      false; // General processing flag for Step 1 Next button actions

  // State for Sync Preview (Step 2)
  SyncPreviewData? _syncPreviewData;
  bool _isPreviewLoading = false;
  String? _previewError;

  // State for Syncing Process (Step 3 & 4)
  bool _isSyncing = false;
  String? _syncError;
  bool _syncSuccess = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSource == 'ios') {
      _selectedUITarget = _uiTargetIPhone;
    } else {
      _selectedUITarget = null;
    }
    // If starting directly on step 2 (e.g. from a deeplink or future resume functionality),
    // one might load preview data here. For now, it's loaded on transition.
  }

  Future<void> _loadPreviewData() async {
    if (!mounted) return;
    setState(() {
      _isPreviewLoading = true;
      _previewError = null;
      _syncPreviewData = null;
    });
    try {
      final previewData =
          await ref.read(contactSyncServiceProvider).getSyncPreview();
      if (mounted) {
        setState(() {
          _syncPreviewData = previewData;
          _isPreviewLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _previewError = "Failed to load sync preview: ${e.toString()}";
          _isPreviewLoading = false;
        });
      }
    }
  }

  Future<void> _performSync() async {
    if (!mounted) return;
    setState(() {
      _currentStep = 3; // Move to progress UI
      _isSyncing = true;
      _syncError = null;
      _syncSuccess = false;
    });

    try {
      // Perform the actual sync
      await ref.read(contactSyncServiceProvider).performTwoWaySync();
      if (mounted) {
        setState(() {
          _syncSuccess = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncError = "Sync failed: ${e.toString()}";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _currentStep = 4; // Move to completion UI
        });
      }
    }
  }

  // Modified to save settings without popping, returns true on success
  Future<bool> _processAndSaveConfiguration() async {
    final settingsRepo = ref.read(userSettingsRepositoryProvider);

    String? sourceToSave =
        (_selectedUITarget == _uiTargetIPhone) ? 'ios' : null;
    if (sourceToSave == null && _selectedUITarget == _uiTargetIPhone) {
      print("Logic Error: iPhone selected but sourceToSave is null");
      return false;
    }

    String priorityToSave = widget.initialPriority ?? 'local_wins';

    try {
      await settingsRepo.saveContactSyncSettings(sourceToSave, priorityToSave);
      // Successfully saved. For multi-step, we don't pop here.
      // We return success, and the calling method handles step transition.
      // If sourceToSave is null (e.g. user somehow unselected iPhone and we allowed 'Next')
      // this still saves the "disabled" state.
      // The calling UI (Next button) should be responsible for ensuring _selectedUITarget is valid for proceeding.
      return true;
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Failed to save settings: $e');
      }
      return false; // Indicate failure
    }
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
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

  // Replicates structure of _buildSourceOptionRow from AddCalendarWizardScreen
  Widget _buildSourceOptionRow({
    required IconData icon,
    required String label,
    required String sourceValue, // To determine if it's selected
    bool disabled = false,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final theme = CupertinoTheme.of(context);
    final bool isSelected = _selectedUITarget == sourceValue;

    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: disabled ? null : onTap,
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

  // --- Step Builder Methods ---
  Widget _buildStep1SelectionUI(BuildContext context) {
    // Mimics layout of AddCalendarWizardScreen _buildStep1
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
      child: Column(
        // Using Column instead of ListView for this fixed number of items
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SELECT SYNC SOURCE', // Matching AddCalendarWizardScreen more closely
            style: AppStyles.labelTextStyle(
              context,
            ), // Assuming this style exists
          ),
          const SizedBox(height: 16),
          _buildSourceOptionRow(
            icon: CupertinoIcons.device_phone_portrait,
            label: _uiTargetIPhone,
            sourceValue: _uiTargetIPhone, // Pass the value for selection check
            onTap: () {
              setState(() {
                if (_selectedUITarget == _uiTargetIPhone) {
                  _selectedUITarget = null;
                } else {
                  _selectedUITarget = _uiTargetIPhone;
                }
              });
            },
          ),
          const SizedBox(height: 12),
          _buildSourceOptionRow(
            icon: CupertinoIcons.device_phone_landscape,
            label: _uiTargetAndroid,
            sourceValue: _uiTargetAndroid, // Pass the value
            disabled: true,
            subtitle: 'Coming soon',
            onTap: () {}, // No action
          ),
        ],
      ),
    );
  }

  Future<void> _handlePermissionRequestAndProceed() async {
    try {
      print("[ContactSyncWizard] Checking contact access status...");

      // Check current contact access status using native method
      String status = await NativeContactAccessService.checkContactAccess();
      print("[ContactSyncWizard] Current contact access status: $status");

      if (status == "authorized") {
        // We have full access - proceed directly to preview
        print(
          "[ContactSyncWizard] Full access confirmed. Proceeding to Step 2.",
        );
        if (mounted) {
          setState(() {
            _currentStep = 2;
          });
          await _loadPreviewData();
        }
        return;
      }

      if (status == "denied" || status == "restricted") {
        // No access - guide to settings
        if (mounted) {
          _showContactAccessDeniedDialog();
        }
        return;
      }

      // For notDetermined or limited access, handle iOS 18 two-stage flow
      if (status == "notDetermined" || status == "limited") {
        print(
          "[ContactSyncWizard] Handling iOS 18 permission flow for status: $status",
        );

        if (mounted) {
          // Show explanation dialog first
          final shouldProceed = await showCupertinoDialog<bool>(
            context: context,
            builder:
                (context) => CupertinoAlertDialog(
                  title: const Text('Contact Access'),
                  content: const Text(
                    'Allow 2-way sync between your device and Assiist.',
                  ),
                  actions: [
                    CupertinoDialogAction(
                      child: const Text('Cancel'),
                      onPressed: () => Navigator.pop(context, false),
                    ),
                    CupertinoDialogAction(
                      isDefaultAction: true,
                      child: const Text('Continue'),
                      onPressed: () => Navigator.pop(context, true),
                    ),
                  ],
                ),
          );

          if (shouldProceed != true) {
            return;
          }

          // Handle iOS 18 two-stage permission flow
          try {
            String accessStatus;

            if (status == "notDetermined") {
              // First stage: Request initial contact access
              print(
                "[ContactSyncWizard] Requesting initial contact access (first stage)...",
              );
              accessStatus =
                  await NativeContactAccessService.requestInitialContactAccess();
              print("[ContactSyncWizard] Initial access result: $accessStatus");

              // If we got limited access, offer upgrade option
              if (accessStatus == 'limited') {
                print(
                  "[ContactSyncWizard] Got limited access, offering full access upgrade...",
                );

                final shouldUpgrade = await showCupertinoDialog<bool>(
                  context: context,
                  builder:
                      (context) => CupertinoAlertDialog(
                        title: const Text('Contact Access Level'),
                        content: const Text(
                          'Assiist works best with full contact access. You can choose to grant full access or continue with limited access.',
                        ),
                        actions: [
                          CupertinoDialogAction(
                            child: const Text('Continue with Limited'),
                            onPressed: () => Navigator.pop(context, false),
                          ),
                          CupertinoDialogAction(
                            isDefaultAction: true,
                            child: const Text('Grant Full Access'),
                            onPressed: () => Navigator.pop(context, true),
                          ),
                        ],
                      ),
                );

                if (shouldUpgrade == true) {
                  accessStatus =
                      await NativeContactAccessService.requestFullContactAccess();
                  print(
                    "[ContactSyncWizard] Full access upgrade result: $accessStatus",
                  );
                }
              }
            } else {
              // status == "limited" - request full access upgrade
              print(
                "[ContactSyncWizard] Already have limited access, requesting full access upgrade...",
              );
              accessStatus =
                  await NativeContactAccessService.requestFullContactAccess();
              print(
                "[ContactSyncWizard] Full access upgrade result: $accessStatus",
              );
            }

            // Handle the final result
            if (accessStatus == 'authorized' || accessStatus == 'limited') {
              print(
                "[ContactSyncWizard] Contact access granted with status: $accessStatus",
              );

              // Proceed to preview regardless of full or limited access
              if (mounted) {
                setState(() {
                  _currentStep = 2;
                });
                await _loadPreviewData();
              }
            } else if (accessStatus == 'denied') {
              print("[ContactSyncWizard] Contact access denied");
              if (mounted) {
                _showContactAccessDeniedDialog();
              }
            } else {
              print(
                "[ContactSyncWizard] Unexpected contact access status: $accessStatus",
              );
              if (mounted) {
                _showErrorDialog(
                  "Unexpected response from contact access: $accessStatus",
                );
              }
            }
          } catch (e) {
            print("[ContactSyncWizard] Error with contact access: $e");
            if (mounted) {
              _showErrorDialog("Error accessing contacts: $e");
            }
          }
        }
      }
    } catch (e) {
      print("[ContactSyncWizard] Error during contact access check: $e");
      if (mounted) {
        _showErrorDialog("Error checking contact access: $e");
      }
    }
  }

  void _showContactAccessDeniedDialog() {
    showCupertinoDialog(
      context: context,
      builder:
          (context) => CupertinoAlertDialog(
            title: const Text('Contact Access Required'),
            content: const Text(
              'Assiist needs access to your contacts for bi-directional sync. Please enable contact access in Settings.',
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('Cancel'),
                onPressed: () => Navigator.pop(context),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                child: const Text('Open Settings'),
                onPressed: () async {
                  Navigator.pop(context);
                  await NativeContactAccessService.openContactSettings();
                },
              ),
            ],
          ),
    );
  }

  Widget _buildStep2PreviewUI(BuildContext context) {
    if (_isPreviewLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CupertinoActivityIndicator(radius: 16),
              SizedBox(height: 16),
              Text(
                "Loading sync preview...",
                style: AppStyles.inputTextStyle(context),
              ),
            ],
          ),
        ),
      );
    }

    if (_previewError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.exclamationmark_triangle,
                color: CupertinoColors.systemRed,
                size: 48,
              ),
              SizedBox(height: 16),
              Text("Error", style: AppStyles.h1TextStyle(context)),
              SizedBox(height: 8),
              Text(
                _previewError!,
                style: AppStyles.inputTextStyle(context),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20),
              CupertinoButton.filled(
                child: Text("Retry"),
                onPressed: _loadPreviewData,
              ),
            ],
          ),
        ),
      );
    }

    if (_syncPreviewData != null) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("SYNC PREVIEW", style: AppStyles.labelTextStyle(context)),
            SizedBox(height: 16),
            _buildPreviewRow(
              context,
              "New contacts to add to Assiist:",
              _syncPreviewData!.toCreateOnServer,
            ),
            _buildPreviewRow(
              context,
              "New contacts to add to iPhone:",
              _syncPreviewData!.toCreateOnNative,
            ),
            _buildPreviewRow(
              context,
              "Contacts to check for updates:",
              _syncPreviewData!.toCompareOrUpdate,
            ),
            SizedBox(height: 24),
            Center(
              child: Text(
                "Ready to synchronize your contacts?",
                style: AppStyles.inputTextStyle(context),
              ),
            ),
            // Spacer(), // Use if you want to push button to bottom
          ],
        ),
      );
    }
    // Should not happen if logic is correct, but as a fallback:
    return Center(child: Text("Step 2: Sync Preview"));
  }

  Widget _buildPreviewRow(BuildContext context, String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppStyles.inputTextStyle(context)),
          Text(
            count.toString(),
            style: AppStyles.inputTextStyle(
              context,
            ).copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3ProgressUI(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CupertinoActivityIndicator(radius: 16),
            SizedBox(height: 16),
            Text(
              "Syncing all contacts...",
              style: AppStyles.inputTextStyle(context),
            ),
            SizedBox(height: 8),
            Text(
              "This may take a few moments depending on the number of contacts.",
              style: AppStyles.captionTextStyle(context),
              textAlign: TextAlign.center,
            ),
            if (_syncPreviewData != null) ...[
              SizedBox(height: 16),
              Text(
                "Processing ${_syncPreviewData!.toCreateOnServer + _syncPreviewData!.toCreateOnNative + _syncPreviewData!.toCompareOrUpdate} contacts",
                style: AppStyles.captionTextStyle(context),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStep4CompletionUI(BuildContext context) {
    if (_syncError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.xmark_circle_fill,
                color: CupertinoColors.systemRed,
                size: 48,
              ),
              SizedBox(height: 16),
              Text("Sync Failed", style: AppStyles.h1TextStyle(context)),
              SizedBox(height: 12),
              Text(
                _syncError!,
                style: AppStyles.bodyTextStyle(context),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_syncSuccess) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppStyles.accentIcon(
                    icon: CupertinoIcons.check_mark_circled_solid,
                    size: 48,
                  ),
                  SizedBox(width: 12),
                  Text("Sync Complete!", style: AppStyles.h1TextStyle(context)),
                ],
              ),
              SizedBox(height: 18),
              Text(
                "All your contacts have been automatically synchronized between your device and Assiist.",
                style: AppStyles.bodyTextStyle(context),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 28),
              if (_syncPreviewData != null) ...[
                Text(
                  "Summary:",
                  style: AppStyles.labelTextStyle(
                    context,
                  ).copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                _buildPreviewRow(
                  context,
                  "Added to Assiist:",
                  _syncPreviewData!.toCreateOnServer,
                ),
                _buildPreviewRow(
                  context,
                  "Added to iPhone:",
                  _syncPreviewData!.toCreateOnNative,
                ),
                _buildPreviewRow(
                  context,
                  "Checked for updates:",
                  _syncPreviewData!.toCompareOrUpdate,
                ),
              ],
            ],
          ),
        ),
      );
    }
    // Fallback, should ideally not be reached if _syncError or _syncSuccess is always set
    return Center(child: Text("Step 4: Completion"));
  }

  @override
  Widget build(BuildContext context) {
    Widget currentStepWidget;
    String navBarTitle = 'Configure Contact Sync'; // Default
    Widget? trailingButton;

    switch (_currentStep) {
      case 1:
        currentStepWidget = _buildStep1SelectionUI(context);
        navBarTitle = 'Select Sync Source';
        trailingButton = CupertinoButton(
          padding: EdgeInsets.zero,
          child:
              _isProcessing
                  ? CupertinoActivityIndicator(
                    color:
                        AppStyles.useGradientAccent
                            ? AppStyles.solidAccent
                            : AppStyles.accentTextColor(context),
                  )
                  : (_selectedUITarget == _uiTargetIPhone)
                  ? AppStyles.accentText(context, 'Next')
                  : Text(
                    'Next',
                    style: TextStyle(color: CupertinoColors.inactiveGray),
                  ),
          onPressed:
              (_selectedUITarget == _uiTargetIPhone && !_isProcessing)
                  ? () async {
                    if (!mounted) return; // Guard at the beginning
                    setState(() => _isProcessing = true);
                    try {
                      bool configSuccess = await _processAndSaveConfiguration();
                      if (configSuccess && mounted) {
                        // _handlePermissionRequestAndProceed will navigate or show its own dialogs.
                        // It should not be responsible for resetting _isProcessing here;
                        // the finally block of this onPressed handler will do that.
                        await _handlePermissionRequestAndProceed();
                      }
                      // If configSuccess is false, an error dialog was shown by _processAndSaveConfiguration.
                      // The finally block below will reset _isProcessing.
                    } catch (e) {
                      print("Error in Step 1 Next button onPressed: $e");
                      if (mounted) {
                        _showErrorDialog(
                          "An unexpected error occurred while proceeding: $e",
                        );
                      }
                    } finally {
                      // Crucially, always reset _isProcessing if this widget is still mounted.
                      if (mounted) {
                        setState(() => _isProcessing = false);
                      }
                    }
                  }
                  : null,
        );
        break;
      case 2:
        currentStepWidget = _buildStep2PreviewUI(context);
        navBarTitle = 'Sync Preview';
        trailingButton = CupertinoButton(
          padding: EdgeInsets.zero,
          child:
              (_syncPreviewData != null && !_isPreviewLoading)
                  ? AppStyles.accentText(context, "Start Sync")
                  : Text(
                    "Start Sync",
                    style: TextStyle(color: CupertinoColors.inactiveGray),
                  ),
          onPressed:
              (_syncPreviewData != null && !_isPreviewLoading)
                  ? _performSync
                  : null,
        );
        break;
      case 3:
        currentStepWidget = _buildStep3ProgressUI(context);
        navBarTitle = 'Syncing Contacts';
        // No trailing button during sync, or a "Cancel Sync" if implemented
        trailingButton = null; // Explicitly null
        break;
      case 4:
        currentStepWidget = _buildStep4CompletionUI(context);
        navBarTitle = _syncError == null ? 'Sync Complete' : 'Sync Failed';
        trailingButton = CupertinoButton(
          padding: EdgeInsets.zero,
          child: AppStyles.accentText(context, "Done"),
          onPressed:
              () => Navigator.pop(context, {
                'source': _selectedUITarget == _uiTargetIPhone ? 'ios' : null,
                'priority': widget.initialPriority ?? 'local_wins',
                'syncStatus':
                    _syncSuccess
                        ? 'completed'
                        : (_syncError != null ? 'failed' : 'unknown'),
              }),
        );
        break;
      default:
        currentStepWidget = Center(child: Text('Unknown Step'));
    }

    return CupertinoPageScaffold(
      backgroundColor: AppStyles.subtleBackgroundColor(context),
      navigationBar: CupertinoNavigationBar(
        middle: Text(navBarTitle),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          child: AppStyles.accentText(
            context,
            _currentStep == 1 ? 'Cancel' : 'Back',
          ),
          onPressed:
              _isProcessing || _isSyncing
                  ? null
                  : () {
                    print(
                      "[ContactSyncWizard] Back/Cancel pressed from step $_currentStep",
                    );

                    // Disable back/cancel if processing permission from step 1 or syncing
                    if (_currentStep == 1) {
                      // Cancel from Step 1 - exit wizard
                      Navigator.pop(context);
                    } else if (_currentStep == 2) {
                      // Back from Step 2 - return to Step 1 and clear preview data
                      setState(() {
                        _currentStep = 1;
                        // Clear preview data when going back
                        _syncPreviewData = null;
                        _previewError = null;
                        _isPreviewLoading = false;
                      });
                    } else if (_currentStep == 3) {
                      // Can't go back during sync - exit wizard
                      Navigator.pop(context);
                    } else if (_currentStep == 4) {
                      // Back from completion - restart wizard
                      setState(() {
                        _currentStep = 1;
                        // Reset all state
                        _syncPreviewData = null;
                        _previewError = null;
                        _isPreviewLoading = false;
                        _syncError = null;
                        _syncSuccess = false;
                        _isSyncing = false;
                      });
                    }
                  },
        ),
        trailing: trailingButton,
      ),
      child: SafeArea(
        // Using a Column directly for step content if it doesn't need to scroll.
        // If individual steps might scroll, they should manage their own ListView.
        // Forcing ListView here might cause issues with intrinsically sized Columns from _buildStep1SelectionUI.
        // Let _buildStep1SelectionUI manage its own layout.
        // If other steps become complex, they can use ListView.
        // For now, direct child to allow flexible step UI.
        child: currentStepWidget,
      ),
    );
  }
}
