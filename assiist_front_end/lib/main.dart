import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // ADD Material import for Theme
import 'package:firebase_core/firebase_core.dart'; // Added
import 'services/notification_service.dart'; // Added - Adjust path if needed
import 'firebase_options.dart'; // Added - Ensure this file exists (run flutterfire configure)
import 'screens/dashboard_screen.dart'; // Keep existing import
// Import Global Material Localizations
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Import Riverpod
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_native_timezone/flutter_native_timezone.dart'; // For timezone detection
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io' show Platform;
import 'providers/auth_providers.dart'; // Add this import
import 'package:flutter_dotenv/flutter_dotenv.dart'; // ADDED: flutter_dotenv import
import 'package:cloud_firestore/cloud_firestore.dart';
import 'utils/navigation_service.dart';
import 'package:assiist_front_end/providers/theme_provider.dart';
import 'package:assiist_front_end/theme/app_theme.dart';

// Import screens
import 'screens/login_screen.dart'; // Assuming you have a LoginScreen
// import 'theme/app_theme.dart'; // REMOVE unused import

// Global instance for notifications plugin (or manage via DI/Provider)
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Import your AuthWrapper or initial routing logic here if needed
// import 'path/to/auth_wrapper.dart';

// Placeholder values - REMOVE once state management provides real values
const String placeholderAccessToken = 'dummy-token-12345';
const String placeholderLocationId = 'loc-abc-9876';

Future<void> main() async {
  // Make main async
  // Ensure Flutter bindings are initialized before using plugins
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env.development
  try {
    await dotenv.load(fileName: ".env.development");
    print(".env.development loaded successfully.");
    // You can optionally print loaded values for debugging, but remove for production
    // print("API_URL from .env: ${dotenv.env['API_URL']}");
    // print("GOOGLE_CLIENT_ID from .env: ${dotenv.env['GOOGLE_CLIENT_ID']}");
  } catch (e) {
    print("Error loading .env.development file: $e");
    // Handle error, maybe fall back to defaults or show an error UI if critical configs are missing
  }

  // Initialize Firebase using the generated options file
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Request notification permissions for iOS
  if (Platform.isIOS) {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
  }

  // Initialize Notification Service (includes FCM setup etc.)
  await NotificationService().initialize();

  // Initialize timezone database
  tz.initializeTimeZones();
  // Get the local timezone
  try {
    final String localTimezone = await FlutterNativeTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTimezone));
  } catch (e) {
    print("Could not get local timezone: $e");
    // Fallback or handle error as needed
  }

  // Configure local notifications
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      ); // Use default app icon
  final DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    // Handle notification tapped when the app is not in the foreground
    onDidReceiveNotificationResponse: (
      NotificationResponse notificationResponse,
    ) async {
      final String? payload = notificationResponse.payload;
      if (payload != null) {
        print('notification payload: $payload');
        // TODO: Implement navigation based on payload
        // e.g., if payload is a contact ID, navigate to ContactRecordScreen
      }
      // selectNotificationSubject.add(payload);
    },
  );

  // Request permissions for iOS (older versions might need this)
  // Permissions are requested in the DarwinInitializationSettings for newer iOS

  // Run the app, wrapped in ProviderScope
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initialize token refresh
    ref.watch(tokenRefreshProvider);

    final appThemeMode = ref.watch(themeModeProvider);
    final cupertinoTheme = switch (appThemeMode) {
      AppThemeMode.light => AppTheme.lightCupertino,
      AppThemeMode.dark => AppTheme.darkCupertino,
      AppThemeMode.system =>
        // Determine based on platform brightness at build time
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark
            ? AppTheme.darkCupertino
            : AppTheme.lightCupertino,
    };

    return CupertinoApp(
      title: 'Assiist',
      theme: cupertinoTheme,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', '')],
      navigatorKey: NavigationService.navigatorKey,
      home: const LoginScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const DashboardScreen(),
      },
    );
  }
}
