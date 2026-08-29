/// Utility functions for generation request operations
class GenerationRequestUtils {
  /// Returns the unified collection name for all GenAI operations
  /// All operations now use the single 'genai_requests' collection with request_type filtering
  static String getCollectionForOperation(String operationType) {
    // All operations now use the unified collection
    return 'genai_requests';
  }

  /// Maps operation type to request_type field value for Firestore queries
  /// This is used to filter documents in the unified genai_requests collection
  static String getRequestTypeForOperation(String operationType) {
    switch (operationType) {
      case 'quick_draft':
        return 'quick_draft';
      case 'revise_draft':
        return 'revise_draft';
      case 'process_note':
        return 'process_note';
      case 'update_tasks':
        return 'update_tasks';
      case 'update_context':
        return 'update_context';
      default:
        throw Exception('Unknown operation type: $operationType');
    }
  }

  /// Determines if an operation requires a frontend listener
  /// Task operations (quick_draft, revise_draft) need listeners for navigation
  /// Background operations (process_note, update_tasks, update_context) do not
  static bool requiresListener(String operationType) {
    switch (operationType) {
      case 'quick_draft':
      case 'revise_draft':
        return true; // These need listeners for task navigation
      case 'process_note':
      case 'update_tasks':
      case 'update_context':
        return false; // These are background operations
      default:
        return false;
    }
  }

  /// Helper method to build Firestore query filters for the unified collection
  /// Usage: query.where('request_type', isEqualTo: getRequestTypeForOperation(operationType))
  static Map<String, dynamic> getQueryFilters(
    String operationType,
    String userId,
  ) {
    return {
      'request_type': getRequestTypeForOperation(operationType),
      'user_id': userId,
    };
  }
}
