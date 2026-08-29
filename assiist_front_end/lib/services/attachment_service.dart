import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:assiist_front_end/core/models/attachment.dart';
import 'package:assiist_front_end/providers/auth_providers.dart';
import 'package:assiist_front_end/services/auth_service.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart';
import 'package:http_parser/http_parser.dart';

class AttachmentService {
  final String baseUrl;
  final AuthService _authService;

  AttachmentService({required this.baseUrl, required AuthService authService})
    : _authService = authService;

  /// Get fresh auth headers for API requests
  Future<Map<String, String>> _getHeaders() async {
    final headers = {'Content-Type': 'application/json; charset=UTF-8'};

    print('DEBUG: Getting fresh auth token...');
    try {
      final String? freshToken = await _authService.getFreshAuthToken();
      print(
        'DEBUG: Fresh token received: ${freshToken != null ? "Yes" : "No"}',
      );

      if (freshToken != null) {
        headers['Authorization'] = 'Bearer $freshToken';
        print('DEBUG: Auth header set successfully');
      } else {
        print('DEBUG: Fresh token is null, throwing UnauthorizedException');
        throw UnauthorizedException(
          'User not authenticated or token refresh failed.',
        );
      }
    } catch (e) {
      print('DEBUG: Error getting fresh token: $e');
      rethrow;
    }

    return headers;
  }

  /// Upload a file to the backend and return attachment metadata
  Future<Attachment> uploadFile(File file) async {
    try {
      final uri = Uri.parse('$baseUrl/notes/upload-attachment');

      final request = http.MultipartRequest('POST', uri);

      // Get fresh auth headers
      final authHeaders = await _getHeaders();
      if (authHeaders['Authorization'] != null) {
        request.headers['Authorization'] = authHeaders['Authorization']!;
        print('DEBUG: Using fresh auth token for upload');
      }

      // Add the file with proper MIME type
      final fileStream = http.ByteStream(file.openRead());
      final fileLength = await file.length();
      final fileName = file.path.split('/').last;

      // Determine MIME type based on file extension
      MediaType? contentType;
      final extension = fileName.toLowerCase().split('.').last;
      switch (extension) {
        case 'jpg':
        case 'jpeg':
          contentType = MediaType('image', 'jpeg');
          break;
        case 'png':
          contentType = MediaType('image', 'png');
          break;
        case 'gif':
          contentType = MediaType('image', 'gif');
          break;
        case 'webp':
          contentType = MediaType('image', 'webp');
          break;
        case 'pdf':
          contentType = MediaType('application', 'pdf');
          break;
        case 'txt':
          contentType = MediaType('text', 'plain');
          break;
        case 'csv':
          contentType = MediaType('text', 'csv');
          break;
        case 'doc':
          contentType = MediaType('application', 'msword');
          break;
        case 'docx':
          contentType = MediaType(
            'application',
            'vnd.openxmlformats-officedocument.wordprocessingml.document',
          );
          break;
        case 'xls':
          contentType = MediaType('application', 'vnd.ms-excel');
          break;
        case 'xlsx':
          contentType = MediaType(
            'application',
            'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          );
          break;
        case 'ppt':
          contentType = MediaType('application', 'vnd.ms-powerpoint');
          break;
        case 'pptx':
          contentType = MediaType(
            'application',
            'vnd.openxmlformats-officedocument.presentationml.presentation',
          );
          break;
        case 'wav':
          contentType = MediaType('audio', 'wav');
          break;
        case 'm4a':
          contentType = MediaType('audio', 'x-m4a');
          break;
        case 'mp3':
          contentType = MediaType('audio', 'mp3');
          break;
        case 'mp4':
          contentType = MediaType('audio', 'mp4');
          break;
        case 'aac':
          contentType = MediaType('audio', 'aac');
          break;
        case 'mpeg':
          contentType = MediaType('audio', 'mpeg');
          break;
        default:
          contentType = MediaType('application', 'octet-stream');
      }

      final multipartFile = http.MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: fileName,
        contentType: contentType,
      );

      request.files.add(multipartFile);

      // Send the request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('DEBUG: Upload response status: ${response.statusCode}');
      print('DEBUG: Upload response body: ${response.body}');

      if (response.statusCode == 201) {
        try {
          final jsonData = json.decode(response.body) as Map<String, dynamic>;
          print('DEBUG: Parsed JSON data: $jsonData');
          final attachment = Attachment.fromJson(jsonData);
          print('DEBUG: Successfully created Attachment object');
          return attachment;
        } catch (e) {
          print('DEBUG: Error parsing JSON or creating Attachment: $e');
          print('DEBUG: Raw response body: ${response.body}');
          throw AttachmentUploadException(
            'Failed to parse upload response: $e',
          );
        }
      } else {
        print(
          'DEBUG: Upload failed - Status: ${response.statusCode}, Body: ${response.body}',
        );
        throw AttachmentUploadException(
          'Upload failed with status ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      if (e is AttachmentUploadException) {
        rethrow;
      }
      throw AttachmentUploadException('Failed to upload file: $e');
    }
  }

  /// Validate file before upload
  bool validateFile(File file) {
    // Check file size (10MB limit)
    const maxSize = 10 * 1024 * 1024; // 10MB
    if (file.lengthSync() > maxSize) {
      throw AttachmentValidationException('File size exceeds 10MB limit');
    }

    // Check file extension
    final fileName = file.path.toLowerCase();
    final allowedExtensions = [
      '.jpg', '.jpeg', '.png', '.gif', '.webp', // Images
      '.pdf', '.txt', '.csv', // Documents
      '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', // Office docs
      '.wav', '.m4a', '.mp3', '.mp4', '.aac', '.mpeg', // Audio files
    ];

    final hasValidExtension = allowedExtensions.any(
      (ext) => fileName.endsWith(ext),
    );
    if (!hasValidExtension) {
      throw AttachmentValidationException('File type not supported');
    }

    return true;
  }
}

/// Exception thrown when file upload fails
class AttachmentUploadException implements Exception {
  final String message;
  AttachmentUploadException(this.message);

  @override
  String toString() => 'AttachmentUploadException: $message';
}

/// Exception thrown when file validation fails
class AttachmentValidationException implements Exception {
  final String message;
  AttachmentValidationException(this.message);

  @override
  String toString() => 'AttachmentValidationException: $message';
}
