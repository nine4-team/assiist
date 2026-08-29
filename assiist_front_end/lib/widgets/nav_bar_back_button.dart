import 'package:flutter/cupertino.dart';
import 'package:assiist_front_end/theme/app_styles.dart';

/// Centralized navigation bar back button with smart accent color
class NavBarBackButton extends StatelessWidget {
  const NavBarBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      child: AppStyles.accentIcon(
        icon: CupertinoIcons.chevron_left,
        size: 28.0,
      ),
      onPressed: () => Navigator.pop(context),
    );
  }
}
