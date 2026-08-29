import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:assiist_front_end/screens/reservation_screen.dart';
import 'package:assiist_front_end/theme/app_styles.dart';

class ShareAssiistDashboard extends StatelessWidget {
  final VoidCallback? onShare;
  const ShareAssiistDashboard({Key? key, this.onShare}) : super(key: key);

  void _handlePromoButtonPress(BuildContext context) {
    // Navigate to reservation screen
    Navigator.of(
      context,
    ).push(CupertinoPageRoute(builder: (context) => const ReservationScreen()));

    if (onShare != null) {
      onShare!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _handlePromoButtonPress(context),
          child: Container(
            decoration: BoxDecoration(
              gradient: AppStyles.gradientAccent,
              borderRadius: BorderRadius.circular(28.0),
            ),
            padding: const EdgeInsets.all(1.5),
            child: Container(
              decoration: BoxDecoration(
                color: AppStyles.subtleBackgroundColor(context),
                borderRadius: BorderRadius.circular(26.5),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 6.5,
                  horizontal: 14.5,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppStyles.accentIcon(icon: CupertinoIcons.plus, size: 18.0),
                    const SizedBox(width: 8.0),
                    AppStyles.accentText(
                      context,
                      'Add to Founders List',
                      style: const TextStyle(
                        fontSize: 15.0,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
