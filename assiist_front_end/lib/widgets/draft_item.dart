import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'; // Needed for Colors
import 'package:assiist_front_end/core/models/task.dart';
import 'basic_list_item.dart'; // ADD import for BasicListItem
import 'package:assiist_front_end/theme/app_styles.dart';
import 'package:intl/intl.dart'; // ADD for DateFormat
// import 'package:flutter/gestures.dart';
// import '../screens/contact_record_screen.dart';

class DraftItem extends StatelessWidget {
  final Task task; // Draft task
  final VoidCallback? onTap;
  final bool showContactInSubtitle; // ADD BACK parameter

  const DraftItem({
    super.key,
    required this.task,
    this.onTap,
    this.showContactInSubtitle = true, // Default to true
  });

  @override
  Widget build(BuildContext context) {
    // Determine Title/Body to Display (Prioritize messageBody for drafts)
    String displayTitle;
    if (task.body != null && task.body!.isNotEmpty) {
      displayTitle = task.body!;
    } else {
      displayTitle = task.title; // Fallback to title
    }

    // Construct Subtitle Widget
    List<TextSpan> subtitleSpans = [];

    // Conditional Left part: Contact Name in accent color
    final String? displayName = task.contactDisplayName;
    if (showContactInSubtitle &&
        displayName != null &&
        displayName.isNotEmpty) {
      subtitleSpans.add(
        TextSpan(text: displayName, style: AppStyles.captionTextStyle(context)),
      );
    }

    // Right part: "Send by: [Date]" in gray, with conditional pipe
    if (task.dueDate != null || task.actionableDate != null) {
      String prefix = 'Send by: ';
      if (subtitleSpans.isNotEmpty) {
        // If contact name was added, add pipe separator before date info
        subtitleSpans.add(
          TextSpan(
            text: ' | ',
            style: AppStyles.captionTextStyle(context), // Pipe in gray
          ),
        );
      }
      subtitleSpans.add(
        TextSpan(
          text:
              '$prefix${DateFormat.yMd().add_jm().format(task.dueDate ?? task.actionableDate!)}',
          style: AppStyles.captionTextStyle(context), // Date info in GRAY
        ),
      );
    }

    Widget? subtitleWidget;
    if (subtitleSpans.isNotEmpty) {
      subtitleWidget = RichText(
        text: TextSpan(children: subtitleSpans),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    // Use BasicListItem for consistent layout and styling
    return BasicListItem(
      leadingWidget: Padding(
        padding: const EdgeInsets.only(right: 0.0),
        child: AppStyles.accentIcon(
          icon: CupertinoIcons.paperplane_fill,
          size: 18.0,
        ),
      ),
      title: displayTitle,
      subtitle: subtitleWidget,
      onTap: onTap,
      showChevron: onTap != null,
      // Use default backgroundColor
    );
  }
}
