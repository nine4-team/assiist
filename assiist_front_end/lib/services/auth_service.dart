// lib/services/auth_service.dart
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// Import MSAL/AAD package if implementing Outlook link

class AuthService {
  final _googleSignIn = GoogleSignIn(
    // Ensure this matches the Web Client ID from Google Cloud Console if needed for backend code exchange
    // serverClientId: 'YOUR_GOOGLE_WEB_CLIENT_ID_FOR_SERVER_CODE',
    scopes: ['email'], // Minimal scope for sign-in
  );
  final _firebaseAuth = fb_auth.FirebaseAuth.instance;
  // Add MSAL config/instance if needed

  // *** Backend URL from .env.development file ***
  String get _backendBaseUrl {
    final String? apiUrl = dotenv.env['API_URL'];
    if (apiUrl == null || apiUrl.isEmpty) {
      throw Exception(
        "API_URL not found in .env.development file. Please ensure the file exists and contains API_URL.",
      );
    }
    // Remove '/api/v1' suffix if present since we just need the base URL
    return apiUrl.replaceAll('/api/v1', '');
  }

  // *** Ensure this endpoint exists on your Python backend ***
  String get _backendLinkProviderEndpoint =>
      "$_backendBaseUrl/auth/link-provider";

  fb_auth.User? get currentUser => _firebaseAuth.currentUser;
  Stream<fb_auth.User?> get authStateChanges =>
      _firebaseAuth.authStateChanges();

