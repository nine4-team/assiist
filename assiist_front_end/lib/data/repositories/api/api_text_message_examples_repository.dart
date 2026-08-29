import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:assiist_front_end/core/models/text_message_example.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart';
import 'package:assiist_front_end/services/auth_service.dart';

class ApiTextMessageExamplesRepository {
  final String baseUrl;
  final AuthService _authService;
  final http.Client client;

  ApiTextMessageExamplesRepository({
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
    if (statusCode == 401 || statusCode == 403) {
      throw UnauthorizedException(detail);
    }
    if (statusCode == 400) throw InvalidInputException(detail);
    throw ServerException('API Error ($statusCode): $detail');
  }

  Future<List<TextMessageExample>> fetchExamples() async {
    final url = Uri.parse('$baseUrl/users/text-message-examples');
    try {
      final response = await client.get(url, headers: await _getHeaders());
      if (response.statusCode == 404) return [];
      _handleResponseErrors(response);
      final List<dynamic> responseData = jsonDecode(response.body);
      return responseData
          .map((data) => TextMessageExample.fromJson(data))
          .toList();
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error fetching examples: $e');
    }
  }

  Future<TextMessageExample> addExample(String text) async {
    final url = Uri.parse('$baseUrl/users/text-message-examples');
    try {
      final body = jsonEncode({'example_text': text});
      final response = await client.post(
        url,
        headers: await _getHeaders(),
        body: body,
      );
      _handleResponseErrors(response);
      final responseData = jsonDecode(response.body);
      return TextMessageExample.fromJson(responseData);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error adding example: $e');
    }
  }

  Future<TextMessageExample> updateExample(
    String exampleId,
    String newText,
  ) async {
    final url = Uri.parse('$baseUrl/users/text-message-examples/$exampleId');
    try {
      final body = jsonEncode({'example_text': newText});
      final response = await client.patch(
        url,
        headers: await _getHeaders(),
        body: body,
      );
      _handleResponseErrors(response);
      final responseData = jsonDecode(response.body);
      return TextMessageExample.fromJson(responseData);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error updating example: $e');
    }
  }

  Future<void> deleteExample(String exampleId) async {
    final url = Uri.parse('$baseUrl/users/text-message-examples/$exampleId');
    try {
      final response = await client.delete(url, headers: await _getHeaders());
      _handleResponseErrors(response);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error deleting example: $e');
    }
  }
}
