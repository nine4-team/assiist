import 'package:flutter/cupertino.dart';
import '../theme/app_styles.dart';

/// A simple borderless action button with an icon and text,
/// styled similarly to the action buttons on the Dashboard.
class BorderlessActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const BorderlessActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Style based on DashboardScreen's _buildBorderlessActionButtons
    const buttonTextStyle = TextStyle(
      fontSize: 16.0,
      fontWeight: FontWeight.w300,
      color: CupertinoColors.white,
    );
    const iconSize = 18.0;
    const spacing = 8.0;

    return CupertinoButton(
      padding: const EdgeInsets.symmetric(
        horizontal: 8.0,
        vertical: 4.0,
      ), // Add some minimal padding
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppStyles.accentIcon(icon: icon, size: iconSize),
          const SizedBox(width: spacing),
          Text(label, style: buttonTextStyle),
        ],
      ),
    );
  }
}
