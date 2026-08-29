// Base class for all API-related exceptions
class ApiException implements Exception {
  final String message;
  final int? statusCode; // Optional: Store HTTP status code

  ApiException(this.message, {this.statusCode});

  @override
  String toString() {
    return 'ApiException: $message${statusCode != null ? ' (Status Code: $statusCode)' : ''}';
  }
}

// Specific exception for network connectivity issues
class NetworkException extends ApiException {
  NetworkException(String message) : super(message);

  @override
  String toString() => 'NetworkException: $message';
}

// Specific exception for server errors (e.g., 5xx)
class ServerException extends ApiException {
  ServerException(String message, {int? statusCode})
    : super(message, statusCode: statusCode);

  @override
  String toString() =>
      'ServerException: $message${statusCode != null ? ' (Status Code: $statusCode)' : ''}';
}

// Specific exception for authentication/authorization errors (401, 403)
class UnauthorizedException extends ApiException {
  UnauthorizedException(String message, {int? statusCode})
    : super(message, statusCode: statusCode);

  @override
  String toString() =>
      'UnauthorizedException: $message${statusCode != null ? ' (Status Code: $statusCode)' : ''}';
}

// Specific exception for resource not found errors (404)
class NotFoundException extends ApiException {
  NotFoundException(String message, {int? statusCode})
    : super(message, statusCode: statusCode);

  @override
  String toString() =>
      'NotFoundException: $message${statusCode != null ? ' (Status Code: $statusCode)' : ''}';
}

// Specific exception for invalid input errors (400)
class InvalidInputException extends ApiException {
  // Optional: Add a field to hold specific validation errors if provided by API
  // final Map<String, dynamic>? errors;

  InvalidInputException(String message, {int? statusCode /*, this.errors*/})
    : super(message, statusCode: statusCode);

  @override
  String toString() =>
      'InvalidInputException: $message${statusCode != null ? ' (Status Code: $statusCode)' : ''}';
}

// Specific exception for duplicate contact (409)
class DuplicateContactException extends ApiException {
  final String existingContactId;
  final String field; // 'email' or 'phone'
  final String value;

  DuplicateContactException({
    required this.existingContactId,
    required this.field,
    required this.value,
    String message = 'Duplicate contact detected',
    int? statusCode,
  }) : super(message, statusCode: statusCode);

  @override
  String toString() =>
      'DuplicateContactException: $message (existingContactId: $existingContactId)';
}

// Specific exception for data parsing/format errors
class DataParsingException extends ApiException {
  DataParsingException(String message) : super(message);

  @override
  String toString() => 'DataParsingException: $message';
}

// Add other specific exceptions as needed (e.g., DataParsingException)
