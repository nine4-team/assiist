import 'package:flutter_contacts/flutter_contacts.dart' as native;
import 'package:assiist_front_end/core/models/contact.dart'
    as app; // Our app's Contact model
import 'package:assiist_front_end/core/repositories/contact_repository.dart';
import 'package:assiist_front_end/core/repositories/user_settings_repository.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart'; // add near imports
import 'package:shared_preferences/shared_preferences.dart'; // Added for incremental sync
// Potentially import other models or utilities as needed

class SyncPreviewData {
  final int toCreateOnServer; // Native contacts to be created on the server
  final int
  toCreateOnNative; // Server contacts to be created on the native device
  final int toCompareOrUpdate; // Pairs that will be compared for updates

  SyncPreviewData({
    required this.toCreateOnServer,
    required this.toCreateOnNative,
    required this.toCompareOrUpdate,
  });
}

class ContactSyncService {
  final ContactRepository _contactRepository;
  final UserSettingsRepository _settingsRepository;

  ContactSyncService({
    required ContactRepository contactRepository,
    required UserSettingsRepository settingsRepository,
  }) : _contactRepository = contactRepository,
       _settingsRepository = settingsRepository;

  Future<void> performTwoWaySync() async {
    // Configure flutter_contacts to include notes on iOS 13+
    // This is crucial for our sync strategy which uses the notes field.
    // Consider moving this to a more global app initialization spot if appropriate.
    native.FlutterContacts.config.includeNotesOnIos13AndAbove = false;

    // 0. Get sync settings (source, priority)
    final syncSettings = await _settingsRepository.getContactSyncSettings();
    if (syncSettings == null || syncSettings['source'] != 'ios') {
      print("Contact Sync: Not configured for iOS or settings not found.");
      return;
    }
    final String priority =
        syncSettings['priority'] ?? 'local_wins'; // Default priority

    // 1. Fetch all native contacts using our improved method
    print("Contact Sync: Fetching native contacts...");
    List<native.Contact> nativeContacts = await getDeviceContacts();
    print("Contact Sync: Found ${nativeContacts.length} native contacts.");

    // 3. Fetch all server contacts (Assiist contacts)
    print("Contact Sync: Fetching server contacts...");
    // TODO: Implement pagination for getAllContactsForUser if it returns a large list
    List<app.Contact> serverContacts =
        await _contactRepository.getAllContactsForUser();
    print("Contact Sync: Found ${serverContacts.length} server contacts.");

    // 4. Pre-process and index contacts using device UUID tracking
    // Index native contacts by device UUID (native ID)
    Map<String, native.Contact> nativeContactsByDeviceId = {};

    for (var nc in nativeContacts) {
      nativeContactsByDeviceId[nc.id] = nc;
    }

    // Index server contacts by Assiist ID and by device UUID
    Map<String, app.Contact> serverContactsByAssiistId = {
      for (var sc in serverContacts) sc.id: sc,
    };
    Map<String, app.Contact> serverContactsByDeviceUuid = {
      for (var sc in serverContacts)
        if (sc.device_contact_uuid != null) sc.device_contact_uuid!: sc,
    };

    // 5. Identify matched pairs and unmatched contacts using device UUID tracking
    List<SyncPair> pairsToCompare = [];
    List<native.Contact> nativeContactsToCreateOnServer = [];
    List<app.Contact> serverContactsToCreateOnNative = [];

    print(
      "Contact Sync: Device contacts found: ${nativeContactsByDeviceId.length}",
    );
    print(
      "Contact Sync: Server contacts with device UUIDs: ${serverContactsByDeviceUuid.length}",
    );

    // Debug: Print first few server contacts with UUIDs
    int debugCount = 0;
    for (var entry in serverContactsByDeviceUuid.entries) {
      if (debugCount < 3) {
        print(
          "  Server contact '${entry.value.displayName}' has device UUID: ${entry.key}",
        );
        debugCount++;
      }
    }

    // Iterate through native contacts to find matches or identify new contacts
    for (var deviceId in nativeContactsByDeviceId.keys) {
      native.Contact nc = nativeContactsByDeviceId[deviceId]!;

      if (serverContactsByDeviceUuid.containsKey(deviceId)) {
        // Found matching server contact by device UUID
        app.Contact sc = serverContactsByDeviceUuid[deviceId]!;
        pairsToCompare.add(SyncPair(nc, sc));
      } else {
        // No server contact found with this device UUID - create new on server
        nativeContactsToCreateOnServer.add(nc);
      }
    }

    // Iterate through server contacts to find those without device UUIDs (new to native)
    for (var scId in serverContactsByAssiistId.keys) {
      app.Contact sc = serverContactsByAssiistId[scId]!;
      if (sc.device_contact_uuid == null) {
        // Server contact has no device UUID - create new on native
        serverContactsToCreateOnNative.add(sc);
      }
      // If server contact has device UUID but we didn't find matching native contact above,
      // it means the native contact was deleted - we could handle this case if needed
    }

    print("Contact Sync: Pairs to compare: ${pairsToCompare.length}");
    print(
      "Contact Sync: Native contacts to create on server: ${nativeContactsToCreateOnServer.length}",
    );
    print(
      "Contact Sync: Server contacts to create on native: ${serverContactsToCreateOnNative.length}",
    );

    // 6. Process comparisons for matched pairs
    for (var pair in pairsToCompare) {
      await _compareAndUpdatePair(
        pair.nativeContact!,
        pair.appContact!,
        priority,
        nativeContactId: pair.nativeContact!.id,
      );
    }

    // 7. Create new contacts on server (from native)
    for (var nc in nativeContactsToCreateOnServer) {
      print("Sync: Creating native contact (Native ID: ${nc.id}) on server.");
      app.Contact newAppContact = _convertToAppContact(nc).copyWith(
        id: '', // Let server generate ID
        device_contact_uuid: nc.id, // Store device UUID for future syncing
        source: 'ios_device_sync_create',
      );

      try {
        await _contactRepository.createContact(
          newAppContact.copyWith(id: null),
        );
      } on DuplicateContactException catch (dup) {
        print(
          "Sync: Duplicate detected for device contact ${nc.id} → existing ${dup.existingContactId}",
        );
        try {
          final existing = await _contactRepository.getContactById(
            dup.existingContactId,
          );
          if (existing != null) {
            final Map<String, dynamic> updates = {};
            if (existing.device_contact_uuid == null) {
              updates['device_contact_uuid'] = nc.id;
            }
            if (updates.isNotEmpty) {
              await _contactRepository.updateContact(existing.id, updates);
            }
          }
        } catch (updateErr) {
          print('Sync: Failed to merge duplicate contact: $updateErr');
        }
      }
    }

    // 8. Create new contacts on native (from server) using batch approach
    if (serverContactsToCreateOnNative.isNotEmpty) {
      await _batchCreateContactsWithUuidTracking(
        serverContactsToCreateOnNative,
      );
    }

    print("Contact Sync: Two-way sync process completed.");
  }

