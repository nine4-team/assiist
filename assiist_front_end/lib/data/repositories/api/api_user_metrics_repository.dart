import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:assiist_front_end/core/models/user_metrics.dart';
import 'package:assiist_front_end/core/repositories/user_metrics_repository.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart';
import 'package:uuid/uuid.dart';
import 'package:assiist_front_end/services/auth_service.dart';

class ApiUserMetricsRepository implements UserMetricsRepository {
  final String baseUrl;
  final AuthService _authService;
  final http.Client client;

  ApiUserMetricsRepository({
    required this.baseUrl,
    required AuthService authService,
    http.Client? httpClient,
  }) : client = httpClient ?? http.Client(),
       _authService = authService;

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

  void _handleResponseErrors(http.Response response) {
    final statusCode = response.statusCode;
    if (statusCode >= 200 && statusCode < 300) return;

    final detail = response.reasonPhrase ?? 'Unknown API error';

    if (statusCode == 404) throw NotFoundException(detail);
    if (statusCode == 401 || statusCode == 403)
      throw UnauthorizedException(detail);
    if (statusCode == 400) throw InvalidInputException(detail);
    throw ServerException('API Error (29): $detail');
  }

  @override
  Future<UserMetrics?> getMetricsForContact(String contactId) async {
    final url = Uri.parse('$baseUrl/metrics/contacts/$contactId');
    try {
      final response = await client.get(url, headers: await _getHeaders());

      if (response.statusCode == 404) {
        return null;
      }

      _handleResponseErrors(response);

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      return UserMetrics.fromJson(responseData);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error getting metrics: $e');
    }
  }

  @override
  Future<void> incrementMessagesSent(String contactId) async {
    final url = Uri.parse('$baseUrl/metrics/contacts/$contactId/messages');
    final uuid = Uuid();
    final idempotencyKey = uuid.v4();
    final headers = await _getHeaders();
    headers['Idempotency-Key'] = idempotencyKey;
    try {
      final response = await client.post(url, headers: headers);
      _handleResponseErrors(response);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error incrementing messages: $e');
    }
  }

  @override
  Future<void> incrementNotesLogged(String contactId) async {
    final url = Uri.parse('$baseUrl/metrics/contacts/$contactId/notes');
    try {
      final response = await client.post(url, headers: await _getHeaders());
      _handleResponseErrors(response);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error incrementing notes: $e');
    }
  }

  @override
  Future<Map<String, int>> getMetricsForUser() async {
    final url = Uri.parse('$baseUrl/metrics/total');
    try {
      final response = await client.get(url, headers: await _getHeaders());
      _handleResponseErrors(response);

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'messages_sent': responseData['messages_sent'] as int? ?? 0,
        'notes_logged': responseData['notes_logged'] as int? ?? 0,
      };
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error getting total metrics: $e');
    }
  }
}
