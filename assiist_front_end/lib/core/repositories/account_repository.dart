import 'package:assiist_front_end/core/models/account_details.dart';

/// Abstract repository for managing account-level operations.
abstract class AccountRepository {
  /// Gets the account ID for the current user.
  ///
  /// Returns the account ID as a string.
  /// Throws an [ApiException] or its subclasses if the operation fails.
  Future<String> getAccountId();

  /// Fetches the account's details (business description and type).
  ///
  /// Returns [AccountDetailsResponse] containing the details.
  /// Returns null or throws an exception upon failure, depending on implementation strategy.
  Future<AccountDetailsResponse?> getAccountDetails();

  /// Updates the account's details (business description and/or type).
  ///
  /// Takes an [AccountDetailsUpdateRequest] object.
  /// Returns the updated [AccountDetailsResponse].
  /// Throws an [ApiException] or its subclasses if the operation fails.
  Future<AccountDetailsResponse> updateAccountDetails(
    AccountDetailsUpdateRequest request,
  );

  /// Gets the account's business description.
  ///
  /// Returns the business description string, or null if not set.
  Future<String?> getBusinessDescription();

  /// Updates the account's business description.
  ///
  /// Throws an [ApiException] or its subclasses if the operation fails.
  Future<void> updateBusinessDescription(String description);

  /// Gets the account's business type.
  ///
  /// Returns the business type string, or null if not set.
  Future<String?> getBusinessType();

  /// Updates the account's business type.
  ///
  /// Throws an [ApiException] or its subclasses if the operation fails.
  Future<void> updateBusinessType(String type);
}
