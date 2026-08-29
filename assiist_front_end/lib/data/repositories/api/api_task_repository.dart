import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:assiist_front_end/core/models/task.dart';
import 'package:assiist_front_end/core/repositories/task_repository.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart';
import 'package:assiist_front_end/core/models/generation_accepted_response.dart';
import 'package:assiist_front_end/services/auth_service.dart';

class ApiTaskRepository implements TaskRepository {
  final String baseUrl; // e.g., http://localhost:8000/api/v1
  final AuthService _authService;
  final http.Client client;

  ApiTaskRepository({
    required this.baseUrl,
    required AuthService authService,
    http.Client? httpClient,
  }) : client = httpClient ?? http.Client(),
       _authService = authService;

  // --- Helpers (Copied from ApiContactRepository) ---

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
  Future<Task> createTask(Task task) async {
    // Backend endpoint likely POST /api/v1/tasks
    // Let's assume backend extracts contact_id and user_id from context/token
    // OR expects contact_id in the body. Task.toJson() should include it.
    // USE THE CORRECT ENDPOINT: /contacts/{contact_id}/tasks
    if (task.contactId == null) {
      throw InvalidInputException('Contact ID is required to create a task.');
    }
    final url = Uri.parse(
      '$baseUrl/contacts/${task.contactId}/tasks',
    ); // Use correct endpoint
    try {
      // task.toJson() already includes contactId
      final bodyMap = task.toJson();
      // REMOVE explicit setting of contact_id
      final body = jsonEncode(bodyMap);

      final response = await client.post(
        url,
        headers: await _getHeaders(),
        body: body,
      );

      _handleResponseErrors(response);

      final responseData =
          jsonDecode(response.body)
              as Map<String, dynamic>; // Assume it's a map
      final String taskId =
          responseData['id'] ?? ''; // Handle potential null ID
      return Task.fromJson(responseData, taskId);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error creating task: $e');
    }
  }

  @override
  Future<bool> deleteTask(String taskId, String contactId) async {
    // Use correct endpoint
    final url = Uri.parse('$baseUrl/contacts/$contactId/tasks/$taskId');
    try {
      final response = await client.delete(url, headers: await _getHeaders());

      _handleResponseErrors(response);

      return response.statusCode == 204;
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error deleting task: $e');
    }
  }

  @override
  Future<Task?> getById(String taskId, String contactId) async {
    // Use correct endpoint
    final url = Uri.parse('$baseUrl/contacts/$contactId/tasks/$taskId');
    try {
      final response = await client.get(url, headers: await _getHeaders());

      if (response.statusCode == 404) {
        return null;
      }

      _handleResponseErrors(response);

      final responseData =
          jsonDecode(response.body)
              as Map<String, dynamic>; // Assume it's a map
      final String taskId =
          responseData['id'] ?? ''; // Handle potential null ID
      return Task.fromJson(responseData, taskId);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      return null;
    }
  }

  @override
  Future<List<Task>> getTasksForContact(String contactId) async {
    final url = Uri.parse('$baseUrl/contacts/$contactId/tasks');
    try {
      final response = await client.get(url, headers: await _getHeaders());

      _handleResponseErrors(response);

      final List<dynamic> responseData = jsonDecode(response.body);
      final tasks =
          responseData.map((data) {
            final mapData = data as Map<String, dynamic>;
            final String taskId = mapData['id'] ?? '';
            return Task.fromJson(mapData, taskId);
          }).toList();
      return tasks;
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error getting tasks for contact: $e');
    }
  }

  @override
  Future<List<Task>> getAllTasksForUser() async {
    final url = Uri.parse('$baseUrl/tasks'); // Add query params if needed
    try {
      final response = await client.get(url, headers: await _getHeaders());

      _handleResponseErrors(response);

      final List<dynamic> responseData = jsonDecode(response.body);

      return responseData.map((data) {
        final mapData = data as Map<String, dynamic>;
        final String taskId = mapData['id'] ?? '';

        return Task.fromJson(mapData, taskId);
      }).toList();
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error getting all tasks for user: $e');
    }
  }

  @override
  Future<Task?> updateTask(
    String taskId,
    String contactId,
    Map<String, dynamic> updateData,
  ) async {
    final urlString = '$baseUrl/contacts/$contactId/tasks/$taskId';
    final url = Uri.parse(urlString);

    try {
      final body = jsonEncode(updateData);
      final response = await client.patch(
        url,
        headers: await _getHeaders(),
        body: body,
      );

      _handleResponseErrors(response);

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;

      final String responseTaskId = responseData['id'] ?? taskId;
      return Task.fromJson(responseData, responseTaskId);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect for task update: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error updating task: $e');
    }
  }

  @override
  Future<Task?> getTaskById(String taskId) async {
    // Direct task lookup endpoint - more efficient than searching through all tasks
    final url = Uri.parse('$baseUrl/tasks/$taskId');
    try {
      final response = await client.get(url, headers: await _getHeaders());

      if (response.statusCode == 404) {
        return null;
      }

      _handleResponseErrors(response);

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      final String responseTaskId = responseData['id'] ?? taskId;
      return Task.fromJson(responseData, responseTaskId);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      return null;
    }
  }
}
