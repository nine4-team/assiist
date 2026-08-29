import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:assiist_front_end/core/models/note.dart';
import 'package:assiist_front_end/core/repositories/note_repository.dart';
import 'package:assiist_front_end/core/errors/exceptions.dart';
import 'package:assiist_front_end/services/auth_service.dart';

class ApiNoteRepository implements NoteRepository {
  final String baseUrl; // e.g., http://localhost:8000/api/v1
  final AuthService _authService;
  final http.Client client;

  ApiNoteRepository({
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

    final detail =
        response.reasonPhrase ?? 'Unknown API error'; // Simple fallback
    // TODO: Enhance error parsing from response body

    if (statusCode == 404) throw NotFoundException(detail);
    if (statusCode == 401 || statusCode == 403) {
      throw UnauthorizedException(detail);
    }
    if (statusCode == 400) throw InvalidInputException(detail);
    throw ServerException('API Error ($statusCode): $detail');
  }

  // --- Interface Method Implementations ---

  @override
  Future<Note> createNote(Note note, String contactId) async {
    // Backend endpoint likely POST /notes
    // Assumes backend expects contact_id and body in the request payload
    // and determines user_id from the auth token.
    final url = Uri.parse('$baseUrl/notes');
    try {
      // --- Build Request Body Manually ---
      // Only send fields required by the backend for creation.
      final Map<String, dynamic> requestBodyMap = {
        'raw_note': note.rawNote,
        'contact_id': contactId, // Ensure contactId is included
      };
      final body = jsonEncode(requestBodyMap);
      // print("DEBUG: Sending Note body for create: $body"); // Debug print

      final response = await client.post(
        url,
        headers: await _getHeaders(),
        body: body,
      );

      _handleResponseErrors(response);

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      final String noteId =
          responseData['id'] ?? ''; // Handle potential null ID
      // The response data from the backend should contain the correct
      // id, userId, createdOn, etc., which Note.fromJson will use.
      return Note.fromJson(responseData, noteId);
    } on http.ClientException catch (e) {
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ServerException('Unexpected error creating note: $e');
    }
  }

  @override
  Future<List<Note>> getNotesForContact(String contactId) async {
    // Correct the URL to match the backend router prefix
    final url = Uri.parse('$baseUrl/contacts/$contactId/notes');
    print("ApiNoteRepository: Fetching notes for contact $contactId from $url");

    try {
      final response = await client.get(url, headers: await _getHeaders());

      // Specific handling for 404: return empty list, not an error
      if (response.statusCode == 404) {
        print(
          "ApiNoteRepository: No notes found (404) for contact $contactId, returning empty list.",
        );
        return [];
      }

      _handleResponseErrors(response);

      final List<dynamic> responseData = jsonDecode(response.body);
      return responseData.map((data) {
        final mapData = data as Map<String, dynamic>;
        // Assume 'id' is present in the response, provide default if needed
        final String noteId = mapData['id'] ?? '';
        return Note.fromJson(mapData, noteId);
      }).toList();
    } on http.ClientException catch (e) {
      print("ApiNoteRepository: Network error getting notes: $e");
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      print("ApiNoteRepository: Unexpected error getting notes: $e");
      throw ServerException('Unexpected error getting notes: $e');
    }
  }

  @override
  Future<Note?> getNoteById(String contactId, String noteId) async {
    final url = Uri.parse('$baseUrl/contacts/$contactId/notes/$noteId');
    print(
      "ApiNoteRepository: Fetching note $noteId for contact $contactId from $url",
    );

    try {
      final response = await client.get(url, headers: await _getHeaders());

      // Handle 404 specifically - Note not found
      if (response.statusCode == 404) {
        print(
          "ApiNoteRepository: Note $noteId not found (404) for contact $contactId.",
        );
        return null; // Return null if not found
      }

      _handleResponseErrors(response);

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      // Note.fromJson expects the ID separately, which we already have
      return Note.fromJson(responseData, noteId);
    } on http.ClientException catch (e) {
      print("ApiNoteRepository: Network error getting note $noteId: $e");
      throw NetworkException('Failed to connect: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      print("ApiNoteRepository: Unexpected error getting note $noteId: $e");
      throw ServerException('Unexpected error getting note $noteId: $e');
    }
  }

  // The NoteRepository interface doesn't have update/delete/getAll.
  // If these are needed later, they can be added to the interface and implemented here.
}
