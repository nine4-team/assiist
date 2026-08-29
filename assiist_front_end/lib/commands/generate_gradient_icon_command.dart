import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../theme/app_styles.dart';

/// Command to generate a gradient-enhanced app icon for TestFlight
/// This can be called from within the Flutter app
class GenerateGradientIconCommand {
  /// Generates a gradient-enhanced version of the app icon
  static Future<bool> generateGradientIcon() async {
    try {
      print('🎨 Generating gradient-enhanced app icon...');

      // Load the white logo image from assets
      const String inputPath = 'assets/images/app_icon_white.png';
      final ByteData imageData = await rootBundle.load(inputPath);
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

      print('📐 Image dimensions: ${width.toInt()}x${height.toInt()}');

      // Draw the original white logo
      canvas.drawImage(originalImage, Offset.zero, Paint());

      // Create gradient shader using the app's gradient
      final Rect gradientRect = Rect.fromLTWH(0, 0, width, height);
      final Paint gradientPaint =
          Paint()
            ..shader = AppStyles.gradientAccent.createShader(gradientRect)
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

      // Save the file to the iOS app icon location
      final String outputPath =
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png';
      final File outputFile = File(outputPath);

      await outputFile.writeAsBytes(pngBytes.buffer.asUint8List());

      print('✅ Successfully generated gradient app icon!');
      print('📁 Saved to: $outputPath');
      print('🚀 Your app icon is ready for TestFlight deployment!');

      return true;
    } catch (e) {
      print('❌ Error generating gradient icon: $e');
      return false;
    }
  }
}
