import 'dart:convert';

/// Utility class for handling text encoding issues
class TextEncodingUtils {
  /// Fixes UTF-8 encoding issues that can occur when Firestore data
  /// is incorrectly decoded as Latin-1 instead of UTF-8.
  ///
  /// This commonly happens with emojis and special characters like apostrophes.
  ///
  /// Returns the properly decoded UTF-8 string, or the original if fixing fails.
  static String? fixUtf8String(dynamic rawString) {
    if (rawString is! String || rawString.isEmpty) return rawString;

    try {
      // Convert the incorrectly decoded string back to bytes, then properly decode as UTF-8
      final bytes = rawString.codeUnits.map((unit) => unit & 0xFF).toList();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      // If UTF-8 fix fails, return the original string
      return rawString;
    }
  }

  /// Convenience method to fix UTF-8 encoding and provide a default value
  static String fixUtf8StringWithDefault(
    dynamic rawString,
    String defaultValue,
  ) {
    return fixUtf8String(rawString) ?? defaultValue;
  }

  /// Recursively fixes UTF-8 encoding issues in an entire JSON object.
  /// This automatically handles Maps, Lists, and nested structures.
  ///
  /// Usage:
  /// ```dart
  /// factory MyModel.fromJson(Map<String, dynamic> json) {
  ///   final fixedJson = TextEncodingUtils.fixUtf8InJson(json);
  ///   return MyModel(
  ///     name: fixedJson['name'] as String?,
  ///     description: fixedJson['description'] as String?,
  ///     // ... other fields
  ///   );
  /// }
  /// ```
  static dynamic fixUtf8InJson(dynamic json) {
    if (json is String) {
      return fixUtf8String(json);
    } else if (json is Map<String, dynamic>) {
      return json.map((key, value) => MapEntry(key, fixUtf8InJson(value)));
    } else if (json is List) {
      return json.map((item) => fixUtf8InJson(item)).toList();
    } else {
      // For non-string, non-Map, non-List values (numbers, booleans, null, etc.)
      return json;
    }
  }
}
