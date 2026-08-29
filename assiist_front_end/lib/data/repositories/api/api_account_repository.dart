import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:assiist_front_end/core/repositories/account_repository.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart';
import 'package:assiist_front_end/services/auth_service.dart';
import 'package:assiist_front_end/core/models/account_details.dart';

class ApiAccountRepository implements AccountRepository {
  final String baseUrl;
  final AuthService _authService;
  final http.Client client;

  ApiAccountRepository({
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

    String detail = 'Unknown API error';
    try {
      final responseBody = jsonDecode(response.body);
      if (responseBody is Map && responseBody.containsKey('detail')) {
        detail = responseBody['detail'];
      } else {
        detail = response.reasonPhrase ?? response.body;
      }
    } catch (_) {
      detail = response.reasonPhrase ?? response.body;
    }

    if (statusCode == 404) throw NotFoundException(detail);
    if (statusCode == 401 || statusCode == 403) {
      throw UnauthorizedException(detail);
    }
    if (statusCode == 400) throw InvalidInputException(detail);
    throw ServerException('API Error ($statusCode): $detail');
  }

  @override
  Future<AccountDetailsResponse?> getAccountDetails() async {
    final url = Uri.parse('$baseUrl/accounts/details');
    try {
      final response = await client.get(url, headers: await _getHeaders());

      if (response.statusCode == 404) {
        return AccountDetailsResponse(
          businessDescription: null,
          businessType: null,
        );
      }
      _handleResponseErrors(response);

      final responseData = jsonDecode(response.body);
      return AccountDetailsResponse.fromJson(responseData);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect to account details: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      print(
        'ApiAccountRepository: Unexpected error getting account details: $e',
      );
      return AccountDetailsResponse(
        businessDescription: null,
        businessType: null,
      );
    }
  }

  @override
  Future<AccountDetailsResponse> updateAccountDetails(
    AccountDetailsUpdateRequest request,
  ) async {
    final url = Uri.parse('$baseUrl/accounts/details');
    try {
      final body = jsonEncode(request.toJson());
      final response = await client.put(
        url,
        headers: await _getHeaders(),
        body: body,
      );

      _handleResponseErrors(response);
      final responseData = jsonDecode(response.body);
      return AccountDetailsResponse.fromJson(responseData);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect to update account details: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error updating account details: $e');
    }
  }

  @Deprecated('Use getAccountDetails instead')
  Future<String?> getBusinessDescription() async {
    final details = await getAccountDetails();
    return details?.businessDescription;
  }

  @Deprecated('Use updateAccountDetails instead')
  Future<void> updateBusinessDescription(String description) async {
    await updateAccountDetails(
      AccountDetailsUpdateRequest(businessDescription: description),
    );
  }

  @Deprecated('Use getAccountDetails instead')
  Future<String?> getBusinessType() async {
    final details = await getAccountDetails();
    return details?.businessType;
  }

  @Deprecated('Use updateAccountDetails instead')
  Future<void> updateBusinessType(String type) async {
    await updateAccountDetails(AccountDetailsUpdateRequest(businessType: type));
  }

  @override
  Future<String> getAccountId() async {
    final url = Uri.parse('$baseUrl/accounts/details');
    print('[DEBUG] Getting account ID from: $url');
    try {
      final headers = await _getHeaders();
      print('[DEBUG] Got headers: ${headers.keys.join(', ')}');
      final response = await client.get(url, headers: headers);
      print(
        '[DEBUG] Account details response: ${response.statusCode} ${response.body}',
      );
      _handleResponseErrors(response);
      final responseData = jsonDecode(response.body);
      final accountId = responseData['id'] as String;
      print('[DEBUG] Parsed account ID: $accountId');
      return accountId;
    } on http.ClientException catch (e) {
      print('[DEBUG] Network error getting account ID: $e');
      throw NetworkException('Failed to connect to get account ID: $e');
    } catch (e) {
      print('[DEBUG] Error getting account ID: $e');
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error getting account ID: $e');
    }
  }
}
