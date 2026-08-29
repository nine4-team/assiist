import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:assiist_front_end/core/models/appointment.dart';
import 'package:assiist_front_end/core/repositories/appointment_repository.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart';
import 'package:assiist_front_end/services/auth_service.dart';

class ApiAppointmentRepository implements AppointmentRepository {
  final String baseUrl;
  final AuthService _authService;
  final http.Client client;

  ApiAppointmentRepository({
    required this.baseUrl,
    required AuthService authService,
    http.Client? httpClient,
  }) : client = httpClient ?? http.Client(),
       _authService = authService;

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
    if (statusCode >= 200 && statusCode < 300) return;
    final detail = response.reasonPhrase ?? 'Unknown API error';
    if (statusCode == 404) throw NotFoundException(detail);
    if (statusCode == 401 || statusCode == 403)
      throw UnauthorizedException(detail);
    if (statusCode == 400) throw InvalidInputException(detail);
    throw ServerException('API Error ($statusCode): $detail');
  }
  // --- End Helpers ---

  @override
  Future<List<Appointment>> getAppointmentsForContact(String contactId) async {
    // Use the new backend endpoint
    final url = Uri.parse('$baseUrl/contacts/$contactId/appointments');
    print(
      "ApiAppointmentRepository: Fetching appointments for contact $contactId from $url",
    );

    try {
      final response = await client.get(url, headers: await _getHeaders());

      // Handle 404 specifically: return empty list
      if (response.statusCode == 404) {
        print(
          "ApiAppointmentRepository: No appointments found (404) for contact $contactId, returning empty list.",
        );
        return [];
      }

      _handleResponseErrors(response);

      final List<dynamic> responseData = jsonDecode(response.body);
      return responseData.map((data) {
        final mapData = data as Map<String, dynamic>;
        final String appointmentId = mapData['id'] ?? '';
        return Appointment.fromJson(mapData, appointmentId);
      }).toList();
    } on http.ClientException catch (e) {
      print("ApiAppointmentRepository: Network error getting appointments: $e");
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      print(
        "ApiAppointmentRepository: Unexpected error getting appointments: $e",
      );
      throw ServerException('Unexpected error getting appointments: $e');
    }
  }

  @override
  Future<Appointment?> getAppointmentById(String appointmentId) async {
    // Use the user-level endpoint
    final url = Uri.parse('$baseUrl/appointments/$appointmentId');
    print(
      "ApiAppointmentRepository: Fetching appointment $appointmentId from $url",
    );

    try {
      final response = await client.get(url, headers: await _getHeaders());

      // Handle 404 specifically - Appointment not found for the user
      if (response.statusCode == 404) {
        print(
          "ApiAppointmentRepository: Appointment $appointmentId not found (404).",
        );
        return null; // Return null if not found
      }

      _handleResponseErrors(response);

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      // Appointment.fromJson expects the ID separately
      return Appointment.fromJson(responseData, appointmentId);
    } on http.ClientException catch (e) {
      print(
        "ApiAppointmentRepository: Network error getting appointment $appointmentId: $e",
      );
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      print(
        "ApiAppointmentRepository: Unexpected error getting appointment $appointmentId: $e",
      );
      throw ServerException(
        'Unexpected error getting appointment $appointmentId: $e',
      );
    }
  }

  @override
  Future<List<Appointment>> getAllAppointmentsForUser() async {
    // Use the user-level endpoint to get all appointments
    final url = Uri.parse('$baseUrl/appointments');
    print("ApiAppointmentRepository: Fetching all appointments from $url");

    try {
      final response = await client.get(url, headers: await _getHeaders());

      // Handle 404 specifically: return empty list
      if (response.statusCode == 404) {
        print(
          "ApiAppointmentRepository: No appointments found (404), returning empty list.",
        );
        return [];
      }

      _handleResponseErrors(response);

      final List<dynamic> responseData = jsonDecode(response.body);
      return responseData.map((data) {
        final mapData = data as Map<String, dynamic>;
        final String appointmentId = mapData['id'] ?? '';
        return Appointment.fromJson(mapData, appointmentId);
      }).toList();
    } on http.ClientException catch (e) {
      print("ApiAppointmentRepository: Network error getting appointments: $e");
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      print(
        "ApiAppointmentRepository: Unexpected error getting appointments: $e",
      );
      throw ServerException('Unexpected error getting appointments: $e');
    }
  }
}
