import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:assiist_front_end/core/models/calendar_connection.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart';
import 'package:assiist_front_end/services/auth_service.dart';

class ApiCalendarConnectionsRepository {
  final String baseUrl;
  final AuthService _authService;

  ApiCalendarConnectionsRepository({
    required this.baseUrl,
    required AuthService authService,
  }) : _authService = authService;

  Future<Map<String, String>> _getHeaders() async {
    final headers = {'Content-Type': 'application/json'};
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

  Future<List<CalendarConnection>> fetchCalendars() async {
    final response = await http.get(
      Uri.parse('$baseUrl/calendars'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((e) => CalendarConnection.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load calendars: ${response.body}');
    }
  }

  Future<void> removeCalendar(String email) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/calendars/$email'),
      headers: await _getHeaders(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to remove calendar: ${response.body}');
    }
  }
}
