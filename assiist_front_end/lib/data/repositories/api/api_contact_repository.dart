import 'dart:convert'; // For jsonDecode, jsonEncode
import 'package:http/http.dart' as http;
import 'package:assiist_front_end/core/models/contact.dart';
import 'package:assiist_front_end/core/repositories/contact_repository.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart'; // Assuming custom exceptions
import 'package:assiist_front_end/services/auth_service.dart'; // Import AuthService
import 'package:flutter/foundation.dart'; // For debugPrint

class ApiContactRepository implements ContactRepository {
  final String baseUrl; // e.g., http://localhost:8000/api/v1
  // final String? accessToken; // Firebase ID Token - REMOVED
  final AuthService _authService; // ADDED
  final http.Client client; // Use dependency injection for testability

  ApiContactRepository({
    required this.baseUrl,
    // required this.accessToken, // REMOVED
    required AuthService authService, // ADDED
    http.Client? httpClient, // Allow injecting a client for tests
  }) : client = httpClient ?? http.Client(),
       _authService = authService; // ADDED

  // Helper to build headers
  Future<Map<String, String>> _getHeaders() async {
    // MODIFIED to async
    final headers = {'Content-Type': 'application/json; charset=UTF-8'};
    final String? freshToken = await _authService.getFreshAuthToken(); // ADDED
    if (freshToken != null) {
      headers['Authorization'] = 'Bearer $freshToken';
    } else {
      // If the token is null, it means the user is not authenticated or token refresh failed.
      // Throwing an exception here ensures API calls are not made without auth.
      throw UnauthorizedException(
        'User not authenticated or token refresh failed.',
      );
    }
    return headers;
  }

