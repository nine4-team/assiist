// lib/services/notification_service.dart
import 'dart:io' show Platform; // For checking OS
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart'; // Needed if using initializeApp in handler
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:assiist_front_end/screens/message_draft_screen.dart'; // Absolute imports
import 'package:assiist_front_end/screens/task_screen.dart';
import 'package:assiist_front_end/core/models/task.dart';
import 'package:assiist_front_end/providers/auth_providers.dart'; // for currentAccountIdProvider
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:assiist_front_end/utils/navigation_service.dart';
import 'package:assiist_front_end/services/contact_sync_locator.dart'; // Added import

// --- FCM Background Handler ---
@pragma('vm:entry-point') // Mandatory for background execution
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If using other Firebase services in the handler, initialize Firebase:
  // await Firebase.initializeApp(); // Consider if necessary
  print("Handling background FCM message: ${message.messageId}");
  print("Data: ${message.data}");

  final String? notificationType = message.data['type'];

  if (notificationType == 'contacts_changed') {
    // Trigger lean incremental sync
    await ContactSyncServiceLocator.instance.syncService
        .performIncrementalSync();
    return;
  }

  if (notificationType?.startsWith('task_') == true) {
    // Handle task notifications
    final String? taskId = message.data['task_id'];
    final String? taskType = message.data['task_type'];
    final String? contactId = message.data['contact_id'];

    // Use notification title and body from FCM message
    final String title = message.notification?.title ?? 'New Task';
    final String body = message.notification?.body ?? '';

    if (taskId != null) {
      await NotificationService().showNotification(
        id: taskId.hashCode & 0x7FFFFFFF,
        title: title,
        body: body,
        payload: 'task_id=$taskId&task_type=$taskType&contact_id=$contactId',
      );
    }
  } else {
    // Legacy event notification handling
    final String? eventTitle = message.data['eventTitle'];
    final String? eventBody = message.data['eventBody'];
    final String? eventId = message.data['eventId'];

    if (eventTitle != null && eventBody != null && eventId != null) {
      // Immediately display the notification using the singleton instance
      await NotificationService().showNotification(
        id: eventId.hashCode & 0x7FFFFFFF, // Consistent ID generation
        title: eventTitle,
        body: eventBody,
        payload: 'event_id=$eventId',
      );
    }
  }
}
// --- End FCM Background Handler ---

