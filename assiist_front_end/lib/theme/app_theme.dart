import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_styles.dart';

/// Centralized theme definitions for the Assiist app.
///
/// We expose two `CupertinoThemeData` objects – one for light mode, one for dark.
/// They are built on top of a shared `ColorScheme` so that Material widgets added
/// later will automatically inherit our palette.
///
/// If you need an additional color, add it to the colour scheme and then surface
/// a convenient getter inside [AppThemeExtensions].
class AppTheme {
  // ---- Base palette ------------------------------------------------------- //

  static const _primary = Color(
    0xFFDAA520,
  ); // matches AppStyles.solidAccent - rich goldenrod
  static const _secondary = Color(0xfff47324);
  static const _tertiary = Color(0xff5a6cea);

  // ---- Light colour scheme ----------------------------------------------- //

  static const _lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: _primary,
    onPrimary: CupertinoColors.white,
    secondary: _secondary,
    onSecondary: CupertinoColors.white,
    tertiary: _tertiary,
    onTertiary: CupertinoColors.white,
    error: CupertinoColors.destructiveRed,
    onError: CupertinoColors.white,
    background: CupertinoColors.systemGroupedBackground,
    onBackground: CupertinoColors.black,
    surface: CupertinoColors.white,
    onSurface: CupertinoColors.black,
  );

  static final lightCupertino = CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: AppStyles.solidAccent,
    barBackgroundColor: _lightColorScheme.background,
    scaffoldBackgroundColor: _lightColorScheme.background,
  );

  // ---- Dark colour scheme ------------------------------------------------- //

  static const _darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: _primary,
    onPrimary: CupertinoColors.white,
    secondary: _secondary,
    onSecondary: CupertinoColors.white,
    tertiary: _tertiary,
    onTertiary: CupertinoColors.white,
    error: CupertinoColors.destructiveRed,
    onError: CupertinoColors.white,
    background: CupertinoColors.black,
    onBackground: CupertinoColors.white,
    surface: CupertinoColors.darkBackgroundGray,
    onSurface: CupertinoColors.white,
  );

  static final darkCupertino = CupertinoThemeData(
    brightness: Brightness.dark,
    primaryColor: AppStyles.solidAccent,
    barBackgroundColor: _darkColorScheme.background,
    scaffoldBackgroundColor: _darkColorScheme.background,
  );
}
