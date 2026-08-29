import 'package:flutter/cupertino.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:assiist_front_end/core/models/pending_contact.dart';
import 'package:assiist_front_end/theme/app_styles.dart'; // For styling

// Callbacks for the actions
typedef PendingContactActionCallback =
    void Function(BuildContext context, PendingContact contact);

// Revert to StatelessWidget, remove internal controller management
class SlidablePendingContactItem extends StatelessWidget {
  final PendingContact pendingContact;
  final PendingContactActionCallback? onAdd;
  final PendingContactActionCallback? onIgnore;
  final SlidableController? controller;
  final VoidCallback? onTap;
  final bool isProcessing;
  final bool showSubtitle;
  final Widget? leadingIcon;
  final String? ignoreLabel;

  const SlidablePendingContactItem({
    super.key,
    required this.pendingContact,
    this.onAdd,
    this.onIgnore,
    this.controller,
    this.onTap,
    this.isProcessing = false,
    this.showSubtitle = true,
    this.leadingIcon,
    this.ignoreLabel,
  });

  @override
  Widget build(BuildContext context) {
    // Determine subtitle based on available info (email or phone)
    String subtitle =
        pendingContact.email ?? pendingContact.phone ?? 'No contact info';
    if (pendingContact.email != null && pendingContact.phone != null) {
      subtitle = '${pendingContact.email} ・ ${pendingContact.phone}';
    }

    const double verticalPadding = 8.0; // Define padding for consistency
    const double itemHeight = 52.0; // unified row & action height

    return Opacity(
      opacity: isProcessing ? 0.5 : 1.0,
      child: Slidable(
        key: ValueKey(pendingContact.id),
        controller: controller,
        endActionPane: ActionPane(
          motion: const BehindMotion(),
          extentRatio: 0.5,
          children: [
            if (onAdd != null)
              CustomSlidableAction(
                flex: 1,
                onPressed: (context) => onAdd!(context, pendingContact),
                backgroundColor: CupertinoColors.systemGreen,
                foregroundColor: CupertinoColors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8.0),
                  bottomLeft: Radius.circular(8.0),
                ),
                child: const Text(
                  'Add',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.white,
                  ),
                ),
              ),
            if (onIgnore != null)
              CustomSlidableAction(
                flex: 1,
                onPressed: (context) => onIgnore!(context, pendingContact),
                backgroundColor: CupertinoColors.systemRed,
                foregroundColor: CupertinoColors.white,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8.0),
                  bottomRight: Radius.circular(8.0),
                ),
                child: Text(
                  ignoreLabel ?? 'Ignore',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.white,
                  ),
                ),
              ),
          ],
        ),
        child: GestureDetector(
          onTap: isProcessing ? null : onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: itemHeight,
            margin: const EdgeInsets.only(bottom: 8.0),
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 6.0,
            ),
            decoration: BoxDecoration(
              color: AppStyles.cardBackgroundColor(context),
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child:
                          leadingIcon ??
                          AppStyles.accentIcon(
                            icon: CupertinoIcons.person_alt_circle,
                            size: 28.0,
                          ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            pendingContact.email ?? 'No Email',
                            style: AppStyles.inputTextStyle(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (showSubtitle &&
                              pendingContact.sourceEventTitle != null &&
                              pendingContact.sourceEventTitle!.isNotEmpty) ...[
                            const SizedBox(height: 2.0),
                            Text(
                              'From: ${pendingContact.sourceEventTitle}',
                              style: AppStyles.captionTextStyle(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (isProcessing) const CupertinoActivityIndicator(),
              ],
            ),
          ),
        ), // end GestureDetector
      ), // end Slidable (child of Opacity)
    ); // end Opacity (return)
  }
}
