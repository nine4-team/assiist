// Only needed for potential future @visibleForTesting

/// Formats a phone number string into common US formats.
///
/// Returns the formatted number or the original string if the format is unknown.
/// Returns an empty string if the input is null or empty.
String formatPhoneNumber(String? phone) {
  if (phone == null || phone.isEmpty) return '';
  // Use double backslash for regex literal in Dart string
  final digits = phone.replaceAll(RegExp(r'\D'), '');

  if (digits.length == 10) {
    // (XXX) XXX-XXXX
    return '(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}';
  } else if (digits.length == 11 && digits.startsWith('1')) {
    // +1 (XXX) XXX-XXXX
    return '+1 (${digits.substring(1, 4)}) ${digits.substring(4, 7)}-${digits.substring(7)}';
  }
  // Add more formats if needed, otherwise return cleaned or original
  return phone; // Fallback to original if format unknown
}

/// Builds a subtitle string combining email and a formatted phone number.
///
/// Separates email and phone with a bullet point (' • ').
/// Returns 'No contact info' if both email and phone are null or empty.
String buildSubtitleText(String? email, String? phone) {
  final formattedPhone = formatPhoneNumber(phone); // Use the function above
  final parts = [
    if (email != null && email.isNotEmpty) email,
    if (formattedPhone.isNotEmpty) formattedPhone,
  ];
  if (parts.isEmpty) return 'No contact info';
  // Use double backslash for unicode character in Dart string
  return parts.join(' \u2022 '); // Join with a bullet point
}