class NotificationService {
  // Singleton pattern
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'assiist-app',
  );
  final fb_auth.FirebaseAuth _auth = fb_auth.FirebaseAuth.instance;
  bool _isInitialized = false;
  String? _fcmToken; // Cache the token

  Future<void> initialize() async {
    if (_isInitialized) return;

    // 1. Initialize Timezone Data
    await _configureLocalTimeZone();

    // 2. Initialize Local Notifications Plugin
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings(
          '@mipmap/ic_launcher',
        ); // Use your app icon name
    final DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission:
              true, // Request permissions during init on iOS
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );
    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );

    // 3. Request FCM Permissions (especially needed on iOS & newer Android)
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // 4. Listen for token refreshes – we'll register after auth
    _firebaseMessaging.onTokenRefresh.listen(
      (token) => _getAndSaveFCMToken(token: token),
    );

    // 5. Set up FCM Message Handlers
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 6. Handle notification tap from terminated state
    final RemoteMessage? initialMessage =
        await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) _handleMessageTap(initialMessage);
    // Handle notification tap from background state
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    _isInitialized = true;
    print("Notification Service Initialized.");
  }

  Future<void> _configureLocalTimeZone() async {
    tz_data.initializeTimeZones();
    final String timeZoneName = await FlutterNativeTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));
  }

  // --- FCM Token Management ---
  Future<void> _getAndSaveFCMToken({String? token}) async {
    final user = _auth.currentUser;
    if (user == null) return; // Only save if user is logged in

    // --- NEW: Wait for APNS token on Apple platforms first ---
    if (Platform.isIOS || Platform.isMacOS) {
      print("Requesting APNS token before FCM token...");
      try {
        final apnsToken = await _firebaseMessaging.getAPNSToken();
        if (apnsToken == null) {
          print("APNS token not available yet. FCM token retrieval may fail.");
          // Optionally wait/retry, or just proceed and let getToken handle it
        } else {
          print("APNS token received.");
        }
      } catch (e) {
        print(
          "Error getting APNS token: $e. Proceeding to get FCM token anyway.",
        );
        // Proceed even if APNS token fetch fails, getToken might still work or fail later
      }
    }
    // --- END NEW ---

    // Now attempt to get the FCM token
    try {
      _fcmToken = token ?? await _firebaseMessaging.getToken();
      if (_fcmToken == null) {
        print("Failed to get FCM token.");
        return;
      }
      print("Got FCM Token: $_fcmToken");
    } catch (e) {
      // Catch potential errors during getToken itself (like the original apns-token-not-set error)
      print("Error getting FCM token: $e");
      // If the error is specifically apns-token-not-set, maybe schedule a retry?
      // For now, just return to prevent crashing.
      return;
    }

    // Save token to Firestore associated with the user
    final tokensRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('device_tokens')
        .doc(_fcmToken); // Use token as doc ID
    try {
      await tokensRef.set({
        'token': _fcmToken,
        'created_on':
            FieldValue.serverTimestamp(), // ← FIXED: Use snake_case with *_on suffix
        'platform': Platform.operatingSystem,
      }, SetOptions(merge: true));
      print("FCM Token saved to Firestore.");
    } catch (e) {
      print("Error saving FCM token to Firestore: $e");
    }
  }

  // NEW: Public method to register the current device's FCM token once a user is authenticated.
  // This can be safely called multiple times; if a token has already been saved it will simply
  // overwrite the existing document. It also includes simple retry logic for iOS cases where
  // getToken() initially returns null because the APNS token is not yet available.
  Future<void> registerDeviceToken({
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    int attempt = 0;
    while (attempt < maxRetries) {
      await _getAndSaveFCMToken();
      // If we managed to cache a non-null token, we are done.
      if (_fcmToken != null) {
        return;
      }
      attempt += 1;
      if (attempt < maxRetries) {
        print(
          "FCM token was null – retrying in ${retryDelay.inSeconds}s (attempt $attempt/$maxRetries)",
        );
        await Future.delayed(retryDelay);
      }
    }
    print("⚠️  Failed to register FCM token after $maxRetries attempts");
  }

  // Call this on user logout
  Future<void> deleteFCMToken() async {
    final user = _auth.currentUser; // Get user *before* sign out if possible
    if (user != null && _fcmToken != null) {
      print("Deleting FCM token: $_fcmToken for user ${user.uid}");
      try {
        final tokenRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('device_tokens')
            .doc(_fcmToken);
        await tokenRef.delete();
      } catch (e) {
        print("Error deleting FCM token from Firestore: $e");
      }
    }
    // Also invalidate the token locally
    try {
      await _firebaseMessaging.deleteToken();
      _fcmToken = null;
    } catch (e) {
      print("Error deleting FCM token instance: $e");
    }
  }

  // --- Message Handlers ---
  void _handleForegroundMessage(RemoteMessage message) async {
    if (message.data['type'] == 'contacts_changed') {
      await ContactSyncServiceLocator.instance.syncService
          .performIncrementalSync();
      return;
    }
    print('Foreground FCM received: ${message.data}');

    // Handle different notification types
    final String? notificationType = message.data['type'];

    if (notificationType?.startsWith('task_') == true) {
      _handleTaskNotification(message);
    } else {
      // Legacy event notification handling
      _handleEventNotification(message);
    }
  }

  void _handleTaskNotification(RemoteMessage message) {
    final String? taskType = message.data['task_type'];
    final String? taskId = message.data['task_id'];
    final String? contactId = message.data['contact_id'];

    // Use notification title and body from FCM message
    final String title = message.notification?.title ?? 'New Task';
    final String body = message.notification?.body ?? '';

    if (taskId != null) {
      showNotification(
        id: taskId.hashCode & 0x7FFFFFFF,
        title: title,
        body: body,
        payload: 'task_id=$taskId&task_type=$taskType&contact_id=$contactId',
      );
    }
  }

  void _handleEventNotification(RemoteMessage message) {
    final String? eventTitle = message.data['eventTitle'];
    final String? eventBody = message.data['eventBody'];
    final String? eventId = message.data['eventId'];

    // Show the notification immediately using local notifications plugin
    if (eventTitle != null && eventBody != null && eventId != null) {
      showNotification(
        id: eventId.hashCode & 0x7FFFFFFF,
        title: eventTitle,
        body: eventBody,
        payload: 'event_id=$eventId',
      );
    }
  }

  void _handleMessageTap(RemoteMessage message) {
    // Prefer deep link if provided
    final String? deepLink = message.data['link'];
    if (deepLink != null && deepLink.startsWith('assiist://')) {
      _handleDeepLink(deepLink);
      return;
    }

    final String? notificationType = message.data['type'];

    if (notificationType?.startsWith('task_') == true) {
      final String? taskId = message.data['task_id'];
      final String? taskType = message.data['task_type'];
      final String? contactId = message.data['contact_id'];
      final String? accountId = message.data['account_id'];

      // Account guard – ignore if it doesn’t match active account
      final currentAccountId = _getCurrentAccountId();
      if (accountId != null &&
          currentAccountId != null &&
          accountId != currentAccountId) {
        print("🔒 Notification account mismatch – ignoring tap.");
        return;
      }

      if (taskId != null) {
        _processPayload(
          'task_id=$taskId&task_type=$taskType&contact_id=$contactId',
        );
      }
    } else {
      // Legacy event notification handling
      final String? eventId = message.data['eventId'];
      if (eventId != null) {
        _processPayload('event_id=$eventId');
      } else {
        print(
          "Message tap detected, but no eventId found in data: ${message.data}",
        );
      }
    }
  }

  // Deep link handler (assiist://task?...)
  void _handleDeepLink(String uriString) {
    try {
      final uri = Uri.parse(uriString);
      if (uri.host != 'task') {
        print('Unknown deep link: $uriString');
        return;
      }

      final taskId = uri.queryParameters['task_id'];
      final contactId = uri.queryParameters['contact_id'];
      final taskType = uri.queryParameters['task_type'];
      final accountId = uri.queryParameters['account_id'];

      // Account guard
      final currentAccountId = _getCurrentAccountId();
      if (accountId != null &&
          currentAccountId != null &&
          accountId != currentAccountId) {
        print('🔒 Deep link account mismatch – ignoring');
        return;
      }

      if (taskId == null) {
        print('Deep link missing task_id');
        return;
      }

      _processTaskPayload(
        'task_id=$taskId&task_type=$taskType&contact_id=$contactId',
      );
    } catch (e) {
      print('Invalid deep link: $uriString – $e');
    }
  }

  String? _getCurrentAccountId() {
    // We need a Riverpod container; use the root ProviderScope if available.
    try {
      final rootContext = _getNavigationContext();
      final container = ProviderScope.containerOf(rootContext);
      return container.read(currentAccountIdProvider);
    } catch (_) {
      return null;
    }
  }

  // --- Local Notification Callbacks ---
  void onDidReceiveNotificationResponse(NotificationResponse response) {
    _processPayload(response.payload);
  }

  // --- Central Payload Processing ---
  void _processPayload(String? payload) {
    print("Processing notification tap payload: $payload");

    if (payload == null) return;

    if (payload.startsWith('task_id=')) {
      _processTaskPayload(payload);
    } else if (payload.startsWith('event_id=')) {
      _processEventPayload(payload);
    }
  }

  void _processTaskPayload(String payload) async {
    // Parse task payload: task_id=123&task_type=message&contact_id=456
    final params = <String, String>{};
    for (final param in payload.split('&')) {
      final parts = param.split('=');
      if (parts.length == 2) {
        params[parts[0]] = parts[1];
      }
    }

    final taskId = params['task_id'];
    final taskType = params['task_type'];
    final contactId = params['contact_id'];

    print("Navigate to task: $taskId, type: $taskType, contact: $contactId");

    if (taskId == null) {
      print("No task ID found in notification payload");
      _navigateToDashboard();
      return;
    }

    // Build a minimal Task object; detailed data will be fetched by the
    // destination screen’s providers.
    final placeholderTask = Task(
      id: taskId,
      title: '',
      type: taskType ?? 'action',
      status: 'pending',
      userId: '',
      createdBy: '',
      createdOn: DateTime.now(),
      contactId: contactId,
      accountId: null,
      body: null,
    );

    final resolvedType =
        (taskType != null && taskType.isNotEmpty)
            ? taskType
            : placeholderTask.type;

    try {
      if (resolvedType == 'message') {
        Navigator.of(_getNavigationContext()).push(
          MaterialPageRoute(
            builder: (context) => MessageDraftScreen(task: placeholderTask),
          ),
        );
      } else {
        Navigator.of(_getNavigationContext()).push(
          MaterialPageRoute(
            builder: (context) => TaskScreen(task: placeholderTask),
          ),
        );
      }
    } catch (e) {
      print("Navigation failed: $e");
      _navigateToDashboard();
    }
  }

  // Obsoleted Firestore fetch – retained blank to prevent compile errors.
  // Future<Task?> _fetchTaskFromFirestore(String taskId, String? contactId) async => null;

  void _navigateToDashboard() {
    Navigator.of(
      _getNavigationContext(),
    ).pushNamedAndRemoveUntil('/dashboard', (route) => false);
  }

  void _processEventPayload(String payload) {
    final eventId = payload.split('=')[1];
    print("Navigate to details for event: $eventId");

    // Navigate to dashboard for event notifications
    Navigator.of(
      _getNavigationContext(),
    ).pushNamedAndRemoveUntil('/dashboard', (route) => false);
  }

  // Helper method to get navigation context
  BuildContext _getNavigationContext() {
    // Prefer the global navigator key's context
    if (NavigationService.navigatorKey.currentContext != null) {
      return NavigationService.navigatorKey.currentContext!;
    }

    // Fallback to rootElement (should rarely be needed)
    final context = WidgetsBinding.instance.rootElement;
    if (context == null) {
      throw Exception('No navigation context available');
    }
    return context;
  }

  // --- Public method to display a notification ---
  Future<void> showNotification({
    required int id,
    String? title,
    String? body,
    String? payload,
  }) async {
    // Ensure initialization (might be needed if called from background isolate context)
    // if (!_isInitialized) {
    //    print("Notification Service not initialized, attempting init...");
    //    await initialize(); // Be cautious with calling this from background isolate directly
    // }

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: AndroidNotificationDetails(
        'event_reminders_channel_id', // Channel ID
        'Event Reminders', // Channel Name
        channelDescription: 'Channel for calendar event reminders',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
      ),
      iOS: DarwinNotificationDetails(
        presentSound: true,
        presentBadge: true,
        presentAlert: true,
      ),
    );
    await _notificationsPlugin.show(
      id,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
    print("Displayed notification: ID=$id, Title=$title");
  }
}
