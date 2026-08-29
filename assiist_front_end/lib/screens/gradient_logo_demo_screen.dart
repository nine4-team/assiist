import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_styles.dart';
import '../widgets/gradient_logo_widget.dart';

/// Demo screen showing different gradient logo variations
/// This is just for testing - you can remove it later
class GradientLogoDemoScreen extends StatelessWidget {
  const GradientLogoDemoScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Gradient Logo Demo'),
      ),
      child: SafeArea(
        child: Padding(
          padding: AppStyles.defaultPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),

              // Simple gradient logo
              const Text(
                'Simple Gradient Logo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              const SimpleGradientLogo(size: 60),

              const SizedBox(height: 40),

              // Prominent gradient logo with shadow
              const Text(
                'Prominent Gradient Logo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              const ProminentGradientLogo(size: 100),

              const SizedBox(height: 40),

              // Settings style gradient logo
              const Text(
                'Settings Style Logo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              const SettingsGradientLogo(size: 80),

              const SizedBox(height: 40),

              // Custom gradient logo
              const Text(
                'Custom Gradient Logo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              GradientLogoWidget(
                width: 80,
                height: 80,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                showShadow: true,
                shadowBlur: 8.0,
                shadowColor: Colors.purple.withOpacity(0.3),
                shadowOffset: const Offset(0, 4),
              ),

              const SizedBox(height: 40),

              // Instructions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppStyles.subtleBackgroundColor(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'To use gradient logos in your app:',
                      style: AppStyles.h3TextStyle(context),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. Add your white logo to assets/images/app_icon_white.png',
                      style: AppStyles.bodyTextStyle(context),
                    ),
                    Text(
                      '2. Use SimpleGradientLogo, ProminentGradientLogo, or SettingsGradientLogo widgets',
                      style: AppStyles.bodyTextStyle(context),
                    ),
                    Text(
                      '3. Run the gradient icon generator script to create TestFlight icons',
                      style: AppStyles.bodyTextStyle(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
