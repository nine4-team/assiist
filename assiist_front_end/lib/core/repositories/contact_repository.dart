import 'package:assiist_front_end/core/models/contact.dart';

/// Abstract interface for contact data operations.
/// This defines the contract for fetching and manipulating contact data,
/// regardless of the underlying data source (Firestore, dummy data, etc.).
abstract class ContactRepository {
  /// Retrieves a single contact by its unique ID.
  /// Returns null if the contact is not found or access is denied.
  Future<Contact?> getContactById(String contactId);

  /// Searches for contacts based on a query string.
  /// The query might match name, email, phone, company, etc.
  /// Returns a list of matching contacts.
  Future<List<Contact>> searchContacts(String query);

  /// Creates a new contact.
  /// Takes a Contact object (likely without an ID initially) and saves it.
  /// Returns the created contact, possibly with the generated ID.
  Future<Contact> createContact(Contact contact);

  /// Updates an existing contact.
  /// Takes the contact ID and a map of fields to update.
  /// Returns the updated contact or null if the update fails.
  Future<Contact?> updateContact(
    String contactId,
    Map<String, dynamic> updates,
  );

  /// Deletes a contact (likely a soft delete).
  /// Returns true if successful, false otherwise.
  Future<bool> deleteContact(String contactId);

  /// Retrieves all contacts for the current authenticated user.
  /// Supports pagination using limit and offset.
  Future<List<Contact>> getAllContactsForUser({int limit = 50, int offset = 0});

  /// Updates the last contacted date for a contact.
  /// Returns true if successful, false otherwise.
  Future<bool> updateLastContacted(String contactId);

  /// Performs incremental contact sync.
  /// Sends client changes and receives server changes.
  /// Returns the parsed response as a Map (caller will convert to models).
  Future<Map<String, dynamic>> postIncrementalSync(
    Map<String, dynamic> payload,
  );

  // TODO: Add methods for fetching contacts by account/user if needed for listing views.
  // Future<List<Contact>> getContactsByUser(String userId, {int limit, int offset});
}
