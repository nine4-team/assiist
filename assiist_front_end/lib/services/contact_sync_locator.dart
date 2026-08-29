import 'package:assiist_front_end/services/contact_sync_service.dart';

/// Simple singleton locator to provide a globally accessible ContactSyncService
/// without introducing a DI framework in this snippet.
class ContactSyncServiceLocator {
  ContactSyncServiceLocator._();
  static final ContactSyncServiceLocator instance =
      ContactSyncServiceLocator._();

  late ContactSyncService syncService;

  void register(ContactSyncService service) {
    syncService = service;
  }
}
