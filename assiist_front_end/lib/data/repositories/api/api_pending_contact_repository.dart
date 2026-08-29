import 'dart:convert';

import 'package:assiist_front_end/core/models/pending_contact.dart';
import 'package:assiist_front_end/core/repositories/pending_contact_repository.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart';
import 'package:http/http.dart' as http; // Import base http package
import 'package:assiist_front_end/services/auth_service.dart'; // IMPORT AuthService

class ApiPendingContactRepository implements PendingContactRepository {
  final String? baseUrl;
  final AuthService _authService; // ADDED
  final http.Client _httpClient;

  ApiPendingContactRepository({
    required this.baseUrl,
    required AuthService authService, // CHANGED
    http.Client? client,
  }) : _authService = authService, // ADDED
       _httpClient = client ?? http.Client();

  // _headers getter now needs to be async to fetch a fresh token
  Future<Map<String, String>> _getHeaders() async {
    final token = await _authService.getFreshAuthToken();
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Uri _buildUri(String endpoint, {Map<String, String>? queryParams}) {
    if (baseUrl == null) {
      throw ApiException("API Base URL is not configured.");
    }
    final uri = Uri.parse('$baseUrl$endpoint');
    if (queryParams != null && queryParams.isNotEmpty) {
      return uri.replace(queryParameters: queryParams);
    }
    return uri;
  }

  @override
  Future<List<PendingContact>> getPendingContacts({String? status}) async {
    final endpoint = '/appointments/pending-contacts';
    // Build query parameters
    final Map<String, String> queryParams = {};
    if (status != null && status.isNotEmpty) {
      queryParams['status'] = status;
    }
    final uri = _buildUri(
      endpoint,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );

    print('--- ApiPendingContactRepository.getPendingContacts --- ');
    print('Attempting to GET: $uri');
    final headers = await _getHeaders();
    print('Using headers: $headers');

    try {
      final response = await _httpClient.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> jsonResponse = jsonDecode(response.body);
        return jsonResponse
            .map(
              (data) => PendingContact.fromJson(data as Map<String, dynamic>),
            )
            .toList();
      } else {
        throw ApiException(
          'Failed to load pending contacts (Status: ${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
    } on ApiException catch (_) {
      rethrow;
    } catch (e) {
      print('ApiPendingContactRepository: Error fetching pending contacts: $e');
      throw ApiException(
        'Network or unexpected error fetching pending contacts.',
      );
    }
  }

  @override
  Future<void> updatePendingContactStatus(String id, String status) async {
    final endpoint = '/appointments/pending-contacts/$id';
    print(
      '[ApiRepo] updateStatus: Attempting to build URI for endpoint: $endpoint',
    );
    final uri = _buildUri(endpoint);
    print('[ApiRepo] updateStatus: Built URI: $uri');
    final body = jsonEncode({'status': status});
    final headers = await _getHeaders(); // MODIFIED: await headers
    print('[ApiRepo] updateStatus: Request body: $body');
    print('[ApiRepo] updateStatus: Headers: $headers');

    try {
      print('[ApiRepo] updateStatus: Making PATCH request to $uri...');
      final response = await _httpClient.patch(
        uri,
        headers: headers, // MODIFIED: pass headers
        body: body,
      );
      print(
        '[ApiRepo] updateStatus: Received status code: ${response.statusCode}',
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Success (e.g., 200 OK or 204 No Content)
        print('Successfully updated pending contact $id status to $status');
        return;
      } else {
        // Handle non-success responses
        throw ApiException(
          'Failed to update pending contact status (Status: ${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
    } on ApiException catch (_) {
      rethrow; // Re-throw API exceptions directly
    } catch (e) {
      // Wrap other errors
      print('ApiPendingContactRepository: Error updating status for $id: $e');
      throw ApiException(
        'Network or unexpected error updating pending contact status.',
      );
    }
  }
}
