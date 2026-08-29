import 'package:assiist_front_end/core/models/pending_contact.dart';

abstract class PendingContactRepository {
  /// Fetches pending contacts, optionally filtering by status.
  Future<List<PendingContact>> getPendingContacts({String status = 'pending'});

  /// Updates the status of a specific pending contact.
  Future<void> updatePendingContactStatus(String id, String status);
}
