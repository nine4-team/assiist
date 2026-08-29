import 'package:permission_handler/permission_handler.dart';

class PermissionUtils {
  /// Requests permission to access device contacts.
  ///
  /// Returns `true` if permission is granted, `false` otherwise.
  static Future<bool> requestContactsPermission() async {
    final status = await Permission.contacts.request();
    return status.isGranted;
  }

  /// Checks the current status of contacts permission.
  ///
  /// Can be used to update UI or decide if requesting permission is necessary.
  static Future<PermissionStatus> getContactsPermissionStatus() async {
    return await Permission.contacts.status;
  }

  /// Opens the app settings so the user can manually grant permission
  /// if it was permanently denied or restricted.
  static Future<void> openAppSettings() async {
    await openAppSettings(); // This is from permission_handler itself
  }
}
