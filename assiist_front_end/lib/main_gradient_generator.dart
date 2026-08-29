import 'dart:io';
import 'package:flutter/material.dart';
import 'commands/generate_gradient_icon_command.dart';

/// Simple app to generate gradient-enhanced app icons
/// Run this with: flutter run lib/main_gradient_generator.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Generate the gradient icon
  final success = await GenerateGradientIconCommand.generateGradientIcon();

  if (success) {
    print('\n🎉 Gradient icon generation completed successfully!');
    print('You can now build your iOS app for TestFlight deployment.');
  } else {
    print('\n❌ Gradient icon generation failed.');
    print('Please check the error messages above.');
  }

  // Exit the app
  exit(0);
}
