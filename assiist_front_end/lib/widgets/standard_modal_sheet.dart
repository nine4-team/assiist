import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:assiist_front_end/theme/app_styles.dart';

class StandardModalSheet extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget content;
  final String cancelText;
  final String saveText;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const StandardModalSheet({
    Key? key,
    required this.title,
    required this.icon,
    required this.content,
    this.cancelText = 'Cancel',
    this.saveText = 'Save',
    required this.onCancel,
    required this.onSave,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppStyles.subtleBackgroundColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20.0),
          topRight: Radius.circular(20.0),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                // Drag handle
                child: Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 12.0),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey4.resolveFrom(context),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
              Center(child: AppStyles.accentIcon(icon: icon, size: 28.0)),
              const SizedBox(height: 12.0),
              Text(
                title,
                style: AppStyles.h2TextStyle(context).copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppStyles.primaryTextColor(context),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16.0),
              content,
              const SizedBox(height: 24.0),
              Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: onCancel,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        decoration: BoxDecoration(
                          color: AppStyles.cardBackgroundColor(context),
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(
                            color: AppStyles.separatorColor(context),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.xmark,
                              size: 20,
                              color: AppStyles.secondaryTextColor(context),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              cancelText,
                              style: AppStyles.bodyTextStyle(context).copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppStyles.secondaryTextColor(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: onSave,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        decoration: AppStyles.accentButtonDecoration(),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.check_mark_circled_solid,
                              size: 20,
                              color: CupertinoColors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              saveText,
                              style: AppStyles.bodyTextStyle(context).copyWith(
                                fontWeight: FontWeight.w600,
                                color: CupertinoColors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