  // Helper to handle common API response errors
  void _handleResponseErrors(http.Response response) {
    final statusCode = response.statusCode;
    if (statusCode >= 200 && statusCode < 300) {
      return; // Success, no error
    }

    String detail;
    Map<String, dynamic>? bodyMap;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        bodyMap = decoded;
      }
    } catch (_) {}

    detail =
        bodyMap?['detail']?.toString() ??
        response.reasonPhrase ??
        'Unknown error';

    switch (statusCode) {
      case 404:
        throw NotFoundException(detail);
      case 401:
      case 403:
        throw UnauthorizedException(detail);
      case 400:
        throw InvalidInputException(detail);
      case 409:
        debugPrint('409 body:  [33m${response.body} [0m');
        final Map<String, dynamic>? detailMap =
            (bodyMap?['detail'] is Map<String, dynamic>)
                ? Map<String, dynamic>.from(bodyMap!['detail'])
                : (bodyMap != null && bodyMap!['code'] != null)
                ? bodyMap
                : null;

        if (detailMap != null && detailMap['code'] == 'duplicate_contact') {
          throw DuplicateContactException(
            existingContactId: detailMap['existing_contact_id'] ?? '',
            field: detailMap['field'] ?? '',
            value: detailMap['value'] ?? '',
            message: 'Duplicate contact',
            statusCode: statusCode,
          );
        }
        throw ServerException('Duplicate contact', statusCode: statusCode);
      case 500:
        throw ServerException('Internal server error: $detail');
      default:
        throw ServerException('API Error ($statusCode): $detail');
    }
  }

  // Helper to parse Contact from JSON response
  Contact _parseContactFromJson(Map<String, dynamic> json) {
    try {
      return Contact.fromJson(json);
    } catch (e) {
      throw DataParsingException('Failed to parse contact data: $e');
    }
  }

  @override
  Future<Contact> createContact(Contact contact) async {
    // Use consistent endpoint with no trailing slash
    final url = Uri.parse('$baseUrl/contacts');
    try {
      final response = await client.post(
        url,
        headers: await _getHeaders(), // MODIFIED
        body: jsonEncode(
          contact.toJson(),
        ), // Assuming toJson exists and matches backend schema
      );

      _handleResponseErrors(response);

      final responseData = jsonDecode(response.body);
      return _parseContactFromJson(responseData);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      // Re-throw known exceptions, wrap others
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error creating contact: $e');
    }
  }

  @override
  Future<bool> deleteContact(String contactId) async {
    final url = Uri.parse('$baseUrl/contacts/$contactId');
    try {
      final response = await client.delete(
        url,
        headers: await _getHeaders(),
      ); // MODIFIED

      _handleResponseErrors(response); // Will throw for non-2xx codes

      // Backend returns 204 No Content on success
      return response.statusCode == 204;
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error deleting contact: $e');
    }
  }

  @override
  Future<Contact?> getContactById(String contactId) async {
    final url = Uri.parse('$baseUrl/contacts/$contactId');
    try {
      final response = await client.get(
        url,
        headers: await _getHeaders(),
      ); // MODIFIED

      // Handle 404 specifically by returning null
      if (response.statusCode == 404) {
        return null;
      }

      _handleResponseErrors(response);

      final responseData = jsonDecode(response.body);
      return _parseContactFromJson(responseData);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      // Don't throw server exception for get, allow null return on parsing error?
      // Or maybe throw a specific DataParsingException?
      print('Unexpected error getting contact by ID: $e');
      return null; // Return null for other unexpected errors during get
    }
  }

  @override
  Future<List<Contact>> searchContacts(
    String query, {
    int limit = 10,
    int offset = 0,
  }) async {
    // Target the new /search endpoint
    final url = Uri.parse('$baseUrl/contacts/search').replace(
      queryParameters: {
        'query': query,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
    print("DEBUG: Calling contact search API: $url"); // Debug print

    try {
      final response = await client.get(
        url,
        headers: await _getHeaders(),
      ); // MODIFIED

      _handleResponseErrors(response);

      final List<dynamic> responseData = jsonDecode(response.body);
      return responseData.map((data) {
        if (data is! Map<String, dynamic>) {
          throw DataParsingException('Invalid contact data format');
        }
        return _parseContactFromJson(data);
      }).toList();
    } on http.ClientException catch (e) {
      print("ERROR: NetworkException during contact search: $e"); // Debug print
      throw NetworkException('Search failed: $e');
    } catch (e) {
      print(
        "ERROR: Unexpected exception during contact search: $e",
      ); // Debug print
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error searching contacts: $e');
    }
  }

  @override
  Future<Contact?> updateContact(
    String contactId,
    Map<String, dynamic> updates,
  ) async {
    final url = Uri.parse('$baseUrl/contacts/$contactId');
    try {
      final response = await client.patch(
        url,
        headers: await _getHeaders(), // MODIFIED
        body: jsonEncode(updates), // Send only the updates
      );

      _handleResponseErrors(response);

      final responseData = jsonDecode(response.body);
      return _parseContactFromJson(responseData);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error updating contact: $e');
    }
  }

  // --- NEW: getAllContactsForUser (based on backend endpoint) ---
  // Implementation using the RESTful contacts endpoint (no trailing slash)
  @override
  Future<List<Contact>> getAllContactsForUser({
    int limit = 50,
    int offset = 0,
  }) async {
    // Use the contacts endpoint with no trailing slash
    // The FastAPI route is defined as @router.get("") which becomes /contacts
    final url = Uri.parse('$baseUrl/contacts').replace(
      queryParameters: {'limit': limit.toString(), 'offset': offset.toString()},
    );
    print("DEBUG: Calling contact list API: $url"); // Debug print

    try {
      final response = await client.get(url, headers: await _getHeaders());

      _handleResponseErrors(response);

      final List<dynamic> responseData = jsonDecode(response.body);
      return responseData.map((data) {
        if (data is! Map<String, dynamic>) {
          throw DataParsingException('Invalid contact data format');
        }
        return _parseContactFromJson(data);
      }).toList();
    } on http.ClientException catch (e) {
      print("ERROR: NetworkException during contact list fetch: $e");
      throw NetworkException('Failed to fetch contacts: $e');
    } catch (e) {
      print("ERROR: Unexpected exception during contact list fetch: $e");
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error fetching contacts: $e');
    }
  }

  // TODO: Implement getAllContactsForUser if needed by the interface
  // Need to know the correct backend endpoint (e.g., /contacts?account_id=... or derived from token?)
  // Assuming it's not part of the current ContactRepository interface based on providers file

  @override
  Future<bool> updateLastContacted(String contactId) async {
    try {
      final updates = {'last_contacted_on': DateTime.now().toIso8601String()};

      final updatedContact = await updateContact(contactId, updates);
      return updatedContact != null;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error updating last contacted: $e');
    }
  }

  // ------------------------------------------------------------------
  // Lean incremental sync endpoint
  // ------------------------------------------------------------------
  @override
  Future<Map<String, dynamic>> postIncrementalSync(
    Map<String, dynamic> payload,
  ) async {
    final url = Uri.parse('$baseUrl/contact_sync/sync/incremental');

    try {
      final response = await client.post(
        url,
        headers: await _getHeaders(),
        body: jsonEncode(payload),
      );

      _handleResponseErrors(response);

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else {
        throw DataParsingException(
          'Unexpected response format for incremental sync',
        );
      }
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error during incremental sync: $e');
    }
  }
}
