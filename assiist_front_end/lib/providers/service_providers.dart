import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import existing repository providers
import 'repository_providers.dart'; // This should contain contactRepositoryProvider and settingsRepositoryProvider

// Import the services
import 'package:assiist_front_end/services/contact_sync_service.dart';
import 'package:assiist_front_end/services/generation_request_service.dart';
import 'package:assiist_front_end/core/repositories/user_settings_repository.dart';

// Provider for ContactSyncService
final contactSyncServiceProvider = Provider<ContactSyncService>((ref) {
  // Obtain instances of the repositories from their actual, existing providers
  final contactRepository = ref.watch(contactRepositoryProvider);
  final userSettingsRepository = ref.watch(userSettingsRepositoryProvider);

  return ContactSyncService(
    contactRepository: contactRepository,
    settingsRepository: userSettingsRepository,
  );
});

// Provider for GenerationRequestService
final generationRequestServiceProvider = Provider<GenerationRequestService>((
  ref,
) {
  return GenerationRequestService();
});
