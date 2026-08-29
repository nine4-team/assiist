import 'package:assiist_front_end/core/models/note.dart';

abstract class NoteRepository {
  /// Creates a new note associated with a contact.
  Future<Note> createNote(Note note, String contactId);

  /// Retrieves all notes associated with a specific contact.
  Future<List<Note>> getNotesForContact(String contactId);

  /// Retrieves a specific note by its ID.
  Future<Note?> getNoteById(String contactId, String noteId);

  // Potential future methods:
  // Future<Note?> getNoteById(String noteId);
  // Future<Note?> updateNote(String noteId, Map<String, dynamic> updateData);
  // Future<bool> deleteNote(String noteId);
}
