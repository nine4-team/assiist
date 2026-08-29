import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:assiist_front_end/core/models/generation_accepted_response.dart';

import 'package:assiist_front_end/core/errors/exceptions.dart';
import 'package:assiist_front_end/services/auth_service.dart';

class ApiGenerationRequestRepository {
  final String baseUrl;
  final AuthService _authService;
  final http.Client client;

  ApiGenerationRequestRepository({
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
    throw ServerException('API Error ($statusCode): $detail');
  }

  /// Submits a quick draft generation request and returns the accepted response (with requestId).
  Future<GenerationAcceptedResponseSchema> submitQuickDraftGenerationRequest({
    required String contactId,
    required String instructions,
    required String language,
  }) async {
    print('--- API Generation Request Repository ---');
    print('baseUrl: $baseUrl');
    print('contactId: $contactId');
    print('instructions: $instructions');
    print('language: $language');

    final url = Uri.parse('$baseUrl/assistant/quick-actions');
    print('Full URL: $url');

    final payload = {
      'contact_id': contactId,
      'request_type': 'quick_draft',
      'message_instructions': instructions,
      'message_language': language,
    };
    print('Payload: $payload');

    final body = jsonEncode(payload);
    print('JSON Body: $body');

    final headers = await _getHeaders();
    print('Headers: $headers');

    try {
      print('Making POST request to $url...');
      final response = await client.post(url, headers: headers, body: body);

      print('Response status code: ${response.statusCode}');
      print('Response headers: ${response.headers}');
      print('Response body: ${response.body}');

      _handleResponseErrors(response);

      if (response.statusCode == 202) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        print('Successfully parsed response data: $responseData');
        return GenerationAcceptedResponseSchema.fromJson(responseData);
      } else {
        throw ServerException(
          'Unexpected status code (${response.statusCode}) for quick draft generation request.',
        );
      }
    } catch (e, stackTrace) {
      print('Error in submitQuickDraftGenerationRequest: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }
}
