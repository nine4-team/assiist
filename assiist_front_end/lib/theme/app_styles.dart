import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

// Centralized application styles and constants
class AppStyles {
  // --- Padding & Sizing ---
  static const double defaultHorizontalPadding = 16.0;
  static const double defaultVerticalPadding = 12.0;
  static const EdgeInsets defaultPadding = EdgeInsets.symmetric(
    horizontal: defaultHorizontalPadding,
    vertical: defaultVerticalPadding,
  );
  static const double dividerThickness = 0.5;

  // --- Colors (Context-dependent) ---
  static Color subtleBackgroundColor(BuildContext context) {
    final bool isDarkMode =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    return isDarkMode
        ? CupertinoColors.darkBackgroundGray
        : CupertinoColors.systemGrey6;
  }

  static Color cardBackgroundColor(BuildContext context) {
    final bool isDarkMode =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    return isDarkMode
        ? CupertinoColors.systemGrey6.withOpacity(0.15)
        : CupertinoColors.white;
  }

  static Color sectionBackgroundColor(BuildContext context) =>
      CupertinoColors.tertiarySystemFill.resolveFrom(context);

  static Color separatorColor(BuildContext context) =>
      CupertinoColors.separator.resolveFrom(context).withOpacity(0.5);

  /// Background color for input fields that adapts to theme.
  static Color inputBackgroundColor(BuildContext context) {
    final bool isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    return isDark
        ? CupertinoColors.systemGrey6.withOpacity(0.15)
        : CupertinoColors
            .systemGrey6; // Light gray input fields to contrast against white cards
  }

  // --- Component Specific Colors ---------------------------------------- //

  /// Background track color for `CupertinoSlidingSegmentedControl` that adapts to
  /// light/dark mode.
  static Color segmentedTrackColor(BuildContext context) {
    final bool isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    return isDark
        ? const Color(0xFF2C2C2F) // Matching native iOS dark segmented track
        : CupertinoColors.systemGrey4; // Light mode subtle grey
  }

  /// Thumb color for `CupertinoSlidingSegmentedControl`.
  static Color segmentedThumbColor(BuildContext context) {
    final bool isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    return isDark
        ? const Color(0xFF767680) // Native iOS dark thumb
        : CupertinoColors.white; // Light mode thumb
  }

  // --- Text Colors (Simplified) ---
  static Color primaryTextColor(BuildContext context) =>
      CupertinoTheme.of(context).textTheme.textStyle.color ??
      CupertinoColors.label.resolveFrom(
        context,
      ); // Default, usually black/white

  static Color secondaryTextColor(BuildContext context) => CupertinoColors
      .secondaryLabel
      .resolveFrom(context); // For less emphasis, usually grey

  static Color prominentTextColor(BuildContext context) =>
      CupertinoTheme.of(
        context,
      ).primaryContrastingColor; // Typically white, for use on primaryColor backgrounds

  /// Legacy solid accent color - uses centralized accent system
  /// For gradient support, use accentText() or accentIcon() instead
  static Color accentTextColor(BuildContext context) => solidAccent;

  /// Primary accent text - automatically uses gradient or solid based on useGradientAccent
  static Widget accentText(
    BuildContext context,
    String text, {
    TextStyle? style,
  }) {
    if (useGradientAccent) {
      return gradientText(
        child: Text(
          text,
          style: (style ?? bodyTextStyle(context)).copyWith(
            color: CupertinoColors.white,
          ),
        ),
      );
    } else {
      return Text(
        text,
        style: (style ?? bodyTextStyle(context)).copyWith(color: solidAccent),
      );
    }
  }

  /// Primary accent icon - automatically uses gradient or solid based on useGradientAccent
  static Widget accentIcon({required IconData icon, double size = 24.0}) {
    if (useGradientAccent) {
      return gradientIcon(icon: icon, size: size);
    } else {
      return Icon(icon, size: size, color: solidAccent);
    }
  }

  // --- Primary Accent System ---

  /// Set this to control your app's accent styling everywhere
  static const bool useGradientAccent = true;

  /// Solid accent color (used when useGradientAccent = false)
  //static const Color solidAccent = CupertinoColors.systemRed;
  static const Color solidAccent = Color(0xFFDAA520); // Rich goldenrod

