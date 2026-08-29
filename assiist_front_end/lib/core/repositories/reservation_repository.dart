import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:assiist_front_end/core/models/reservation.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart';
import 'package:assiist_front_end/services/auth_service.dart';

abstract class ReservationRepository {
  Future<Reservation> create(Reservation reservation);
  Future<Reservation?> getById(String id);
  Future<List<Reservation>> getByAccount(
    String accountId, {
    String? userId,
    String? contactId,
  });
  Future<bool> delete(String id);
  Future<bool> exists(String contactId, String accountId);
}

class ReservationRepositoryImpl implements ReservationRepository {
  final String baseUrl;
  final AuthService _authService;
  final http.Client client;

  ReservationRepositoryImpl({
    required this.baseUrl,
    required AuthService authService,
    http.Client? httpClient,
  }) : client = httpClient ?? http.Client(),
       _authService = authService {
    print(
      '[DEBUG] ReservationRepositoryImpl constructed with client: '
      '[33m$client[0m',
    );
  }

  Future<Map<String, String>> _getHeaders() async {
    final headers = {'Content-Type': 'application/json; charset=UTF-8'};
    final String? freshToken = await _authService.getFreshAuthToken();
    if (freshToken != null) {
      headers['Authorization'] = 'Bearer $freshToken';
    } else {
      throw UnauthorizedException(
        'User not authenticated or token refresh failed.',
      );
    }
    return headers;
  }

  @override
  Future<Reservation> create(Reservation reservation) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/reservations'),
        headers: await _getHeaders(),
        body: jsonEncode(reservation.toJson()),
      );
      print(
        '[DEBUG] ReservationRepositoryImpl.create response: '
        '${response.statusCode} ${response.body}',
      );
      if (response.statusCode == 201) {
        return Reservation.fromJson(jsonDecode(response.body));
      } else if (response.statusCode == 409) {
        throw ApiException('Reservation already exists for this contact');
      } else {
        throw ApiException(
          'Failed to create reservation: ${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      print('[DEBUG] Exception in ReservationRepositoryImpl.create: $e');
      throw ApiException('Failed to create reservation: $e');
    }
  }

  @override
  Future<Reservation?> getById(String id) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/reservations/$id'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        return Reservation.fromJson(jsonDecode(response.body));
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw ApiException('Failed to get reservation: ${response.statusCode}');
      }
    } catch (e) {
      throw ApiException('Failed to get reservation: $e');
    }
  }

  @override
  Future<List<Reservation>> getByAccount(
    String accountId, {
    String? userId,
    String? contactId,
  }) async {
    print('[DEBUG] ReservationRepositoryImpl.getByAccount called with:');
    print('[DEBUG]   accountId: $accountId');
    print('[DEBUG]   userId: $userId');
    print('[DEBUG]   contactId: $contactId');

    try {
      final queryParams = <String, String>{};
      if (userId != null) queryParams['user_id'] = userId;
      if (contactId != null) queryParams['contact_id'] = contactId;

      final uri = Uri.parse(
        '$baseUrl/reservations',
      ).replace(queryParameters: queryParams);
      print('[DEBUG] Making GET request to: $uri');

      final response = await client.get(uri, headers: await _getHeaders());
      print('[DEBUG] Response status: ${response.statusCode}');
      print('[DEBUG] Response body: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        final reservations =
            jsonList.map((json) => Reservation.fromJson(json)).toList();
        print('[DEBUG] Parsed ${reservations.length} reservations');
        return reservations;
      } else {
        throw ApiException(
          'Failed to get reservations: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('[DEBUG] Error in getByAccount: $e');
      throw ApiException('Failed to get reservations: $e');
    }
  }

  @override
  Future<bool> delete(String id) async {
    try {
      final response = await client.delete(
        Uri.parse('$baseUrl/reservations/$id'),
        headers: await _getHeaders(),
      );

      return response.statusCode == 204;
    } catch (e) {
      throw ApiException('Failed to delete reservation: $e');
    }
  }

  @override
  Future<bool> exists(String contactId, String accountId) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/reservations').replace(
          queryParameters: {'contact_id': contactId, 'account_id': accountId},
        ),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.isNotEmpty;
      } else {
        throw ApiException(
          'Failed to check reservation existence: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw ApiException('Failed to check reservation existence: $e');
    }
  }
}
