import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:assiist_front_end/core/models/user_metrics.dart';
import 'repository_providers.dart';
import 'auth_providers.dart';

// Provider for contact-specific metrics
final contactMetricsProvider = FutureProvider.family<UserMetrics?, String>((
  ref,
  contactId,
) async {
  final repository = ref.watch(userMetricsRepositoryProvider);
  return repository.getMetricsForContact(contactId);
});

// Provider for user-wide total metrics
final userTotalMetricsProvider = FutureProvider<Map<String, int>>((ref) async {
  final repository = ref.watch(userMetricsRepositoryProvider);
  return repository.getMetricsForUser();
});
