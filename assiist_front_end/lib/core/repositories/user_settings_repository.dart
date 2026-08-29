/// Abstract repository for managing user settings.
abstract class UserSettingsRepository {
  /// Gets the list of ignored email addresses.
  ///
  /// Returns a list of email addresses that the user has chosen to ignore.
  /// Throws an [ApiException] or its subclasses if the operation fails.
  Future<List<String>> getIgnoredEmailsList();

  /// Removes an email address from the ignored list.
  ///
  /// Throws an [ApiException] or its subclasses if the operation fails.
  Future<void> removeIgnoredEmail(String email);

  /// Saves the user's contact synchronization settings.
  ///
  /// [source] can be null if no source is selected.
  /// [priority] determines how conflicts are resolved.
  /// Throws an [ApiException] or its subclasses if the operation fails.
  Future<void> saveContactSyncSettings(String? source, String priority);

  /// Retrieves the user's contact synchronization settings.
  ///
  /// Returns a map containing 'source' and 'priority' keys, or null if no settings exist.
  /// Throws an [ApiException] or its subclasses if the operation fails.
  Future<Map<String, String>?> getContactSyncSettings();

  /// Saves the user's business description.
  ///
  /// Throws an [ApiException] or its subclasses if the operation fails.
  Future<void> saveBusinessDescription(String description);

  /// Retrieves the user's business description.
  ///
  /// Returns the business description string, or null if not set.
  Future<String?> getBusinessDescription();
}
