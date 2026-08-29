import 'dart:async';

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter/foundation.dart';

import 'package:assiist_front_end/services/contact_sync_locator.dart';

/// Listens to native contact-store changes and triggers incremental sync.
class ContactChangeDetector {
  static final ContactChangeDetector _instance = ContactChangeDetector._();
  ContactChangeDetector._();
  factory ContactChangeDetector() => _instance;

  Future<void> start() async {
    if (!await FlutterContacts.requestPermission()) {
      debugPrint('[ContactChangeDetector] Permission denied – not starting');
      return;
    }

    FlutterContacts.addListener(() async {
      debugPrint('[ContactChangeDetector] Detected native contact change');
      await ContactSyncServiceLocator.instance.syncService
          .performIncrementalSync();
    });
  }

  void stop() {
    // FlutterContacts listener currently cannot be removed without app restart.
  }
}
