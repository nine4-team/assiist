import 'package:assiist_front_end/core/models/task.dart';

/// Abstract interface for task data operations.
abstract class TaskRepository {
  /// Retrieves all tasks associated with a specific contact ID.
  Future<List<Task>> getTasksForContact(String contactId);

  /// Retrieves all tasks relevant to the current user (e.g., for the dashboard).
  /// Might involve filtering by status, due date, etc., depending on implementation.
  Future<List<Task>> getAllTasksForUser();

  /// Creates a new task directly.
  Future<Task> createTask(Task task);

  /// Updates an existing task.
  Future<Task?> updateTask(
    String taskId,
    String contactId, // Needed to locate the task in subcollection
    Map<String, dynamic> updates,
  );

  /// Deletes a task.
  Future<bool> deleteTask(
    String taskId,
    String contactId, // Needed to locate the task in subcollection
  );

  /// Retrieves a task by its ID and contact ID.
  Future<Task?> getById(String taskId, String contactId);

  /// Retrieves a task by ID without requiring contactId (direct lookup for performance)
  Future<Task?> getTaskById(String taskId);
}
