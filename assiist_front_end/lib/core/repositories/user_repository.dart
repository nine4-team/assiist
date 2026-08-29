import 'package:assiist_front_end/core/models/pending_contact.dart'; // Use correct relative path

abstract class UserRepository {
  /// Fetches the list of pending contacts for the current user.
  Future<List<PendingContact>> getPendingContacts();
}