  /// Gradient accent (used when useGradientAccent = true)
  static const LinearGradient gradientAccent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFD700), // Bright gold highlight
      Color(0xFFDAA520), // Rich goldenrod
      Color(0xFFB8860B), // Dark goldenrod
      Color(0xFF8B7355), // Dark bronze
    ],
    stops: [0.0, 0.1, 0.7, 1.0],
  );

  /// Creates a ShaderMask for applying the gradient to text or icons
  static Widget gradientText({
    required Widget child,
    LinearGradient? gradient,
  }) {
    return ShaderMask(
      blendMode: BlendMode.srcIn, // Ensure proper gradient blending
      shaderCallback:
          (bounds) => (gradient ?? gradientAccent).createShader(bounds),
      child: child,
    );
  }

  /// Creates a ShaderMask for applying the gradient to icons
  static Widget gradientIcon({
    required IconData icon,
    double size = 24.0,
    LinearGradient? gradient,
  }) {
    return ShaderMask(
      blendMode: BlendMode.srcIn, // Ensure proper gradient blending
      shaderCallback:
          (bounds) => (gradient ?? gradientAccent).createShader(bounds),
      child: Icon(
        icon,
        size: size,
        color: CupertinoColors.white, // Base color for gradient overlay
      ),
    );
  }

  /// Replaces any accent color usage with gradient - use this instead of accentTextColor
  static Widget accentGradientText(
    BuildContext context,
    String text, {
    TextStyle? style,
  }) {
    return gradientText(
      child: Text(
        text,
        style: (style ?? bodyTextStyle(context)).copyWith(
          color: CupertinoColors.white, // Base color for gradient
        ),
      ),
    );
  }

  /// Creates a gradient container for button backgrounds - automatically uses gradient or solid based on useGradientAccent
  static BoxDecoration accentButtonDecoration({BorderRadius? borderRadius}) {
    if (useGradientAccent) {
      return BoxDecoration(
        gradient: gradientAccent,
        borderRadius: borderRadius ?? BorderRadius.circular(8.0),
      );
    } else {
      return BoxDecoration(
        color: solidAccent,
        borderRadius: borderRadius ?? BorderRadius.circular(8.0),
      );
    }
  }

  /// Creates a gradient border decoration - automatically uses gradient or solid based on useGradientAccent
  static BoxDecoration accentBorderDecoration({
    BorderRadius? borderRadius,
    double borderWidth = 1.0,
  }) {
    return BoxDecoration(
      border: Border.all(
        color: useGradientAccent ? solidAccent : solidAccent,
        width: borderWidth,
      ),
      borderRadius: borderRadius ?? BorderRadius.circular(8.0),
    );
  }

  /// Creates a proper gradient border using Container nesting approach
  static Widget gradientBorder({
    required Widget child,
    required BuildContext context,
    BorderRadius? borderRadius,
    double borderWidth = 1.5,
    LinearGradient? gradient,
  }) {
    if (!useGradientAccent) {
      // Fallback to regular border when gradients are disabled
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: solidAccent, width: borderWidth),
          borderRadius: borderRadius ?? BorderRadius.circular(8.0),
        ),
        child: child,
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: gradient ?? gradientAccent,
        borderRadius: borderRadius ?? BorderRadius.circular(8.0),
      ),
      padding: EdgeInsets.all(borderWidth),
      child: Container(
        decoration: BoxDecoration(
          color: AppStyles.subtleBackgroundColor(
            context,
          ), // Match screen background
          borderRadius:
              borderRadius != null
                  ? BorderRadius.circular(
                    (borderRadius.topLeft.x - borderWidth).clamp(
                      0,
                      double.infinity,
                    ),
                  )
                  : BorderRadius.circular(6.5), // 8.0 - 1.5 = 6.5
        ),
        child: child,
      ),
    );
  }

  // --- Text Styles (NEW CSS-inspired Naming) ---

  // Define base font sizes
  static const double _fontSizeH1 = 22.0;
  static const double _fontSizeH2 = 17.0;
  static const double _fontSizeH3 = 15.0;
  static const double _fontSizeBody = 15.0;
  static const double _fontSizeCaption = 13.0;
  static const double _fontSizeInput = 16.0; // Current input size

  // H1 - For primary page titles
  static TextStyle h1TextStyle(BuildContext context) {
    return TextStyle(
      fontSize: _fontSizeH1,
      fontWeight: FontWeight.w600, // Semibold
      color: AppStyles.primaryTextColor(context),
    );
  }

  // H2 - For major section titles
  static TextStyle h2TextStyle(BuildContext context) {
    return TextStyle(
      fontSize: _fontSizeH2,
      fontWeight:
          FontWeight.w400, // Regular weight (aligns with typical H2 uses)
      color: AppStyles.secondaryTextColor(context), // UPDATED to secondary/gray
    );
  }

  // H3 - For item titles (often prominent, e.g., on cards or contrasting backgrounds)
  static TextStyle h3TextStyle(BuildContext context) {
    return TextStyle(
      fontSize: _fontSizeH3,
      fontWeight: FontWeight.w500, // Medium weight
      color: AppStyles.prominentTextColor(
        context,
      ), // Prominent color (e.g., white)
    );
  }

  // H3 Standard Variant - Item titles with standard text color (less prominent than H3)
  static TextStyle h3StandardTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: _fontSizeH3,
      fontWeight: FontWeight.w400, // Regular weight for standard color
      color: AppStyles.primaryTextColor(context),
    );
  }

  // Body - Standard text for content blocks and detailed information
  static TextStyle bodyTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: _fontSizeBody,
      fontWeight: FontWeight.w400,
      color: AppStyles.primaryTextColor(context),
    );
  }

  // Label - For field labels or secondary text, same size as body but greyed out for less emphasis
  static TextStyle labelTextStyle(BuildContext context) {
    return bodyTextStyle(
      context,
    ).copyWith(color: AppStyles.secondaryTextColor(context));
  }

  // Caption - For small meta-text, dates, status indicators, and other tertiary information
  static TextStyle captionTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: _fontSizeCaption,
      fontWeight: FontWeight.w400,
      color: AppStyles.secondaryTextColor(context),
    );
  }

  // Caption variant - Prominent color, for small text that needs to be normally visible (not greyed)
  static TextStyle captionProminentTextStyle(BuildContext context) {
    return captionTextStyle(
      context,
    ).copyWith(color: AppStyles.primaryTextColor(context));
  }

  // Caption variant - Accent color, for small text that needs to use the theme's accent color
  static TextStyle captionAccentTextStyle(BuildContext context) {
    return captionTextStyle(context).copyWith(
      color: AppStyles.accentTextColor(context),
      fontWeight: FontWeight.w500, // Slightly bolder for accent
    );
  }

  // Caption variant - Gradient accent, for small text with gradient styling
  static Widget captionAccentGradientText(BuildContext context, String text) {
    return gradientText(
      child: Text(
        text,
        style: captionTextStyle(context).copyWith(
          color: CupertinoColors.white, // Base color for gradient
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // Caption accent text - automatically uses gradient or solid based on useGradientAccent
  static Widget captionAccentText(
    BuildContext context,
    String text, {
    TextStyle? style,
  }) {
    if (useGradientAccent) {
      return gradientText(
        child: Text(
          text,
          style: (style ?? captionTextStyle(context)).copyWith(
            color: CupertinoColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    } else {
      return Text(
        text,
        style: (style ?? captionTextStyle(context)).copyWith(
          color: solidAccent,
          fontWeight: FontWeight.w600,
        ),
      );
    }
  }

  // Action sheet text - automatically uses gradient or solid based on useGradientAccent
  static Widget actionSheetText(
    BuildContext context,
    String text, {
    TextStyle? style,
  }) {
    if (useGradientAccent) {
      return gradientText(
        child: Text(
          text,
          style: (style ??
                  const TextStyle(fontSize: 20.0, fontWeight: FontWeight.w400))
              .copyWith(color: CupertinoColors.white),
        ),
      );
    } else {
      return Text(
        text,
        style: (style ??
                const TextStyle(fontSize: 20.0, fontWeight: FontWeight.w400))
            .copyWith(color: solidAccent),
      );
    }
  }

  // Input field text style - For text entered by the user in text fields
  static TextStyle inputTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: _fontSizeInput, // Specific size for inputs
      fontWeight: FontWeight.w400,
      color: AppStyles.primaryTextColor(context),
    );
  }

  // Placeholder text style for input fields - Hint text shown before user input
  static TextStyle placeholderTextStyle(BuildContext context) => inputTextStyle(
    context,
  ).copyWith(color: AppStyles.secondaryTextColor(context).withOpacity(0.7));

  // --- Button Text Styles ---
  // Standard button text style (e.g., for text buttons or icon buttons with text)
  static TextStyle buttonTextStyle(BuildContext context) =>
  // Using body font size for button text, but with accent color and bold
  bodyTextStyle(context).copyWith(
    fontWeight: FontWeight.w600,
    color: AppStyles.accentTextColor(context),
  );

  // Gradient button text - For button text with gradient styling
  static Widget buttonGradientText(BuildContext context, String text) {
    return gradientText(
      child: Text(
        text,
        style: bodyTextStyle(context).copyWith(
          fontWeight: FontWeight.w600,
          color: CupertinoColors.white, // Base color for gradient
        ),
      ),
    );
  }

  // Button accent text - automatically uses gradient or solid based on useGradientAccent
  static Widget buttonAccentText(
    BuildContext context,
    String text, {
    TextStyle? style,
  }) {
    if (useGradientAccent) {
      return gradientText(
        child: Text(
          text,
          style: (style ?? bodyTextStyle(context)).copyWith(
            color: CupertinoColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    } else {
      return Text(
        text,
        style: (style ?? bodyTextStyle(context)).copyWith(
          color: solidAccent,
          fontWeight: FontWeight.w600,
        ),
      );
    }
  }

  static TextStyle filledButtonTextStyle(BuildContext context) =>
  // Using body font size, white color for text on filled buttons (works with gradient backgrounds)
  bodyTextStyle(context).copyWith(
    fontWeight: FontWeight.w600,
    color:
        CupertinoColors
            .white, // Always white for filled buttons with gradient/accent backgrounds
  );

  // --- Padding for Buttons ---
  static const EdgeInsets filledButtonPadding = EdgeInsets.symmetric(
    vertical: 8.0,
    horizontal: 20.0,
  );

  /// Creates a filled button with gradient accent background
  static Widget filledButton({
    required BuildContext context,
    required String text,
    required VoidCallback onPressed,
    BorderRadius? borderRadius,
    IconData? icon,
    double iconSize = 20.0,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        padding: filledButtonPadding,
        decoration: accentButtonDecoration(
          borderRadius: borderRadius ?? BorderRadius.circular(8.0),
        ),
        child:
            icon != null
                ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: CupertinoColors.white, size: iconSize),
                    const SizedBox(width: 8.0),
                    Text(text, style: filledButtonTextStyle(context)),
                  ],
                )
                : Text(text, style: filledButtonTextStyle(context)),
      ),
    );
  }

  /// Creates a bordered button with gradient accent border and text
  static Widget borderedButton({
    required BuildContext context,
    required String text,
    required VoidCallback onPressed,
    BorderRadius? borderRadius,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: gradientBorder(
        context: context,
        borderRadius: borderRadius ?? BorderRadius.circular(8.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 6.5,
            horizontal: 18.5,
          ), // Compensate for border width
          child: accentText(
            context,
            text,
            style: bodyTextStyle(context).copyWith(
              fontWeight: FontWeight.w600, // Match other button font weight
            ),
          ), // Gradient text for bordered buttons
        ),
      ),
    );
  }

  /// Creates a borderless button with gradient accent text
  static Widget borderlessButton({
    required BuildContext context,
    required String text,
    required VoidCallback onPressed,
  }) {
    return CupertinoButton(
      padding: filledButtonPadding,
      onPressed: onPressed,
      child: accentText(
        context,
        text,
        style: bodyTextStyle(context).copyWith(
          fontWeight: FontWeight.w600, // Match other button font weight
        ),
      ),
    );
  }

  // --- Input Decorations ---
  static BoxDecoration get minimalInputDecoration {
    return const BoxDecoration(
      // This decoration is minimal, often appearing transparent.
      // It relies on the TextField's padding and placeholder for visual cues.
      // No explicit border or background color is set here.
    );
  }
}

class AppStyledDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;
  final IconData? icon;

  const AppStyledDialog({
    Key? key,
    required this.title,
    required this.content,
    required this.actions,
    this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      content: Padding(
        padding: const EdgeInsets.only(top: 12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              AppStyles.accentIcon(icon: icon!, size: 24.0),
              const SizedBox(height: 12.0),
            ],
            Text(
              title,
              style: AppStyles.h2TextStyle(context),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12.0),
            Flexible(child: SingleChildScrollView(child: content)),
          ],
        ),
      ),
      actions: actions,
    );
  }
}
