import 'package:flutter/widgets.dart';

/// A widget that automatically unfocuses any focused input when tapped.
///
/// Wrap your screen or form with this widget to dismiss the keyboard when the
/// user taps outside of any text input.
class UnfocusScope extends StatelessWidget {
  /// The child widget to render.
  final Widget child;

  const UnfocusScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Use translucent behavior to ensure it catches all taps
      behavior: HitTestBehavior.translucent,
      // Simply unfocus the primary focus when tapped anywhere
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}

/// A widget that wraps the entire app to handle keyboard dismissal.
///
/// This is a more robust solution that should be used at the app level.
class AppUnfocusScope extends StatefulWidget {
  final Widget child;

  const AppUnfocusScope({super.key, required this.child});

  @override
  State<AppUnfocusScope> createState() => _AppUnfocusScopeState();
}

class _AppUnfocusScopeState extends State<AppUnfocusScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }

  @override
  void didChangeMetrics() {
    // This gets called when keyboard appears/disappears
    final window = WidgetsBinding.instance.window;
    final bottomInset = window.viewInsets.bottom;

    // If keyboard is closing, unfocus to avoid keyboard popping back up
    if (bottomInset == 0.0) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }
}
