import 'package:flutter/cupertino.dart';
// Remove incorrect import
// import '../screens/dashboard_screen.dart';
// Import the model directly using correct package name
import 'package:assiist_front_end/core/models/pending_contact.dart';
// import 'package:assiist_front_end/theme/app_styles.dart'; // No longer needed directly
import 'basic_list_item.dart'; // IMPORT new basic widget

class PendingContactItem extends StatelessWidget {
  final PendingContact pendingContact;
  final VoidCallback onTap;
  final bool showSubtitle;

  const PendingContactItem({
    super.key,
    required this.pendingContact,
    required this.onTap,
    this.showSubtitle = true,
  });

  @override
  Widget build(BuildContext context) {
    // Assign title and subtitle directly based on the confirmed convention
    // Assumes email and displayName are never null for PendingContact
    final String title = pendingContact.email!;
    final String subtitleString =
        'From: ${pendingContact.displayName}'; // Renamed to avoid conflict

    /* --- REMOVED conditional logic ---
    // Determine title and subtitle based on email availability
    final String title;
    final String? subtitle;

    if (pendingContact.email != null && pendingContact.email!.isNotEmpty) {
      title = pendingContact.email!;
      subtitle = pendingContact.displayName; // Use displayName as subtitle
    } else {
      title = pendingContact.displayName; // Use displayName as title if no email
      subtitle = 'From Calendar'; // Indicate source if no email
    }
    --- END REMOVED conditional logic --- */

    /* --- OLD subtitle logic ---
    String subtitle = '';
    if (pendingContact.email != null) {
      subtitle = pendingContact.email!;
    } else if (pendingContact.phone != null) {
      subtitle = pendingContact.phone!;
    }
    --- END OLD subtitle logic --- */

    // Use BasicListItem
    return BasicListItem(
      title: title, // Use email
      subtitle: showSubtitle ? Text(subtitleString) : null,
      onTap: onTap,
      showChevron: true, // Keep the chevron
    );

    /* --- REMOVED old layout ---
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque, // Ensure empty areas are tappable
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
        margin: const EdgeInsets.only(bottom: 8.0), // Spacing between items
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pendingContact.displayName,
                    style: AppStyles.inputTextStyle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2.0),
                    Text(
                      subtitle,
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .tabLabelTextStyle
                          .copyWith(color: CupertinoColors.systemGrey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8.0),
            const Icon(
              CupertinoIcons.right_chevron,
              color: CupertinoColors.systemGrey2,
              size: 18.0,
            ),
          ],
        ),
      ),
    );
    --- END REMOVED old layout --- */
  }
}