  // ------------------------------------------------------------------
  // Lean incremental-sync implementation
  // ------------------------------------------------------------------
  Future<void> performIncrementalSync() async {
    // Use SharedPreferences to keep the timestamp locally
    final prefs = await SharedPreferences.getInstance();
    final lastSyncIso = prefs.getString('contacts_last_sync_ts');
    DateTime? lastSyncTs;
    if (lastSyncIso != null) {
      try {
        lastSyncTs = DateTime.parse(lastSyncIso);
      } catch (_) {}
    }

    // (Future work) Detect local changes since lastSyncTs.
    final List<Map<String, dynamic>> localChanges = [];

    final payload = {
      'last_sync_ts': lastSyncTs?.toIso8601String(),
      'client_changes': localChanges,
    };

    try {
      final Map<String, dynamic> response = await _contactRepository
          .postIncrementalSync(payload);
      final List<dynamic> serverChangesRaw = response['server_changes'] ?? [];

      for (final change in serverChangesRaw) {
        if (change is Map<String, dynamic>) {
          final serverContact = app.Contact.fromJson(change);

          if (serverContact.is_deleted) {
            // Never delete native contact. Optionally archive or ignore.
            continue;
          }

          // TODO: Upsert serverContact into local database (not yet implemented)
          // For now, just print to console.
          print(
            '[ContactSync] Received server change: ${serverContact.displayName}',
          );
        }
      }

      // Update timestamp
      await prefs.setString(
        'contacts_last_sync_ts',
        DateTime.now().toIso8601String(),
      );
      print('[ContactSync] Incremental sync completed.');
    } catch (e) {
      print('[ContactSync] Incremental sync failed: $e');
    }
  }