  Future<bool> signInWithGoogleAndLinkBackend() async {
    if (_firebaseAuth.currentUser != null) {
      print(
        "User already signed in. Assuming already linked or will check status.",
      );
      // Optional: Add logic to check link status with backend if needed on re-launch
      return true;
    }
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return false; // Cancelled
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String? googleIdToken = googleAuth.idToken;
      if (googleIdToken == null) throw Exception("Google ID Token was null.");

      final fb_auth.AuthCredential credential = fb_auth
          .GoogleAuthProvider.credential(idToken: googleIdToken);
      final fb_auth.UserCredential userCredential = await _firebaseAuth
          .signInWithCredential(credential);
      final fb_auth.User? firebaseUser = userCredential.user;
      if (firebaseUser == null)
        throw Exception("Firebase user was null after credential sign-in.");

      // Now, notify *your* backend, authenticating with the Firebase ID token
      bool linkSuccess = await _notifyBackendLink(
        provider: 'google',
        providerToken: googleIdToken,
      );
      if (!linkSuccess) {
        // Decide how to handle backend link failure (e.g., sign out, show error)
        await signOut(); // Example: sign out if link fails
        return false;
      }
      return true;
    } catch (error) {
      print("signInWithGoogleAndLinkBackend Error: $error");
      await signOut(); // Clean up on error
      return false;
    }
  }

  // TODO: Implement signInWithOutlookAndLinkBackend similarly if needed

  /// Notifies the backend to link the provider, authenticating via Firebase ID token.
  Future<bool> _notifyBackendLink({
    required String provider,
    String? providerToken,
    String? providerCode,
  }) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return false;
    String? firebaseIdToken = await user.getIdToken(
      true,
    ); // MODIFIED: Force refresh for this critical call
    if (firebaseIdToken == null) {
      print(
        "Failed to get/refresh Firebase ID token for backend link notification.",
      ); // ADDED log
      return false;
    }

    print("Notifying backend to link $provider provider.");
    try {
      final response = await http.post(
        Uri.parse(_backendLinkProviderEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Bearer $firebaseIdToken', // Authenticate this request
        },
        body: json.encode({
          'provider': provider,
          'id_token': providerToken, // The token *from Google/Outlook*
          'auth_code': providerCode, // Or the auth code *from Google/Outlook*
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        print("Backend successfully linked $provider.");
        return true;
      } else {
        print(
          "Backend link notification failed: ${response.statusCode} ${response.body}",
        );
        return false;
      }
    } catch (e) {
      print("Exception notifying backend of link: $e");
      return false;
    }
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    // Best effort to sign out from providers too
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    // try { await _msal.logout(); } catch (_) {} // If using MSAL
    print("Signed Out.");
  }

  Future<GoogleSignInAccount?> promptGoogleAccountPicker() async {
    try {
      // First, sign out from Google Sign-In
      await _googleSignIn.signOut();

      // Then sign out from Firebase
      await _firebaseAuth.signOut();

      // Add a longer delay to ensure session is cleared
      await Future.delayed(Duration(seconds: 1));

      // Attempt to sign in with Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        print("Google Sign-In was cancelled by user");
        return null;
      }

      // Verify the sign-in was successful
      try {
        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        if (googleAuth.idToken == null) {
          print("Failed to get Google ID token");
          return null;
        }
        return googleUser;
      } catch (e) {
        print("Error during Google authentication: $e");
        return null;
      }
    } catch (e) {
      print("Error in promptGoogleAccountPicker: $e");
      // If we encounter an error, try to clean up
      try {
        await _googleSignIn.signOut();
        await _firebaseAuth.signOut();
      } catch (_) {}
      return null;
    }
  }

  Future<bool> signInToFirebaseWithGoogleAccount(
    GoogleSignInAccount googleUser,
  ) async {
    try {
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String? googleIdToken = googleAuth.idToken;
      if (googleIdToken == null) {
        print("Google ID Token was null");
        return false;
      }

      final fb_auth.AuthCredential credential = fb_auth
          .GoogleAuthProvider.credential(
        idToken: googleIdToken,
        accessToken: googleAuth.accessToken,
      );

      final fb_auth.UserCredential userCredential = await _firebaseAuth
          .signInWithCredential(credential);
      final fb_auth.User? firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        print("Firebase user was null after credential sign-in");
        return false;
      }

      // Notify backend of the new sign-in
      bool linkSuccess = await _notifyBackendLink(
        provider: 'google',
        providerToken: googleIdToken,
      );

      if (!linkSuccess) {
        print("Failed to link with backend");
        await signOut();
        return false;
      }

      return true;
    } catch (error) {
      print("signInToFirebaseWithGoogleAccount Error: $error");
      await signOut();
      return false;
    }
  }

  Future<String?> getFreshAuthToken({int maxRetries = 3}) async {
    print("DEBUG: getFreshAuthToken called (maxRetries: $maxRetries)");
    final fb_auth.User? user = _firebaseAuth.currentUser;
    if (user == null) {
      print("DEBUG: No Firebase user currently signed in.");
      return null;
    }

    print("DEBUG: Firebase user found, attempting token refresh...");

    // Retry logic with exponential backoff for network failures
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // Force refresh and handle potential null
        final String? freshToken = await user.getIdToken(true);
        if (freshToken == null) {
          print("DEBUG: Failed to refresh Firebase ID token, it was null.");
          return null;
        }
        print(
          "DEBUG: Successfully got fresh token on attempt $attempt: ${freshToken.substring(0, 20)}...",
        );
        return freshToken;
      } catch (e) {
        print("DEBUG: Token refresh attempt $attempt failed: $e");

        // Check if this is a network-related error that should be retried
        final isNetworkError =
            e.toString().contains('network-request-failed') ||
            e.toString().contains('timeout') ||
            e.toString().contains('unreachable') ||
            e.toString().contains('connection');

        if (!isNetworkError) {
          print("DEBUG: Non-network error, not retrying: $e");
          return null;
        }

        if (attempt == maxRetries) {
          print(
            "DEBUG: All $maxRetries token refresh attempts failed, giving up",
          );
          return null;
        }

        // Exponential backoff: wait longer between each retry
        final delayMs = 500 * attempt; // 500ms, 1000ms, 1500ms...
        print(
          "DEBUG: Waiting ${delayMs}ms before retry attempt ${attempt + 1}",
        );
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    return null; // Should never reach here, but just in case
  }
}
