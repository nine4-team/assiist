import 'package:flutter/cupertino.dart';
import 'package:assiist_front_end/theme/app_styles.dart'; // Assuming AppStyles is needed for styling

class KpiWidget extends StatelessWidget {
  final String label;
  final String value;

  const KpiWidget({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    // Use theme-aware colors for better visibility
    final labelStyle = TextStyle(
      color: AppStyles.secondaryTextColor(context),
      fontSize: 13.0,
      fontWeight: FontWeight.w500, // Slightly bolder for better visibility
      height: 1.2,
    );
    final valueStyle = const TextStyle(
      fontSize: 18.0,
      fontWeight: FontWeight.w300,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppStyles.accentText(context, value, style: valueStyle),
        const SizedBox(height: 8.0),
        Text(label, style: labelStyle, textAlign: TextAlign.center),
      ],
    );
  }
}
