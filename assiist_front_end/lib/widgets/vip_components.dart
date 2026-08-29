import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:assiist_front_end/theme/app_styles.dart';

/// Primary VIP Component - Tappable Badge
/// Combines display and interaction in one clean widget
class TappableVipBadge extends StatelessWidget {
  final bool isVip;
  final VoidCallback? onTap;
  final double size;
  final bool showWhenNotVip;

  const TappableVipBadge({
    Key? key,
    required this.isVip,
    this.onTap,
    this.size = 16,
    this.showWhenNotVip = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Show nothing for non-VIP contacts unless explicitly requested
    if (!isVip && !showWhenNotVip) {
      return const SizedBox.shrink();
    }

    if (isVip) {
      // VIP state - filled gradient button style
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            gradient: AppStyles.gradientAccent,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.star_fill,
                color: CupertinoColors.white,
                size: size * 0.75,
              ),
              const SizedBox(width: 4.0),
              Text(
                'VIP',
                style: TextStyle(
                  color: CupertinoColors.white,
                  fontSize: size * 0.75,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Non-VIP state - bordered style like "Add to Founders List"
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppStyles.gradientAccent,
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.all(1.5),
        child: Container(
          decoration: BoxDecoration(
            color: AppStyles.subtleBackgroundColor(context),
            borderRadius: BorderRadius.circular(26.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5, horizontal: 6.5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppStyles.accentIcon(
                  icon: CupertinoIcons.star,
                  size: size * 0.75,
                ),
                const SizedBox(width: 4.0),
                AppStyles.accentText(
                  context,
                  'MARK VIP',
                  style: TextStyle(
                    fontSize: size * 0.75,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Legacy VIP Badge Widget - Simple display only (deprecated)
/// Use TappableVipBadge instead for new implementations
@Deprecated('Use TappableVipBadge instead for better UX')
class VipBadge extends StatelessWidget {
  final bool isVip;
  final double size;

  const VipBadge({Key? key, required this.isVip, this.size = 16})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isVip) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: AppStyles.gradientAccent, // Use gradient instead of solid red
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'VIP',
        style: TextStyle(
          color: CupertinoColors.white,
          fontSize: size * 0.75,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// VIP Toggle Widget - Switch for toggling VIP status in forms
class VipToggle extends StatelessWidget {
  final bool isVip;
  final ValueChanged<bool> onChanged;
  final String? label;

  const VipToggle({
    Key? key,
    required this.isVip,
    required this.onChanged,
    this.label,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CupertinoFormRow(
      prefix: Text(label ?? 'VIP Status'),
      child: CupertinoSwitch(
        value: isVip,
        onChanged: onChanged,
        activeColor: AppStyles.solidAccent, // Use AppStyles accent system
      ),
    );
  }
}

/// VIP Star Icon - DEPRECATED: Confusing UI element
/// Use TappableVipBadge instead for cleaner UX
@Deprecated('Confusing UI element. Use TappableVipBadge instead.')
class VipStarIcon extends StatelessWidget {
  final bool isVip;
  final double size;
  final VoidCallback? onTap;

  const VipStarIcon({Key? key, required this.isVip, this.size = 24, this.onTap})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child:
          isVip
              ? AppStyles.accentIcon(icon: CupertinoIcons.star_fill, size: size)
              : Icon(
                CupertinoIcons.star,
                size: size,
                color: CupertinoColors.systemGrey,
              ),
    );
  }
}

/// Contact Filter Widget - Segmented control for filtering contacts
enum ContactFilter { all, vipOnly, regularOnly }

class ContactFilterWidget extends StatelessWidget {
  final ContactFilter currentFilter;
  final ValueChanged<ContactFilter> onFilterChanged;

  const ContactFilterWidget({
    Key? key,
    required this.currentFilter,
    required this.onFilterChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CupertinoSegmentedControl<ContactFilter>(
      children: const {
        ContactFilter.all: Text('All'),
        ContactFilter.vipOnly: Text('VIP'),
        ContactFilter.regularOnly: Text('Regular'),
      },
      groupValue: currentFilter,
      onValueChanged: onFilterChanged,
    );
  }
}

/// VIP Contact List Tile - Enhanced list tile with clean VIP indicator
class VipContactListTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isVip;
  final VoidCallback? onTap;
  final VoidCallback? onVipToggle;
  final Widget? leading;
  final Widget? trailing;

  const VipContactListTile({
    Key? key,
    required this.title,
    this.subtitle,
    required this.isVip,
    this.onTap,
    this.onVipToggle,
    this.leading,
    this.trailing,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      onTap: onTap,
      leading:
          leading ??
          CircleAvatar(
            child: Text(title.isNotEmpty ? title[0].toUpperCase() : '?'),
          ),
      title: Row(
        children: [
          Expanded(child: Text(title)),
          if (isVip) TappableVipBadge(isVip: isVip, onTap: onVipToggle),
        ],
      ),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: trailing,
    );
  }
}

/// VIP Analytics Widget - Shows VIP contact statistics
class VipAnalyticsWidget extends StatelessWidget {
  final int totalContacts;
  final int vipContacts;
  final double? engagementScore;

  const VipAnalyticsWidget({
    Key? key,
    required this.totalContacts,
    required this.vipContacts,
    this.engagementScore,
  }) : super(key: key);

  double get vipPercentage =>
      totalContacts > 0 ? (vipContacts / totalContacts) * 100 : 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppStyles.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VIP Contacts', style: AppStyles.h2TextStyle(context)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                'Total VIPs',
                '$vipContacts',
                CupertinoIcons.star_fill,
                context,
              ),
              _buildStatItem(
                'VIP %',
                '${vipPercentage.toStringAsFixed(1)}%',
                CupertinoIcons.chart_pie_fill,
                context,
              ),
              if (engagementScore != null)
                _buildStatItem(
                  'Engagement',
                  '${engagementScore!.toStringAsFixed(0)}%',
                  CupertinoIcons.heart_fill,
                  context,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    BuildContext context,
  ) {
    return Column(
      children: [
        AppStyles.accentIcon(icon: icon),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
