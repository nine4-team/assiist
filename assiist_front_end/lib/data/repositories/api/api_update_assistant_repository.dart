import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:assiist_front_end/core/errors/exceptions.dart';
import 'package:assiist_front_end/services/auth_service.dart';

class ProcessNoteResponse {
  final bool success;
  final int tasksProcessed;
  final bool contextUpdated;
  final Map<String, dynamic> noteSaved;
  final double? processingTime;

  ProcessNoteResponse({
    required this.success,
    required this.tasksProcessed,
    required this.contextUpdated,
    required this.noteSaved,
    this.processingTime,
  });

  factory ProcessNoteResponse.fromJson(Map<String, dynamic> json) {
    return ProcessNoteResponse(
      success: json['success'] as bool,
      tasksProcessed: json['tasks_processed'] as int,
      contextUpdated: json['context_updated'] as bool,
      noteSaved: json['note_saved'] as Map<String, dynamic>,
      processingTime: json['processing_time']?.toDouble(),
    );
  }
}

class ApiUpdateAssistantRepository {
  final String baseUrl;
  final AuthService _authService;
  final http.Client client;

  ApiUpdateAssistantRepository({
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

  /// Process raw note content through Update Assistant
  Future<ProcessNoteResponse> updateAssistant({
    required String contactId,
    required String rawNoteContent,
    Map<String, dynamic>? context,
    String noteType = "user",
  }) async {
    print('--- API Update Assistant Repository ---');
    print('baseUrl: $baseUrl');
    print('contactId: $contactId');
    print(
      'rawNoteContent: ${rawNoteContent.substring(0, rawNoteContent.length > 100 ? 100 : rawNoteContent.length)}...',
    );
    print('context: $context');

    final url = Uri.parse('$baseUrl/assistant/update-assistant');
    print('Full URL: $url');

    final payload = {
      'contact_id': contactId,
      'note_content': rawNoteContent,
      'context': context ?? {},
      'note_type': noteType,
    };
    print('Payload: $payload');

    final body = jsonEncode(payload);
    final headers = await _getHeaders();

    try {
      print('Making POST request to $url...');
      final response = await client.post(url, headers: headers, body: body);

      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      _handleResponseErrors(response);

      // Handle both 200 (legacy) and 202 (async) responses
      if (response.statusCode == 200 || response.statusCode == 202) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        print('Successfully processed raw note: $responseData');

        // Transform async response to expected format for backward compatibility
        if (response.statusCode == 202) {
          // Async response - create a compatible response structure
          final requestIds =
              responseData['request_ids'] as Map<String, dynamic>? ?? {};
          return ProcessNoteResponse(
            success: responseData['success'] ?? true,
            tasksProcessed: 0, // Will be updated later via real-time updates
            contextUpdated: true, // Assume true for async processing
            noteSaved: {
              'status': 'processing',
              'message':
                  responseData['message'] ??
                  'Update Assistant processing started',
              'request_ids': requestIds,
              'estimated_completion_time':
                  responseData['estimated_completion_time'] ?? '30-60 seconds',
            },
            processingTime: null, // Will be available when processing completes
          );
        } else {
          // Legacy 200 response
          return ProcessNoteResponse.fromJson(responseData);
        }
      } else {
        throw ServerException(
          'Unexpected status code (${response.statusCode}) for Update Assistant request.',
        );
      }
    } catch (e, stackTrace) {
      print('Error in updateAssistant: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }
}