  Future<List<native.Contact>> getDeviceContacts() async {
    try {
      print("[ContactSync] Configuring FlutterContacts...");
      native.FlutterContacts.config.includeNotesOnIos13AndAbove =
          false; // Changed to false for iOS 18 entitlement issue
      native.FlutterContacts.config.returnUnifiedContacts =
          true; // Make sure we get unified contacts

      // REMOVED: Don't let flutter_contacts handle permissions - we do this in the wizard
      // bool hasPermission = await native.FlutterContacts.requestPermission();
      // print("[ContactSync] Permission status: $hasPermission");

      // if (!hasPermission) {
      //   print("[ContactSync] Permission denied for contacts");
      //   return [];
      // }

      print("[ContactSync] Fetching all contacts with properties...");
      List<native.Contact> contacts = await native.FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: true,
        withThumbnail: false,
        withGroups: false,
        withAccounts: false,
      );

      print("[ContactSync] Successfully fetched ${contacts.length} contacts");
      if (contacts.isNotEmpty) {
        print("[ContactSync] First contact details (example):");
        var firstContact = contacts.first;
        print("  - Name: ${firstContact.displayName}");
        print("  - ID: ${firstContact.id}");
        print("  - Has phones: ${firstContact.phones.length > 0}");
        print("  - Has emails: ${firstContact.emails.length > 0}");
        print("  - Has notes: ${firstContact.notes.length > 0}");
      }

      return contacts;
    } catch (e, stackTrace) {
      print("[ContactSync] Error fetching contacts: $e");
      print("[ContactSync] Stack trace: $stackTrace");
      return [];
    }
  }

  Future<SyncPreviewData> getSyncPreview() async {
    native.FlutterContacts.config.includeNotesOnIos13AndAbove =
        false; // Changed to false for iOS 18 entitlement issue

    // REMOVED: Don't let flutter_contacts handle permissions - we do this in the wizard
    // bool hasPermission = await native.FlutterContacts.requestPermission();
    // print("Contact Sync Preview: Permission check result: $hasPermission");

    // 1. Fetch native contacts
    // Permission should ideally be confirmed before this point by the UI flow.
    // getContacts itself might re-request if needed and not granted.
    print("Contact Sync Preview: Fetching native contacts...");

    try {
      // Using the new method that tries multiple approaches
      List<native.Contact> nativeContacts = await getDeviceContacts();

      print(
        "Contact Sync Preview: Found ${nativeContacts.length} native contacts.",
      );

      // Print some details about the first few contacts if any
      if (nativeContacts.isNotEmpty) {
        print("Contact Sync Preview: First contact details:");
        // Show details for up to 3 contacts
        for (
          int i = 0;
          i < (nativeContacts.length > 3 ? 3 : nativeContacts.length);
          i++
        ) {
          final contact = nativeContacts[i];
          print("  Contact #$i: ${contact.displayName}, ID: ${contact.id}");
          print("    Phone numbers: ${contact.phones.length}");
          print("    Emails: ${contact.emails.length}");
          print("    Notes: ${contact.notes.length}");
        }
      } else {
        print("Contact Sync Preview: No native contacts found.");
        // REMOVED: Permission status debug print since we removed hasPermission
        // print("  - Permission status: $hasPermission");
        // Try to get just one contact to test functionality
        try {
          final testContact = await native.FlutterContacts.openExternalPick();
          print(
            "  - External pick test: ${testContact != null ? 'SUCCESS' : 'NULL result'}",
          );
        } catch (e) {
          print("  - External pick test error: $e");
        }
      }

      // 2. Fetch all server contacts (Assiist contacts)
      print("Contact Sync Preview: Fetching server contacts...");
      List<app.Contact> serverContacts =
          await _contactRepository.getAllContactsForUser();
      print(
        "Contact Sync Preview: Found ${serverContacts.length} server contacts.",
      );

      // 3. Pre-process and index contacts using UUID-based matching (same as performTwoWaySync)
      Map<String, native.Contact> nativeContactsByDeviceId = {};
      for (var nc in nativeContacts) {
        nativeContactsByDeviceId[nc.id] = nc;
      }

      // Index server contacts by Assiist ID and by device UUID
      Map<String, app.Contact> serverContactsByAssiistId = {
        for (var sc in serverContacts) sc.id: sc,
      };
      Map<String, app.Contact> serverContactsByDeviceUuid = {
        for (var sc in serverContacts)
          if (sc.device_contact_uuid != null) sc.device_contact_uuid!: sc,
      };

      // 4. Identify matched pairs and unmatched contacts using UUID-based matching
      List<SyncPair> pairsToCompare = [];
      List<native.Contact> nativeContactsToCreateOnServer = [];
      List<app.Contact> serverContactsToCreateOnNative = [];

      // Iterate through native contacts to find matches or identify new contacts
      for (var deviceId in nativeContactsByDeviceId.keys) {
        native.Contact nc = nativeContactsByDeviceId[deviceId]!;

        if (serverContactsByDeviceUuid.containsKey(deviceId)) {
          // Found matching server contact by device UUID
          app.Contact sc = serverContactsByDeviceUuid[deviceId]!;
          pairsToCompare.add(SyncPair(nc, sc));
        } else {
          // No server contact found with this device UUID - create new on server
          nativeContactsToCreateOnServer.add(nc);
        }
      }

      // Iterate through server contacts to find those without device UUIDs (new to native)
      for (var scId in serverContactsByAssiistId.keys) {
        app.Contact sc = serverContactsByAssiistId[scId]!;
        if (sc.device_contact_uuid == null) {
          // Server contact has no device UUID - create new on native
          serverContactsToCreateOnNative.add(sc);
        }
      }

      print("Contact Sync Preview: Pairs to compare: ${pairsToCompare.length}");
      print(
        "Contact Sync Preview: Native contacts to create on server: ${nativeContactsToCreateOnServer.length}",
      );
      print(
        "Contact Sync Preview: Server contacts to create on native: ${serverContactsToCreateOnNative.length}",
      );

      return SyncPreviewData(
        toCreateOnServer: nativeContactsToCreateOnServer.length,
        toCreateOnNative: serverContactsToCreateOnNative.length,
        toCompareOrUpdate: pairsToCompare.length,
      );
    } catch (e) {
      print("Error in getSyncPreview: $e");
      return SyncPreviewData(
        toCreateOnServer: 0,
        toCreateOnNative: 0,
        toCompareOrUpdate: 0,
      );
    }
  }

  app.Contact _convertToAppContact(native.Contact nativeContact) {
    return app.Contact(
      id: '', // Let server generate new ID for new contacts
      device_contact_uuid: nativeContact.id, // Store the device contact UUID
      first_name: nativeContact.name.first,
      last_name: nativeContact.name.last,
      addressed_as: nativeContact.name.nickname,
      business_name:
          nativeContact.organizations.isNotEmpty
              ? nativeContact.organizations.first.company
              : null,
      phone_numbers:
          nativeContact.phones
              .map(
                (p) => app.PhoneNumber(
                  label: p.label.toString().split('.').last,
                  number: p.number,
                ),
              )
              .toList(),
      emails:
          nativeContact.emails
              .map(
                (e) => app.EmailAddress(
                  label: e.label.toString().split('.').last,
                  address: e.address,
                ),
              )
              .toList(),
      addresses:
          nativeContact.addresses
              .map(
                (a) => app.Address(
                  street: a.street,
                  city: a.city,
                  state: a.state,
                  zip: a.postalCode,
                  country: a.country,
                ),
              )
              .toList(),
      relationship_details: {}, // Add empty map instead of null
      tags: [], // Add empty list instead of null
      source: 'ios_device',
      updated_on: DateTime.now(), // Set current timestamp for new contacts
      is_deleted: false,
    );
  }

  // Helper method to convert app Contact to native Contact
  native.Contact _convertToNative(app.Contact appContact) {
    // Convert phone numbers
    List<native.Phone> nativePhones = [];
    if (appContact.phone_numbers != null &&
        appContact.phone_numbers!.isNotEmpty) {
      nativePhones.addAll(
        appContact.phone_numbers!.map((p_app) {
          native.PhoneLabel label = native.PhoneLabel.custom;
          try {
            if (p_app.label != null) {
              label = native.PhoneLabel.values.firstWhere(
                (e_label) =>
                    e_label.toString().split('.').last ==
                    p_app.label!.toLowerCase(),
              );
            }
          } catch (_) {}
          return native.Phone(p_app.number ?? '', label: label);
        }).toList(),
      );
    }

    // Convert email addresses
    List<native.Email> nativeEmails = [];
    if (appContact.emails != null && appContact.emails!.isNotEmpty) {
      nativeEmails.addAll(
        appContact.emails!.map((e_app) {
          native.EmailLabel label = native.EmailLabel.custom;
          try {
            if (e_app.label != null) {
              label = native.EmailLabel.values.firstWhere(
                (e_label) =>
                    e_label.toString().split('.').last ==
                    e_app.label!.toLowerCase(),
              );
            }
          } catch (_) {}
          return native.Email(e_app.address ?? '', label: label);
        }).toList(),
      );
    }

    // Convert addresses
    List<native.Address> nativeAddresses = [];
    if (appContact.addresses != null && appContact.addresses!.isNotEmpty) {
      nativeAddresses.addAll(
        appContact.addresses!.map((a_app) {
          return native.Address(
            (a_app.street ?? '') +
                (a_app.city == null ? '' : ', ${a_app.city}') +
                (a_app.state == null ? '' : ', ${a_app.state}'),
            street: a_app.street ?? '',
            city: a_app.city ?? '',
            state: a_app.state ?? '',
            postalCode: a_app.zip ?? '',
            country: a_app.country ?? '',
          );
        }).toList(),
      );
    }

    // Create deep link URL to Assiist contact record
    List<native.Website> nativeWebsites = [];
    if (appContact.id.isNotEmpty) {
      // Create deep link URL that opens the contact in Assiist app
      String deepLinkUrl = 'assiist://contact/${appContact.id}';
      nativeWebsites.add(
        native.Website(deepLinkUrl, label: native.WebsiteLabel.other),
      );
    }

    return native.Contact(
      name: native.Name(
        first: appContact.first_name ?? '',
        last: appContact.last_name ?? '',
        nickname: appContact.addressed_as ?? '',
      ),
      organizations:
          appContact.business_name != null &&
                  appContact.business_name!.isNotEmpty
              ? [
                native.Organization(
                  company: appContact.business_name!,
                  title: '',
                ),
              ]
              : [],
      phones: nativePhones,
      emails: nativeEmails,
      addresses: nativeAddresses,
      websites: nativeWebsites, // Add deep link URL
      // Note: Removed notes field since we can't write to it without entitlement
      // The device UUID tracking handles sync identification instead
    );
  }

  // Helper method for formatting Assiist data into native notes
  String _formatAssiistDataForNativeNotes(app.Contact contact) {
    final StringBuffer notesBuffer = StringBuffer();

    notesBuffer.writeln("### Assiist Data Start ###");

    if (contact.personal_details != null) {
      // TODO: Implement proper JSON serialization for complex objects
      notesBuffer.writeln(
        "Personal Details: ${contact.personal_details.toString()}",
      );
    }
    if (contact.relationship_details != null &&
        contact.relationship_details!.isNotEmpty) {
      // TODO: Implement proper JSON serialization for complex objects
      notesBuffer.writeln(
        "Relationship Details: ${contact.relationship_details.toString()}",
      );
    }
    if (contact.business_details != null) {
      // TODO: Implement proper JSON serialization for complex objects
      notesBuffer.writeln(
        "Business Details: ${contact.business_details.toString()}",
      );
    }

    notesBuffer.writeln("Last Synced Assiist ID: ${contact.id}");
    if (contact.updated_on != null) {
      notesBuffer.writeln(
        "Assiist Last Modified: ${contact.updated_on!.toIso8601String()}",
      );
    }
    notesBuffer.writeln("### Assiist Data End ###");
    return notesBuffer.toString();
  }

  // Helper method to merge Assiist data with existing user notes
  String _mergeNotesWithAssiistData(
    String? existingNotes,
    app.Contact contact,
  ) {
    if (existingNotes == null || existingNotes.isEmpty) {
      return _formatAssiistDataForNativeNotes(contact);
    }

    // Remove any existing Assiist data block
    String userNotes = _removeAssiistDataFromNotes(existingNotes);

    // Add new Assiist data
    String assiistData = _formatAssiistDataForNativeNotes(contact);

    // Combine user notes with Assiist data
    if (userNotes.trim().isEmpty) {
      return assiistData;
    } else {
      return "$userNotes\n\n$assiistData";
    }
  }

  // Helper method to remove Assiist data block from notes while preserving user notes
  String _removeAssiistDataFromNotes(String notesContent) {
    final lines = notesContent.split('\n');
    final List<String> userLines = [];
    bool inAssiistBlock = false;

    for (String line in lines) {
      if (line.trim() == "### Assiist Data Start ###") {
        inAssiistBlock = true;
        continue;
      }
      if (line.trim() == "### Assiist Data End ###") {
        inAssiistBlock = false;
        continue;
      }

      if (!inAssiistBlock) {
        userLines.add(line);
      }
    }

    return userLines.join('\n').trim();
  }

  // Helper method for parsing Assiist data from native notes
  Map<String, dynamic> _parseAssiistDataFromNativeNotes(String notesContent) {
    final Map<String, dynamic> parsedData = {};
    final lines = notesContent.split('\n');
    bool inAssiistBlock = false;

    for (String line in lines) {
      if (line.trim() == "### Assiist Data Start ###") {
        inAssiistBlock = true;
        continue;
      }
      if (line.trim() == "### Assiist Data End ###") {
        inAssiistBlock = false;
        break;
      }

      if (inAssiistBlock) {
        if (line.startsWith("Personal Details: ")) {
          parsedData['personal_details_str'] = line.substring(
            "Personal Details: ".length,
          );
        } else if (line.startsWith("Relationship Details: ")) {
          parsedData['relationship_details_str'] = line.substring(
            "Relationship Details: ".length,
          );
        } else if (line.startsWith("Business Details: ")) {
          parsedData['business_details_str'] = line.substring(
            "Business Details: ".length,
          );
        } else if (line.startsWith("Last Synced Assiist ID: ")) {
          parsedData['assiist_id'] = line.substring(
            "Last Synced Assiist ID: ".length,
          );
        } else if (line.startsWith("Assiist Last Modified: ")) {
          final dateString = line.substring("Assiist Last Modified: ".length);
          parsedData['assiist_last_modified_at'] = DateTime.tryParse(
            dateString,
          );
        }
      }
    }
    return parsedData;
  }

  // Helper method to compare a pair and decide on updates using device UUID tracking
  Future<void> _compareAndUpdatePair(
    native.Contact nativeContact, // This is the contact from flutter_contacts
    app.Contact appContact, // This is our app's contact model
    String priority, { // 'local_wins' or 'remote_wins' (device is local)
    required String
    nativeContactId, // The actual ID from flutter_contacts plugin
  }) async {
    // For now, use simple timestamp comparison or priority-based resolution
    // Since we can't rely on notes for native timestamps, we'll use server timestamps
    DateTime? serverLastModified = appContact.updated_on;

    // For simplicity, default to server wins unless priority specifies otherwise
    // This can be enhanced later with more sophisticated conflict resolution
    bool nativeIsSourceOfTruth = (priority == 'local_wins');

    // If server contact was recently updated, prefer server version
    if (serverLastModified != null) {
      final now = DateTime.now();
      final hoursSinceUpdate = now.difference(serverLastModified).inHours;
      if (hoursSinceUpdate < 24) {
        nativeIsSourceOfTruth = false; // Server wins if updated recently
      }
    }

    if (nativeIsSourceOfTruth) {
      // Native is newer or wins by priority: Update server contact
      print(
        "Sync: Native wins for contact ID (Assiist): ${appContact.id}, (Native): $nativeContactId. Updating server.",
      );
      app.Contact updatedAppContact = _convertToAppContact(
        nativeContact,
      ).copyWith(
        id: appContact.id, // Preserve original server ID!
        source: 'ios_device_sync_update',
      );
      await _contactRepository.updateContact(
        updatedAppContact.id,
        updatedAppContact.toJson(),
      );
    } else {
      // Server is newer or wins by priority: Update native contact
      print(
        "Sync: Server wins for contact ID (Assiist): ${appContact.id}, (Native): $nativeContactId. Updating native.",
      );

      // Convert appContact to a native.Contact representation
      native.Contact desiredNativeState = _convertToNative(appContact);

      // Modify the existing nativeContact object (which has the correct ID)
      // with the fields from desiredNativeState.
      nativeContact.name = desiredNativeState.name;
      nativeContact.phones = desiredNativeState.phones;
      nativeContact.emails = desiredNativeState.emails;
      nativeContact.addresses = desiredNativeState.addresses;
      nativeContact.organizations = desiredNativeState.organizations;
      nativeContact.websites =
          desiredNativeState.websites; // Include deep link URL
      nativeContact.socialMedias = desiredNativeState.socialMedias;
      nativeContact.events = desiredNativeState.events;
      // Note: We're not updating notes since we can't write to them without entitlement

      await nativeContact
          .update(); // Call update() on the modified nativeContact object
    }
  }

  /// Batch create contacts with UUID tracking using performance-optimized re-query approach
  /// Implements the solution from contact_sync_uuid_issue.md
  Future<void> _batchCreateContactsWithUuidTracking(
    List<app.Contact> serverContacts,
  ) async {
    print(
      "Sync: Starting batch contact creation for ${serverContacts.length} contacts",
    );

    // Step 1: Pre-insertion snapshot - get baseline device contact IDs
    print("Sync: Getting baseline device contact IDs...");
    List<native.Contact> existingContacts = await getDeviceContacts();
    Set<String> existingContactIds = existingContacts.map((c) => c.id).toSet();
    print("Sync: Found ${existingContactIds.length} existing device contacts");

    // Step 2: Batch contact insertion - insert all server contacts to device
    print("Sync: Inserting ${serverContacts.length} contacts to device...");
    List<app.Contact> insertedServerContacts = [];

    for (var sc in serverContacts) {
      try {
        print(
          "Sync: Creating server contact (Assiist ID: ${sc.id}) on native device",
        );
        native.Contact newNativeContact = _convertToNative(sc);
        await newNativeContact.insert();
        insertedServerContacts.add(sc);
        print("Sync: Successfully inserted contact: ${sc.displayName}");
      } catch (e) {
        print("Sync: ERROR inserting contact ${sc.displayName}: $e");
        // Continue with other contacts even if one fails
      }
    }

    print(
      "Sync: Successfully inserted ${insertedServerContacts.length} contacts",
    );

    // Step 3: Post-insertion identification - get only NEW contacts
    print("Sync: Identifying newly created device contacts...");
    List<native.Contact> allCurrentContacts = await getDeviceContacts();
    List<native.Contact> newlyCreatedContacts =
        allCurrentContacts
            .where((contact) => !existingContactIds.contains(contact.id))
            .toList();

    print(
      "Sync: Found ${newlyCreatedContacts.length} newly created device contacts",
    );

    // Step 4: Smart UUID matching - match server contacts to device contacts
    print("Sync: Matching server contacts to device contacts...");
    Map<String, String> serverIdToDeviceUuid = {};
    List<String> unmatchedServerIds = [];

    for (var serverContact in insertedServerContacts) {
      native.Contact? matchedDeviceContact = _findMatchingDeviceContact(
        serverContact,
        newlyCreatedContacts,
      );

      if (matchedDeviceContact != null) {
        serverIdToDeviceUuid[serverContact.id] = matchedDeviceContact.id;
        print(
          "Sync: Matched '${serverContact.displayName}' -> UUID: ${matchedDeviceContact.id}",
        );
      } else {
        unmatchedServerIds.add(serverContact.id);
        print(
          "Sync: WARNING - Could not match server contact: ${serverContact.displayName}",
        );
      }
    }

    print("Sync: Successfully matched ${serverIdToDeviceUuid.length} contacts");
    if (unmatchedServerIds.isNotEmpty) {
      print(
        "Sync: WARNING - ${unmatchedServerIds.length} contacts could not be matched",
      );
    }

    // Step 5: Bulk server updates - update all server contacts with device UUIDs
    print("Sync: Updating server contacts with device UUIDs...");
    int successfulUpdates = 0;
    int failedUpdates = 0;

    for (var entry in serverIdToDeviceUuid.entries) {
      String serverId = entry.key;
      String deviceUuid = entry.value;

      try {
        app.Contact? serverContact =
            insertedServerContacts.where((sc) => sc.id == serverId).firstOrNull;

        if (serverContact != null) {
          app.Contact updatedServerContact = serverContact.copyWith(
            device_contact_uuid: deviceUuid,
            source: 'ios_device_sync_create',
            updated_on: DateTime.now(),
          );

          await _contactRepository.updateContact(
            serverId,
            updatedServerContact.toJson(),
          );

          successfulUpdates++;
          print(
            "Sync: Updated server contact ${serverId} with UUID: $deviceUuid",
          );
        }
      } catch (e) {
        failedUpdates++;
        print("Sync: ERROR updating server contact $serverId: $e");
        // Continue with other updates even if one fails
      }
    }

    // Summary
    print("Sync: Batch contact creation completed");
    print("  - Contacts inserted: ${insertedServerContacts.length}");
    print("  - Contacts matched: ${serverIdToDeviceUuid.length}");
    print("  - Server updates successful: $successfulUpdates");
    print("  - Server updates failed: $failedUpdates");

    if (unmatchedServerIds.isNotEmpty) {
      print("  - Unmatched server contact IDs: $unmatchedServerIds");
    }
  }

  /// Find matching device contact for a server contact using name and phone matching
  native.Contact? _findMatchingDeviceContact(
    app.Contact serverContact,
    List<native.Contact> deviceContacts,
  ) {
    // Try exact name match first
    List<native.Contact> nameMatches =
        deviceContacts.where((dc) {
          String serverDisplayName =
              serverContact.displayName?.toLowerCase() ?? '';
          String deviceDisplayName = dc.displayName?.toLowerCase() ?? '';
          return serverDisplayName == deviceDisplayName;
        }).toList();

    if (nameMatches.length == 1) {
      return nameMatches.first;
    }

    // If multiple name matches or no name matches, try phone number verification
    if (serverContact.phone_numbers != null &&
        serverContact.phone_numbers!.isNotEmpty) {
      String? serverPhone = _extractPhoneDigits(
        serverContact.phone_numbers!.first.number,
      );

      if (serverPhone != null && serverPhone.length >= 7) {
        String serverLast7 = serverPhone.substring(serverPhone.length - 7);

        for (var deviceContact
            in (nameMatches.isNotEmpty ? nameMatches : deviceContacts)) {
          for (var phone in deviceContact.phones) {
            String? devicePhoneDigits = _extractPhoneDigits(phone.number);
            if (devicePhoneDigits != null && devicePhoneDigits.length >= 7) {
              String deviceLast7 = devicePhoneDigits.substring(
                devicePhoneDigits.length - 7,
              );
              if (serverLast7 == deviceLast7) {
                return deviceContact;
              }
            }
          }
        }
      }
    }

    // If still no match and we had name matches, return the first one
    if (nameMatches.isNotEmpty) {
      return nameMatches.first;
    }

    // No match found
    return null;
  }

  /// Extract only digits from phone number for comparison
  String? _extractPhoneDigits(String? phoneNumber) {
    if (phoneNumber == null) return null;
    return phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
  }
}

// Helper class (can be outside or inside, or in a separate file)
class SyncPair {
  final native.Contact nativeContact;
  final app.Contact appContact;
  SyncPair(this.nativeContact, this.appContact);
}
