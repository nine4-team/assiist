import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:assiist_front_end/core/repositories/assistant_repository.dart';
import 'package:assiist_front_end/core/models/generation_accepted_response.dart';
import 'package:assiist_front_end/services/auth_service.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart';

class ApiAssistantRepository implements AssistantRepository {
  final String baseUrl;
  final AuthService authService;
  final http.Client client;

  ApiAssistantRepository({
    required this.baseUrl,
    required this.authService,
    http.Client? client,
  }) : client = client ?? http.Client();

  Future<Map<String, String>> _getHeaders() async {
    final token = await authService.getFreshAuthToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  void _handleResponseErrors(http.Response response) {
    if (response.statusCode == 401) {
      throw UnauthorizedException('Authentication failed');
    } else if (response.statusCode == 403) {
      throw UnauthorizedException('Access denied');
    } else if (response.statusCode == 404) {
      throw NotFoundException('Resource not found');
    } else if (response.statusCode >= 400 && response.statusCode < 500) {
      String errorMessage = 'Client error: ${response.statusCode}';
      try {
        final Map<String, dynamic> errorBody = jsonDecode(response.body);
        errorMessage = errorBody['detail'] ?? errorMessage;
      } catch (_) {}
      throw InvalidInputException(errorMessage);
    } else if (response.statusCode >= 500) {
      throw ServerException('Server error: ${response.statusCode}');
    }
  }

  @override
  Future<Map<String, dynamic>> reviseDraft(
    Map<String, dynamic> revisionPayload,
  ) async {
    final url = Uri.parse('$baseUrl/assistant/quick-actions');

    try {
      // Convert the payload to the simplified unified format expected by the backend
      final unifiedPayload = {
        'contact_id': revisionPayload['contact_id'],
        'request_type': 'revise_draft',
        'task_id': revisionPayload['task_id'],
        'revision_instructions': revisionPayload['revision_instructions'],
        'message_language': revisionPayload['message_language'] ?? 'english',
      };

      final body = jsonEncode(unifiedPayload);

      final response = await client.post(
        url,
        headers: await _getHeaders(),
        body: body,
      );

      _handleResponseErrors(response);

      if (response.statusCode == 202) {
        final responseData = jsonDecode(response.body);
        return responseData;
      } else {
        throw ServerException(
          'Unexpected response status: ${response.statusCode}',
        );
      }
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect for revision request: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error in revision request: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> quickDraft(
    Map<String, dynamic> draftPayload,
  ) async {
    final url = Uri.parse('$baseUrl/assistant/quick-actions');

    try {
      final unifiedPayload = {
        'contact_id': draftPayload['contact_id'],
        'request_type': 'quick_draft',
        'message_instructions': draftPayload['message_instructions'],
        'language': draftPayload['language'] ?? 'english',
      };

      final body = jsonEncode(unifiedPayload);

      final response = await client.post(
        url,
        headers: await _getHeaders(),
        body: body,
      );

      _handleResponseErrors(response);

      if (response.statusCode == 202) {
        final responseData = jsonDecode(response.body);
        return responseData;
      } else {
        throw ServerException(
          'Unexpected response status: ${response.statusCode}',
        );
      }
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect for quick draft request: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error in quick draft request: $e');
    }
  }

  @override
  Future<GenerationAcceptedResponseSchema> requestQuickTaskGeneration(
    String contactId,
    String instructions,
  ) async {
    final url = Uri.parse('$baseUrl/assistant/quick-actions');

    try {
      final payload = {
        'contact_id': contactId,
        'request_type': 'quick_task',
        'message_instructions': instructions,
        'language': 'english',
      };

      final body = jsonEncode(payload);

      final response = await client.post(
        url,
        headers: await _getHeaders(),
        body: body,
      );

      _handleResponseErrors(response);

      if (response.statusCode == 202) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        return GenerationAcceptedResponseSchema.fromJson(responseData);
      } else {
        throw ServerException(
          'Unexpected status code (${response.statusCode}) for quick task generation request.',
        );
      }
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect for quick task generation: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException(
        'Unexpected error requesting quick task generation: $e',
      );
    }
  }

  @override
  Future<GenerationAcceptedResponseSchema> requestQuickDraftGeneration(
    String contactId,
    String instructions,
    String language,
  ) async {
    final url = Uri.parse('$baseUrl/assistant/quick-actions');

    try {
      final payload = {
        'contact_id': contactId,
        'request_type': 'quick_draft',
        'message_instructions': instructions,
        'language': language,
      };

      final body = jsonEncode(payload);

      final response = await client.post(
        url,
        headers: await _getHeaders(),
        body: body,
      );

      _handleResponseErrors(response);

      if (response.statusCode == 202) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        return GenerationAcceptedResponseSchema.fromJson(responseData);
      } else {
        throw ServerException(
          'Unexpected status code (${response.statusCode}) for quick draft generation request.',
        );
      }
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Failed to connect for quick draft generation: $e',
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException(
        'Unexpected error requesting quick draft generation: $e',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> updateAssistant(
    Map<String, dynamic> updatePayload,
  ) async {
    final url = Uri.parse('$baseUrl/assistant/update-assistant');

    try {
      final body = jsonEncode(updatePayload);

      final response = await client.post(
        url,
        headers: await _getHeaders(),
        body: body,
      );

      _handleResponseErrors(response);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return responseData;
      } else {
        throw ServerException(
          'Unexpected response status: ${response.statusCode}',
        );
      }
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Failed to connect for update assistant request: $e',
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error in update assistant request: $e');
    }
  }
}
