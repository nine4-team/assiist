import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:assiist_front_end/theme/app_styles.dart';

class ControlCenterNavBar extends StatelessWidget {
  final VoidCallback onCalendarTap;
  final VoidCallback onAssistantTap;
  final VoidCallback onAddContactTap;
  final Color? backgroundColor;
  final bool showCalendarButton;

  const ControlCenterNavBar({
    Key? key,
    required this.onCalendarTap,
    required this.onAssistantTap,
    required this.onAddContactTap,
    this.backgroundColor,
    this.showCalendarButton = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppStyles.separatorColor(context),
            width: 0.25,
          ),
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            color:
                backgroundColor ??
                AppStyles.subtleBackgroundColor(context).withOpacity(0.85),
            height:
                84.0, // Calculated height: 8 (top pad) + 56 (button) + 32 (bottom pad)
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Visibility(
                    visible: showCalendarButton,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: CupertinoControlCenterButton(
                      icon: Icons.calendar_today,
                      onTap: onCalendarTap,
                    ),
                  ),
                  CupertinoControlCenterPillButton(
                    icon: CupertinoIcons.pencil,
                    label: 'Assistant',
                    onTap: onAssistantTap,
                  ),
                  CupertinoControlCenterButton(
                    icon: Icons.person_add,
                    onTap: onAddContactTap,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CupertinoControlCenterButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;

  const CupertinoControlCenterButton({
    Key? key,
    required this.icon,
    required this.onTap,
    this.label,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: AppStyles.accentButtonDecoration(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Center(
              child: Icon(icon, color: CupertinoColors.white, size: 28),
            ),
          ),
        ),
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Text(
              label!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: CupertinoColors.white,
                shadows: [
                  Shadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class CupertinoControlCenterPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const CupertinoControlCenterPillButton({
    Key? key,
    required this.icon,
    required this.label,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 49, vertical: 18),
        decoration: AppStyles.accentButtonDecoration(
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: CupertinoColors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.white,
                shadows: [
                  Shadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
