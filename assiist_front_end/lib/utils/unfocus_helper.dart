import 'package:flutter/widgets.dart';

/// Helper class for implementing keyboard dismissal throughout the app.
///
/// This class provides utility methods that can be used to dismiss
/// the keyboard when tapping outside input fields.
class UnfocusHelper {
  /// Adds GestureDetector to dismiss keyboard to any widget
  ///
  /// Use this in a screen's build method by wrapping the entire screen:
  /// ```dart
  /// @override
  /// Widget build(BuildContext context) {
  ///   return UnfocusHelper.addDismissKeyboard(
  ///     context: context,
  ///     child: YourScreen(),
  ///   );
  /// }
  /// ```
  static Widget addDismissKeyboard({
    required BuildContext context,
    required Widget child,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => dismissKeyboard(context),
      child: child,
    );
  }

  /// Directly dismiss the keyboard - can be called from anywhere
  ///
  /// Example usage in a button callback:
  /// ```dart
  /// onPressed: () {
  ///   UnfocusHelper.dismissKeyboard(context);
  ///   // Additional logic
  /// }
  /// ```
  static void dismissKeyboard(BuildContext context) {
    FocusScope.of(context).unfocus();
  }
}
