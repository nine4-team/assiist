import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:assiist_front_end/core/repositories/user_settings_repository.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart';
import 'package:assiist_front_end/services/auth_service.dart';
import 'package:assiist_front_end/core/models/pending_contact.dart';
import 'package:assiist_front_end/core/repositories/pending_contact_repository.dart';

class ApiUserSettingsRepository implements UserSettingsRepository {
  final String baseUrl;
  final AuthService _authService;
  final http.Client client;
  final PendingContactRepository _pendingContactRepository;

  ApiUserSettingsRepository({
    required this.baseUrl,
    required AuthService authService,
    required PendingContactRepository pendingContactRepository,
    http.Client? httpClient,
  }) : client = httpClient ?? http.Client(),
       _authService = authService,
       _pendingContactRepository = pendingContactRepository;

  // --- Helpers (Copied from other API Repositories) ---
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
    // Allow 204 No Content as success for this operation
    if (statusCode >= 200 && statusCode < 300) return;

    final detail = response.reasonPhrase ?? 'Unknown API error';
    // TODO: Enhance error parsing from response body if backend provides details

    if (statusCode == 404) throw NotFoundException(detail);
    if (statusCode == 401 || statusCode == 403) {
      throw UnauthorizedException(detail);
    }
    if (statusCode == 400) throw InvalidInputException(detail);
    throw ServerException('API Error ($statusCode): $detail');
  }
  // --- End Helpers ---

  @override
  Future<void> addIgnoredEmail(String email) async {
    final url = Uri.parse('$baseUrl/settings/ignore-list');
    try {
      final body = jsonEncode({'email': email});

      final response = await client.post(
        url,
        headers: await _getHeaders(),
        body: body,
      );

      _handleResponseErrors(response);

      // No need to decode response body for 204 No Content
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error adding ignored email: $e');
    }
  }

  @override
  Future<void> removeIgnoredEmail(String email) async {
    final url = Uri.parse('$baseUrl/settings/ignore-list');
    try {
      final body = jsonEncode({'email': email});
      final response = await client.delete(
        url,
        headers: await _getHeaders(),
        body: body,
      );
      _handleResponseErrors(response);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error removing ignored email: $e');
    }
  }

  @override
  Future<List<String>> getIgnoredEmailsList() async {
    try {
      final pendingContacts = await _pendingContactRepository
          .getPendingContacts(status: 'ignored');
      return pendingContacts
          .map((contact) => contact.email ?? '')
          .where((email) => email.isNotEmpty)
          .toList();
    } on ApiException catch (_) {
      rethrow;
    } catch (e) {
      print('ApiSettingsRepository: Error fetching ignored emails list: $e');
      throw ServerException('Unexpected error fetching ignored emails list.');
    }
  }

  @override
  Future<void> saveContactSyncSettings(String? source, String priority) async {
    final url = Uri.parse(
      '$baseUrl/users/settings/contact-sync',
    ); // New endpoint
    try {
      final body = jsonEncode({
        'source_preference': source,
        'source_priority': priority,
      });

      final response = await client.patch(
        // Using PATCH to update settings (was PUT)
        url,
        headers: await _getHeaders(),
        body: body,
      );

      _handleResponseErrors(response);
      // Backend might return 200 OK with the updated settings or 204 No Content
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException(
        'Unexpected error saving contact sync settings: $e',
      );
    }
  }

  @override
  Future<Map<String, String>?> getContactSyncSettings() async {
    final url = Uri.parse(
      '$baseUrl/users/settings/contact-sync',
    ); // New endpoint
    try {
      final response = await client.get(url, headers: await _getHeaders());

      if (response.statusCode == 404) {
        // If settings are not found (e.g., user never saved them), return null.
        return null;
      }

      _handleResponseErrors(response);

      final responseData = jsonDecode(response.body);
      if (responseData is Map<String, dynamic>) {
        // Ensure the keys exist and values are strings before returning
        final String? source = responseData['source_preference'] as String?;
        final String? priority = responseData['source_priority'] as String?;
        if (source != null && priority != null) {
          return {'source': source, 'priority': priority};
        }
      }
      // If response is not in the expected format or keys are missing
      print(
        'ApiSettingsRepository: Unexpected format for contact sync settings: $responseData',
      );
      return null;
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      print(
        'ApiSettingsRepository: Unexpected error getting contact sync settings: $e',
      );
      return null; // Return null for other unexpected errors
    }
  }

  @override
  Future<void> saveBusinessDescription(String description) async {
    final url = Uri.parse('$baseUrl/settings/business-description');
    try {
      final body = jsonEncode({'description': description});

      final response = await client.put(
        url,
        headers: await _getHeaders(),
        body: body,
      );

      _handleResponseErrors(response);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error saving business description: $e');
    }
  }

  @override
  Future<String?> getBusinessDescription() async {
    final url = Uri.parse('$baseUrl/settings/business-description');
    try {
      final response = await client.get(url, headers: await _getHeaders());

      if (response.statusCode == 404) {
        return null;
      }

      _handleResponseErrors(response);

      final responseData = jsonDecode(response.body);
      if (responseData is Map<String, dynamic>) {
        return responseData['description'] as String?;
      }
      return null;
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      print(
        'ApiSettingsRepository: Unexpected error getting business description: $e',
      );
      return null;
    }
  }

  // Implement other methods like getIgnoredEmails later if needed
}
