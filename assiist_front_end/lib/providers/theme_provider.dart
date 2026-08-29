import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Enum representing the three theme modes we want to support in the UI.
enum AppThemeMode { system, light, dark }

class ThemeModeNotifier extends StateNotifier<AppThemeMode> {
  static const _prefsKey = 'app_theme_mode';

  ThemeModeNotifier() : super(AppThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored != null) {
      state = AppThemeMode.values.firstWhere(
        (e) => e.name == stored,
        orElse: () => AppThemeMode.system,
      );
    }
  }

  Future<void> set(AppThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }

  /// Convenience helpers
  bool get isDark => resolvedBrightness == Brightness.dark;

  Brightness get resolvedBrightness {
    if (state == AppThemeMode.light) return Brightness.light;
    if (state == AppThemeMode.dark) return Brightness.dark;
    // System
    return WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, AppThemeMode>(
      (ref) => ThemeModeNotifier(),
    );
