import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:assiist_front_end/core/models/feedback.dart';
import 'package:assiist_front_end/core/repositories/feedback_repository.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart';
import 'package:assiist_front_end/services/auth_service.dart';

class ApiFeedbackRepository implements FeedbackRepository {
  final String baseUrl; // e.g., http://localhost:8000/api/v1
  final AuthService _authService;
  final http.Client client;

  ApiFeedbackRepository({
    required this.baseUrl,
    required AuthService authService,
    http.Client? httpClient,
  }) : client = httpClient ?? http.Client(),
       _authService = authService;

  // --- Helpers ---

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

    String detail;
    try {
      final responseBody = jsonDecode(response.body);
      if (responseBody is Map) {
        detail =
            responseBody['error'] ??
            responseBody['detail'] ??
            response.reasonPhrase ??
            'Unknown API error';
      } else {
        detail = response.reasonPhrase ?? response.body;
      }
    } catch (e) {
      detail = response.reasonPhrase ?? response.body;
    }

    if (statusCode == 404) throw NotFoundException(detail);
    if (statusCode == 401 || statusCode == 403) {
      throw UnauthorizedException(detail);
    }
    if (statusCode == 400) throw InvalidInputException(detail);
    if (statusCode == 422) throw InvalidInputException(detail);
    throw ServerException('API Error ($statusCode): $detail');
  }

  // --- Interface Method Implementations ---

  @override
  Future<Feedback> submitFeedback(FeedbackSubmissionRequest request) async {
    final url = Uri.parse('$baseUrl/feedback/');
    try {
      final body = jsonEncode(request.toJson());

      final response = await client.post(
        url,
        headers: await _getHeaders(),
        body: body,
      );

      _handleResponseErrors(response);

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      return Feedback.fromJson(responseData);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error submitting feedback: $e');
    }
  }

  @override
  Future<FeedbackListResponse> getFeedbackList() async {
    final url = Uri.parse('$baseUrl/feedback/');
    try {
      final response = await client.get(url, headers: await _getHeaders());

      _handleResponseErrors(response);

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      return FeedbackListResponse.fromJson(responseData);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error getting feedback list: $e');
    }
  }
}
