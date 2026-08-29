import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_styles.dart';

/// Utility class for generating gradient-enhanced app icons
class LogoGradientGenerator {
  /// Generates a gradient-enhanced version of the app icon
  /// This creates a new PNG file with a gradient overlay applied to the white logo
  static Future<String?> generateGradientLogo({
    String? inputPath,
    String? outputPath,
    LinearGradient? gradient,
    double opacity = 0.8,
  }) async {
    try {
      // Use the app's gradient accent by default
      final logoGradient = gradient ?? AppStyles.gradientAccent;

      // Default input path - the current app icon
      final defaultInputPath =
          inputPath ??
          'assets/images/app_icon_white.png'; // You'll need to add this

      // Load the white logo image
      final ByteData imageData = await rootBundle.load(defaultInputPath);
      final Uint8List bytes = imageData.buffer.asUint8List();

      // Decode the image
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image originalImage = frameInfo.image;

      // Create a picture recorder to draw the gradient overlay
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      // Get the image dimensions
      final double width = originalImage.width.toDouble();
      final double height = originalImage.height.toDouble();

      // Draw the original white logo
      canvas.drawImage(originalImage, Offset.zero, Paint());

      // Create gradient shader
      final Rect gradientRect = Rect.fromLTWH(0, 0, width, height);
      final Paint gradientPaint =
          Paint()
            ..shader = logoGradient.createShader(gradientRect)
            ..blendMode =
                BlendMode.multiply; // Multiply blend mode for gradient overlay

      // Draw gradient overlay
      canvas.drawRect(gradientRect, gradientPaint);

      // Convert to image
      final ui.Picture picture = recorder.endRecording();
      final ui.Image gradientImage = await picture.toImage(
        originalImage.width,
        originalImage.height,
      );

      // Convert to PNG bytes
      final ByteData? pngBytes = await gradientImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (pngBytes == null) {
        throw Exception('Failed to convert image to PNG');
      }

      // Save the file
      final Directory tempDir = await getTemporaryDirectory();
      final String fileName =
          outputPath ??
          'gradient_logo_${DateTime.now().millisecondsSinceEpoch}.png';
      final String filePath = '${tempDir.path}/$fileName';

      final File file = File(filePath);
      await file.writeAsBytes(pngBytes.buffer.asUint8List());

      return filePath;
    } catch (e) {
      print('Error generating gradient logo: $e');
      return null;
    }
  }

  /// Creates a gradient-enhanced logo widget for in-app use
  /// This is useful for displaying a gradient version of your logo within the app
  static Widget createGradientLogoWidget({
    required String imagePath,
    double? width,
    double? height,
    LinearGradient? gradient,
    BoxFit fit = BoxFit.contain,
  }) {
    return ShaderMask(
      blendMode: BlendMode.multiply,
      shaderCallback: (bounds) {
        final logoGradient = gradient ?? AppStyles.gradientAccent;
        return logoGradient.createShader(bounds);
      },
      child: Image.asset(
        imagePath,
        width: width,
        height: height,
        fit: fit,
        color: Colors.white, // Base color for the gradient overlay
      ),
    );
  }

  /// Alternative approach using Container with gradient background
  /// This creates a gradient background with the logo on top
  static Widget createGradientLogoContainer({
    required String imagePath,
    double? width,
    double? height,
    LinearGradient? gradient,
    BoxFit fit = BoxFit.contain,
    EdgeInsets? padding,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: gradient ?? AppStyles.gradientAccent,
        borderRadius: BorderRadius.circular(12.0), // Optional rounded corners
      ),
      padding: padding ?? const EdgeInsets.all(16.0),
      child: Image.asset(imagePath, fit: fit, color: Colors.white),
    );
  }

  /// Creates a gradient logo with shadow effect
  static Widget createGradientLogoWithShadow({
    required String imagePath,
    double? width,
    double? height,
    LinearGradient? gradient,
    BoxFit fit = BoxFit.contain,
    double shadowBlur = 8.0,
    Color shadowColor = Colors.black26,
    Offset shadowOffset = const Offset(0, 4),
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: gradient ?? AppStyles.gradientAccent,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: shadowBlur,
            offset: shadowOffset,
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Image.asset(imagePath, fit: fit, color: Colors.white),
    );
  }
}

/// Extension methods for easy gradient logo creation
extension GradientLogoExtension on String {
  /// Creates a gradient logo widget from an image path
  Widget toGradientLogo({
    double? width,
    double? height,
    LinearGradient? gradient,
    BoxFit fit = BoxFit.contain,
  }) {
    return LogoGradientGenerator.createGradientLogoWidget(
      imagePath: this,
      width: width,
      height: height,
      gradient: gradient,
      fit: fit,
    );
  }

  /// Creates a gradient logo container from an image path
  Widget toGradientLogoContainer({
    double? width,
    double? height,
    LinearGradient? gradient,
    BoxFit fit = BoxFit.contain,
    EdgeInsets? padding,
  }) {
    return LogoGradientGenerator.createGradientLogoContainer(
      imagePath: this,
      width: width,
      height: height,
      gradient: gradient,
      fit: fit,
      padding: padding,
    );
  }
}
