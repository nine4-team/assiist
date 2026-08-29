import 'package:flutter/foundation.dart';
import 'package:background_fetch/background_fetch.dart';

import 'package:assiist_front_end/services/contact_sync_locator.dart';

/// Registers a true background task using the `background_fetch` plugin.  This
/// plugin maps to BGTaskScheduler on iOS (minimum interval ~15 min) and Job
/// Scheduler / AlarmManager on Android.
class BackgroundSyncService {
  static final BackgroundSyncService _instance = BackgroundSyncService._();
  BackgroundSyncService._();
  factory BackgroundSyncService() => _instance;

  bool _configured = false;

  /// Call once, ideally during app start, to configure background fetch.
  Future<void> initialize({int fetchIntervalMinutes = 30}) async {
    if (_configured) return;

    // iOS requires explicit Xcode capabilities (Background fetch + Processing)
    // and registration of permitted identifiers in Info.plist, which the
    // implementation guide already lists.

    final status = await BackgroundFetch.configure(
      BackgroundFetchConfig(
        minimumFetchInterval: fetchIntervalMinutes,
        stopOnTerminate: false,
        enableHeadless: true,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresStorageNotLow: false,
        requiresDeviceIdle: false,
      ),
      _onBackgroundFetch,
      _onBackgroundFetchTimeout,
    );

    debugPrint('[BackgroundSync] BackgroundFetch configured (status: $status)');

    // For Android headless execution
    BackgroundFetch.registerHeadlessTask(_backgroundFetchHeadlessTask);

    _configured = true;
  }

  // Called when a background-fetch event fires (app in foreground or background).
  Future<void> _onBackgroundFetch(String taskId) async {
    debugPrint('[BackgroundSync] Event → $taskId');
    await ContactSyncServiceLocator.instance.syncService
        .performIncrementalSync();
    BackgroundFetch.finish(taskId);
  }

  // Called when the OS terminates the background task early.
  void _onBackgroundFetchTimeout(String taskId) {
    debugPrint('[BackgroundSync] TIMEOUT → $taskId');
    BackgroundFetch.finish(taskId);
  }

  // Headless task entry-point (Android)
  static Future<void> _backgroundFetchHeadlessTask(String taskId) async {
    debugPrint('[BackgroundSync] Headless event → $taskId');
    await ContactSyncServiceLocator.instance.syncService
        .performIncrementalSync();
    BackgroundFetch.finish(taskId);
  }
}
