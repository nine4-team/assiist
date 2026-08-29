import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:assiist_front_end/core/repositories/reservation_repository.dart';
import 'package:assiist_front_end/core/models/reservation.dart';
import 'package:assiist_front_end/providers/auth_providers.dart';
import 'package:assiist_front_end/services/auth_service.dart';
import 'package:http/http.dart' as http;

final reservationRepositoryProvider = Provider<ReservationRepository>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final authService = ref.watch(authServiceProvider);
  return ReservationRepositoryImpl(
    baseUrl: baseUrl,
    authService: authService,
    httpClient: http.Client(),
  );
});

final addToReservationListProvider = FutureProvider.family<bool, Reservation>((
  ref,
  reservation,
) async {
  final repository = ref.watch(reservationRepositoryProvider);

  try {
    await repository.create(reservation);
    return true;
  } catch (e, stack) {
    print('[DEBUG] Exception in addToReservationListProvider: $e');
    print('[DEBUG] Contact ID: ${reservation.contactId}');
    print('[DEBUG] Contact Name: ${reservation.contactName}');
    print('[DEBUG] Contact Email: ${reservation.contactEmail}');
    print('[DEBUG] Account ID: ${reservation.accountId}');
    print('[DEBUG] Stack trace: $stack');

    // Check if this is a 409 conflict specifically
    if (e.toString().contains('409') ||
        e.toString().contains('already exists')) {
      print(
        '[DEBUG] This is a 409 conflict - reservation already exists for this contact!',
      );
    }

    return false;
  }
});

final getReservationsProvider = FutureProvider.family<
  List<Reservation>,
  Map<String, String?>
>((ref, filters) async {
  print('[DEBUG] getReservationsProvider called with filters: $filters');
  final repository = ref.watch(reservationRepositoryProvider);
  final accountId = ref.watch(currentAccountIdProvider);
  print('[DEBUG] Current accountId from provider: $accountId');

  if (accountId == null) {
    print('[DEBUG] ERROR: Account ID not available in provider!');
    throw Exception('Account ID not available');
  }

  try {
    print('[DEBUG] Calling repository.getByAccount with accountId: $accountId');
    final reservations = await repository.getByAccount(
      accountId,
      userId: filters['userId'],
      contactId: filters['contactId'],
    );
    print('[DEBUG] Got reservations from repository: ${reservations.length}');
    return reservations;
  } catch (e, stack) {
    print('[DEBUG] Error in getReservationsProvider: $e');
    print('[DEBUG] Stack trace: $stack');
    rethrow;
  }
});
