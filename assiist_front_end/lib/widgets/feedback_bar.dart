import 'package:flutter/cupertino.dart';
import 'package:assiist_front_end/theme/app_styles.dart';
import 'package:assiist_front_end/widgets/feedback_modal.dart';

class FeedbackBar extends StatelessWidget {
  final VoidCallback? onTap;

  const FeedbackBar({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => showFeedbackModal(context),
      child: Container(
        height: 32.0,
        decoration: BoxDecoration(
          color: AppStyles.subtleBackgroundColor(context),
        ),
        child: Center(
          child: AppStyles.accentText(
            context,
            'Send Feedback',
            style: AppStyles.captionTextStyle(
              context,
            ).copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}
