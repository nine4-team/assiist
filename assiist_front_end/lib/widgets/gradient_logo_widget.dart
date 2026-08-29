import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_styles.dart';
import '../utils/logo_gradient_generator.dart';

/// A widget that displays the app logo with gradient styling
class GradientLogoWidget extends StatelessWidget {
  final double? width;
  final double? height;
  final LinearGradient? gradient;
  final BoxFit fit;
  final bool showShadow;
  final double shadowBlur;
  final Color shadowColor;
  final Offset shadowOffset;
  final EdgeInsets? padding;
  final BorderRadius? borderRadius;

  const GradientLogoWidget({
    Key? key,
    this.width,
    this.height,
    this.gradient,
    this.fit = BoxFit.contain,
    this.showShadow = false,
    this.shadowBlur = 8.0,
    this.shadowColor = Colors.black26,
    this.shadowOffset = const Offset(0, 4),
    this.padding,
    this.borderRadius,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // For now, we'll use a placeholder since we don't have the white logo asset yet
    // You can replace this with your actual logo path once you add it to assets
    const String logoPath = 'assets/images/app_icon_white.png';

    if (showShadow) {
      return LogoGradientGenerator.createGradientLogoWithShadow(
        imagePath: logoPath,
        width: width,
        height: height,
        gradient: gradient,
        fit: fit,
        shadowBlur: shadowBlur,
        shadowColor: shadowColor,
        shadowOffset: shadowOffset,
      );
    } else if (padding != null || borderRadius != null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: gradient ?? AppStyles.gradientAccent,
          borderRadius: borderRadius ?? BorderRadius.circular(12.0),
        ),
        padding: padding ?? const EdgeInsets.all(16.0),
        child: Image.asset(logoPath, fit: fit, color: Colors.white),
      );
    } else {
      return LogoGradientGenerator.createGradientLogoWidget(
        imagePath: logoPath,
        width: width,
        height: height,
        gradient: gradient,
        fit: fit,
      );
    }
  }
}

/// A simple gradient logo for use in app bars, splash screens, etc.
class SimpleGradientLogo extends StatelessWidget {
  final double size;
  final LinearGradient? gradient;

  const SimpleGradientLogo({Key? key, this.size = 40.0, this.gradient})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GradientLogoWidget(
      width: size,
      height: size,
      gradient: gradient,
      fit: BoxFit.contain,
    );
  }
}

/// A gradient logo with shadow for prominent display
class ProminentGradientLogo extends StatelessWidget {
  final double size;
  final LinearGradient? gradient;

  const ProminentGradientLogo({Key? key, this.size = 80.0, this.gradient})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GradientLogoWidget(
      width: size,
      height: size,
      gradient: gradient,
      fit: BoxFit.contain,
      showShadow: true,
      shadowBlur: 12.0,
      shadowColor: Colors.black38,
      shadowOffset: const Offset(0, 6),
    );
  }
}

/// A gradient logo for use in settings or about screens
class SettingsGradientLogo extends StatelessWidget {
  final double size;
  final LinearGradient? gradient;

  const SettingsGradientLogo({Key? key, this.size = 60.0, this.gradient})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GradientLogoWidget(
      width: size,
      height: size,
      gradient: gradient,
      fit: BoxFit.contain,
      padding: const EdgeInsets.all(12.0),
      borderRadius: BorderRadius.circular(16.0),
    );
  }
}
