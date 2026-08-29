import 'package:flutter/services.dart';

class NativeContactAccessService {
  static const MethodChannel _channel = MethodChannel('assiist.contact_access');

  /// Check the current contact access status
  /// Returns: "notDetermined", "restricted", "denied", "authorized", "limited"
  static Future<String> checkContactAccess() async {
    try {
      final String status = await _channel.invokeMethod('checkContactAccess');
      return status;
    } on PlatformException catch (e) {
      print("Error checking contact access: ${e.message}");
      return "unknown";
    }
  }

  /// Request initial contact access (first stage of iOS 18 flow)
  /// This shows the first permission dialog: "Allow Assiist to access your contacts?"
  /// Returns: "authorized", "limited", "denied"
  static Future<String> requestInitialContactAccess() async {
    try {
      final String status = await _channel.invokeMethod(
        'requestInitialContactAccess',
      );
      return status;
    } on PlatformException catch (e) {
      print("Error requesting initial contact access: ${e.message}");
      return "denied";
    }
  }

  /// Request full contact access (handles both stages of iOS 18 flow)
  /// If user has limited access, this will present the upgrade picker
  /// Returns: "authorized", "limited", "denied"
  static Future<String> requestFullContactAccess() async {
    try {
      final String status = await _channel.invokeMethod(
        'requestFullContactAccess',
      );
      return status;
    } on PlatformException catch (e) {
      print("Error requesting contact access: ${e.message}");
      return "denied";
    }
  }

  /// Present iOS 18 contact access picker for managing contact selection
  /// This allows users to add/remove contacts or upgrade to full access
  /// Returns: "authorized", "limited", "denied"
  static Future<String> presentContactAccessPicker() async {
    try {
      final String status = await _channel.invokeMethod(
        'presentContactAccessPicker',
      );
      return status;
    } on PlatformException catch (e) {
      print("Error presenting contact access picker: ${e.message}");
      return "denied";
    }
  }

  /// Open iOS Settings app to the app's permission settings
  static Future<bool> openContactSettings() async {
    try {
      final bool success = await _channel.invokeMethod('openContactSettings');
      return success;
    } on PlatformException catch (e) {
      print("Error opening contact settings: ${e.message}");
      return false;
    }
  }
}
