import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assiist_front_end/core/models/user_profile.dart';
import 'package:assiist_front_end/core/repositories/user_profile_repository.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart';
import 'package:assiist_front_end/services/auth_service.dart';

class ApiUserProfileRepository implements UserProfileRepository {
  final String baseUrl;
  final AuthService _authService;
  final http.Client client;

  ApiUserProfileRepository({
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

  @override
  Future<UserProfile> getUserProfile() async {
    final token = await _authService.currentUser?.getIdToken();
    if (token == null) {
      throw Exception('No authentication token available');
    }

    final response = await client.get(
      Uri.parse('${baseUrl}/users/${_authService.currentUser?.uid}'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('[DEBUG] API Response data: $data'); // Debug log

      return UserProfile(
        id: data['id'] as String? ?? '', // Backend user ID
        firebaseUid: _authService.currentUser?.uid ?? '', // Firebase UID
        email: data['email'] as String?,
        firstName: data['first_name'] as String?,
        lastName: data['last_name'] as String?,
        displayName: null,
        createdOn:
            data['created_on'] != null
                ? Timestamp.fromDate(DateTime.parse(data['created_on']))
                : null,
        accountId: data['account_id'] as String?,
      );
    } else if (response.statusCode == 404) {
      throw NotFoundException('User profile not found');
    } else {
      throw Exception('Failed to get user profile: ${response.statusCode}');
    }
  }

  @override
  Future<UserProfile?> updateUserProfile(UserProfile profile) async {
    final url = Uri.parse('$baseUrl/users/me');
    try {
      final body = jsonEncode({
        'first_name': profile.firstName,
        'last_name': profile.lastName,
      });
      final response = await client.patch(
        url,
        headers: await _getHeaders(),
        body: body,
      );
      _handleResponseErrors(response);
      final responseData = jsonDecode(response.body);
      return UserProfile(
        id: responseData['id'] as String? ?? '', // Backend user ID
        firebaseUid: _authService.currentUser?.uid ?? '', // Firebase UID
        email: responseData['email'] as String?,
        firstName: responseData['first_name'] as String?,
        lastName: responseData['last_name'] as String?,
        displayName: null,
        createdOn: null,
        accountId: responseData['account_id'] as String?,
      );
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error updating user profile: $e');
    }
  }
}
