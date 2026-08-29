import 'dart:async'; // Import for Timer
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart'; // Import for date formatting
// import 'package:assiist_front_end/core/models/contact.dart'; // No longer needed directly
import 'package:assiist_front_end/core/models/task.dart'; // IMPORT centralized model
// import 'package:assiist_front_end/theme/app_styles.dart'; // No longer needed directly
import 'package:assiist_front_end/theme/app_styles.dart'; // Re-import for styles
import 'basic_list_item.dart'; // Re-import for BasicListItem
import 'package:flutter_riverpod/flutter_riverpod.dart'; // For potential future use with providers
import '../screens/contact_record_screen.dart'; // Import for navigation
// REMOVE LogNoteScreen import, navigation handled by parent
// import '../screens/log_note_screen.dart';
import 'package:flutter/gestures.dart'; // Import for TapGestureRecognizer

// Convert to ConsumerStatefulWidget for optimistic UI updates
class TaskItem extends ConsumerStatefulWidget {
  final Task task;
  final VoidCallback? onTap;
  final Function(Task task)? onStatusToggle;
  final bool showContactInSubtitle;

  const TaskItem({
    super.key,
    required this.task,
    this.onTap,
    this.onStatusToggle,
    this.showContactInSubtitle = true,
  });

  @override
  _TaskItemState createState() => _TaskItemState();
}

class _TaskItemState extends ConsumerState<TaskItem> {
  bool _isProcessing = false; // For visual feedback

  @override
  void didUpdateWidget(covariant TaskItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.task.status != oldWidget.task.status) {
      // The task status has been updated from the backend
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _handleToggle() {
    if (widget.onStatusToggle != null) {
      // Only show processing state if we're toggling a completed task
      if (widget.task.status == 'completed') {
        setState(() {
          _isProcessing = true;
        });
      }
      widget.onStatusToggle!(widget.task);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isCompleted = widget.task.status == 'completed';

    // Call helper methods to build title and subtitle
    final String displayTitle = _buildTitle();
    final Widget? subtitleWidget = _buildSubtitle(context);

    final checkMarkButton = CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed:
          _isProcessing
              ? null
              : _handleToggle, // Disable button while processing
      child:
          isCompleted
              ? AppStyles.accentIcon(
                icon: CupertinoIcons.check_mark_circled_solid,
                size: 22.0,
              )
              : AppStyles.accentIcon(icon: CupertinoIcons.circle, size: 22.0),
    );

    // Only apply opacity if processing a completed task
    return Opacity(
      opacity: _isProcessing ? 0.5 : 1.0,
      child: BasicListItem(
        leadingWidget: checkMarkButton,
        title: displayTitle,
        subtitle: subtitleWidget,
        onTap:
            _isProcessing ? null : widget.onTap, // Disable tap while processing
        showChevron: widget.onTap != null,
      ),
    );
  }

  Widget? _buildSubtitle(BuildContext context) {
    List<TextSpan> subtitleSpans = [];

    // Use contactDisplayName directly, assuming it's always available from the backend.
    final String? displayNameForSubtitle = widget.task.contactDisplayName;

    if (widget.showContactInSubtitle &&
        displayNameForSubtitle != null &&
        displayNameForSubtitle.isNotEmpty) {
      subtitleSpans.add(
        TextSpan(
          text: displayNameForSubtitle,
          style: AppStyles.captionTextStyle(context),
        ),
      );
    }

    // Date formatting (always use full date/time format)
    DateTime? relevantDate = widget.task.dueDate ?? widget.task.actionableDate;
    String? dateString;
    if (relevantDate != null) {
      dateString = DateFormat.yMd().add_jm().format(relevantDate);
    }

    if (dateString != null) {
      if (subtitleSpans.isNotEmpty) {
        subtitleSpans.add(
          TextSpan(text: ' | ', style: AppStyles.captionTextStyle(context)),
        );
      }
      subtitleSpans.add(
        TextSpan(text: dateString, style: AppStyles.captionTextStyle(context)),
      );
    }

    if (subtitleSpans.isEmpty) return null;
    return RichText(
      text: TextSpan(children: subtitleSpans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _buildTitle() {
    String displayTitle;
    if (widget.task.type == 'message' &&
        widget.task.body != null &&
        widget.task.body!.isNotEmpty) {
      displayTitle = widget.task.body!;
    } else {
      displayTitle = widget.task.title;
    }
    return displayTitle;
  }
}
