import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:assiist_front_end/core/models/contact.dart';
import 'package:assiist_front_end/core/repositories/contact_repository.dart';
import 'package:assiist_front_end/widgets/vip_components.dart';
import 'repository_providers.dart';

/// Provider for VIP contacts only
final vipContactsProvider = FutureProvider<List<Contact>>((ref) async {
  final contactRepo = ref.watch(contactRepositoryProvider);
  final allContacts = await contactRepo.getAllContactsForUser();
  return allContacts.where((contact) => contact.isVip).toList();
});

/// Provider for contact filtering state
final contactFilterProvider = StateProvider<ContactFilter>(
  (ref) => ContactFilter.all,
);

/// Provider for filtered contacts based on current filter
final filteredContactsProvider = FutureProvider<List<Contact>>((ref) async {
  final contactRepo = ref.watch(contactRepositoryProvider);
  final filter = ref.watch(contactFilterProvider);
  final allContacts = await contactRepo.getAllContactsForUser();

  switch (filter) {
    case ContactFilter.vipOnly:
      return allContacts.where((contact) => contact.isVip).toList();
    case ContactFilter.regularOnly:
      return allContacts.where((contact) => !contact.isVip).toList();
    case ContactFilter.all:
    default:
      return allContacts;
  }
});

/// Provider for VIP contact statistics
final vipStatisticsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final contactRepo = ref.watch(contactRepositoryProvider);
  final allContacts = await contactRepo.getAllContactsForUser();

  final vipContacts = allContacts.where((contact) => contact.isVip).toList();
  final totalContacts = allContacts.length;
  final vipCount = vipContacts.length;
  final vipPercentage =
      totalContacts > 0 ? (vipCount / totalContacts) * 100 : 0.0;

  // Calculate engagement score based on recent interactions
  double engagementScore = 0.0;
  if (vipContacts.isNotEmpty) {
    final now = DateTime.now();
    int totalScore = 0;
    for (final contact in vipContacts) {
      if (contact.last_contacted_on != null) {
        final daysSince = now.difference(contact.last_contacted_on!).inDays;
        // Higher score for more recent contact (max 100 points)
        final score = (100 - daysSince).clamp(0, 100);
        totalScore += score;
      }
    }
    engagementScore = totalScore / vipContacts.length;
  }

  return {
    'total_contacts': totalContacts,
    'vip_contacts': vipCount,
    'vip_percentage': vipPercentage,
    'vip_engagement_score': engagementScore,
  };
});

/// State notifier for VIP contact updates
class VipContactNotifier extends StateNotifier<AsyncValue<Contact?>> {
  final ContactRepository _repository;
  final Ref _ref;

  VipContactNotifier(this._repository, this._ref)
    : super(const AsyncValue.data(null));

  /// Toggle VIP status for a contact
  Future<void> toggleVipStatus(String contactId, bool currentStatus) async {
    state = const AsyncValue.loading();

    try {
      final updatedContact = await _repository.updateContact(contactId, {
        'is_vip': !currentStatus,
      });

      if (updatedContact != null) {
        state = AsyncValue.data(updatedContact);
        // Invalidate related providers to refresh data
        _ref.invalidate(vipContactsProvider);
        _ref.invalidate(filteredContactsProvider);
        _ref.invalidate(vipStatisticsProvider);
      } else {
        state = const AsyncValue.error(
          'Failed to update VIP status',
          StackTrace.empty,
        );
      }
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Bulk update VIP status for multiple contacts
  Future<void> bulkUpdateVipStatus(List<String> contactIds, bool isVip) async {
    state = const AsyncValue.loading();

    try {
      final futures =
          contactIds
              .map((id) => _repository.updateContact(id, {'is_vip': isVip}))
              .toList();

      await Future.wait(futures);

      state = const AsyncValue.data(null);
      // Invalidate related providers to refresh data
      _ref.invalidate(vipContactsProvider);
      _ref.invalidate(filteredContactsProvider);
      _ref.invalidate(vipStatisticsProvider);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}

/// Provider for VIP contact updates
final vipContactNotifierProvider =
    StateNotifierProvider<VipContactNotifier, AsyncValue<Contact?>>((ref) {
      final repository = ref.watch(contactRepositoryProvider);
      return VipContactNotifier(repository, ref);
    });

/// Provider to get VIP contacts sorted by priority (last contacted)
final vipContactsSortedProvider = FutureProvider<List<Contact>>((ref) async {
  final vipContacts = await ref.watch(vipContactsProvider.future);

  // Sort VIP contacts by last contacted date (most recent first)
  vipContacts.sort((a, b) {
    if (a.last_contacted_on == null && b.last_contacted_on == null) return 0;
    if (a.last_contacted_on == null) return 1;
    if (b.last_contacted_on == null) return -1;
    return b.last_contacted_on!.compareTo(a.last_contacted_on!);
  });

  return vipContacts;
});

/// Provider for contacts sorted with VIP priority
final contactsWithVipPriorityProvider = FutureProvider<List<Contact>>((
  ref,
) async {
  final contactRepo = ref.watch(contactRepositoryProvider);
  final allContacts = await contactRepo.getAllContactsForUser();

  // Sort with VIP contacts first, then alphabetical within each group
  allContacts.sort((a, b) {
    // VIP contacts first
    if (a.isVip && !b.isVip) return -1;
    if (!a.isVip && b.isVip) return 1;

    // Then alphabetical within each group
    return a.displayName.compareTo(b.displayName);
  });

  return allContacts;
});

/// Provider for search results with VIP priority
final vipPrioritySearchProvider = FutureProvider.family<List<Contact>, String>((
  ref,
  query,
) async {
  final contactRepo = ref.watch(contactRepositoryProvider);

  if (query.trim().isEmpty) {
    return [];
  }

  final searchResults = await contactRepo.searchContacts(query);

  // Sort search results with VIP contacts first
  searchResults.sort((a, b) {
    if (a.isVip && !b.isVip) return -1;
    if (!a.isVip && b.isVip) return 1;
    return 0; // Keep original relevance order within VIP/non-VIP groups
  });

  return searchResults;
});
