import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:assiist_front_end/core/models/user_profile.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:assiist_front_end/services/auth_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:assiist_front_end/services/notification_service.dart';

/// Provides the session's access token.
/// Initial value is null, should be updated after login.
final accessTokenProvider = StateProvider<String?>((ref) => null);

/// Provides the currently active location ID for the user.
/// Initial value is null, should be updated after login or selection.
final locationIdProvider = StateProvider<String?>((ref) => null);

/// Provides the base URL for the backend API.
/// Loads the URL from the .env.development file via flutter_dotenv.
final baseUrlProvider = Provider<String>((ref) {
  // Read from .env.development file loaded by flutter_dotenv
  final String? apiUrl = dotenv.env['API_URL'];

  if (apiUrl == null || apiUrl.isEmpty) {
    throw Exception(
      "API_URL not found in .env.development file. Please ensure the file exists and contains API_URL.",
    );
  }

  print('Using API_URL from .env: $apiUrl');

  return apiUrl;
});

/// Provides the profile information for the currently logged-in user.
/// Initial value is null, should be updated after login.
final userProfileProvider = StateProvider<UserProfile?>((ref) => null);

// You can add more providers here later, e.g.:
// final isAuthenticatedProvider = Provider<bool>((ref) {
//   final token = ref.watch(accessTokenProvider);
//   return token != null && token.isNotEmpty;
// });

/// Provider for the FirebaseAuth instance
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

/// Provider that automatically refreshes the token when needed
final tokenRefreshProvider = Provider<void>((ref) {
  final auth = ref.watch(firebaseAuthProvider);

  // Listen to auth state changes
  auth.authStateChanges().listen((User? user) async {
    if (user != null) {
      // Get the token and force refresh if needed
      try {
        final token = await user.getIdToken(true); // true forces refresh
        ref.read(accessTokenProvider.notifier).state = token;

        // NEW: Ensure the device's FCM token is registered for the logged-in user
        await NotificationService().registerDeviceToken();
      } catch (e) {
        print('Error refreshing token: $e');
      }
    } else {
      // User is signed out
      ref.read(accessTokenProvider.notifier).state = null;

      // Clean up any stored FCM token for this device
      try {
        await NotificationService().deleteFCMToken();
      } catch (e) {
        print('Error deleting FCM token on sign-out: $e');
      }
    }
  });
});

// Provider to expose the auth state changes stream
final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

// Provider to get the current Firebase UID or null (for auth operations)
final userIdProvider = Provider<String?>((ref) {
  // Watch the auth state changes
  final authState = ref.watch(authStateChangesProvider);
  // Return the Firebase UID if the user is logged in, otherwise null
  return authState.value?.uid;
});

// Provider to get the current backend user ID or null (for business logic)
final backendUserIdProvider = Provider<String?>((ref) {
  // Watch the user profile
  final userProfile = ref.watch(userProfileProvider);
  // Return the backend user ID if profile is loaded, otherwise null
  return userProfile?.id;
});

// ADDED: Provider for AuthService
final authServiceProvider = Provider<AuthService>((ref) {
  print('DEBUG: Creating AuthService instance...');
  try {
    final authService = AuthService();
    print('DEBUG: AuthService created successfully');
    return authService;
  } catch (e) {
    print('DEBUG: Error creating AuthService: $e');
    rethrow;
  }
});

// Provider for the current account ID
final currentAccountIdProvider = StateProvider<String?>((ref) => null);
