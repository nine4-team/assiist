import 'package:flutter/cupertino.dart';
import 'package:assiist_front_end/theme/app_styles.dart';

class BasicListItem extends StatelessWidget {
  final String title;
  final Widget? subtitle;
  final VoidCallback? onTap;
  final bool showChevron;
  final Widget? leadingWidget;
  final Color? backgroundColor;
  final Widget? trailingWidget;

  const BasicListItem({
    super.key,
    required this.title,
    this.subtitle,
    this.onTap,
    this.showChevron = true, // Default to true
    this.leadingWidget,
    this.backgroundColor,
    this.trailingWidget,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasSubtitle = subtitle != null;

    // Determine bottom padding based on leading widget presence
    final double bottomPadding = (leadingWidget == null) ? 8.0 : 12.0;

    Widget content = Container(
      padding: EdgeInsets.only(
        top: 12.0,
        bottom: bottomPadding,
        left: 12.0,
        right: 12.0,
      ), // Use dynamic bottom padding
      margin: const EdgeInsets.only(bottom: 8.0),
      decoration: BoxDecoration(
        color:
            backgroundColor ?? // Use provided color or default
            AppStyles.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        children: [
          if (leadingWidget != null) ...[
            leadingWidget!,
            const SizedBox(width: 12.0),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize:
                  MainAxisSize.min, // Prevent column expanding vertically
              children: [
                Text(
                  title,
                  style: AppStyles.inputTextStyle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasSubtitle) ...[
                  const SizedBox(height: 2.0),
                  subtitle!, // Render the subtitle widget directly
                ],
              ],
            ),
          ),
          // Add trailing widget if provided
          if (trailingWidget != null) ...[
            const SizedBox(width: 8.0),
            trailingWidget!,
          ],
          if (showChevron) ...[
            const SizedBox(width: 8.0),
            AppStyles.accentIcon(
              icon: CupertinoIcons.right_chevron,
              size: 18.0,
            ),
          ],
        ],
      ),
    );

    // Wrap with GestureDetector only if onTap is provided
    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque, // Ensure empty areas are tappable
        child: content,
      );
    } else {
      return content;
    }
  }
}
