import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppSegmentedToggle<T extends Object> extends StatelessWidget {
  final Map<T, String> options;
  final T groupValue;
  final ValueChanged<T?> onValueChanged;

  const AppSegmentedToggle({
    Key? key,
    required this.options,
    required this.groupValue,
    required this.onValueChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Color activeColor = Colors.white;
    final Color inactiveColor = CupertinoColors.systemGrey;
    final fontWeight = FontWeight.w600;

    final children = <T, Widget>{};
    options.forEach((value, label) {
      children[value] = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            color: groupValue == value ? activeColor : inactiveColor,
            fontWeight: fontWeight,
          ),
        ),
      );
    });

    return CupertinoSlidingSegmentedControl<T>(
      groupValue: groupValue,
      padding: const EdgeInsets.all(4),
      children: children,
      onValueChanged: onValueChanged,
    );
  }
}
