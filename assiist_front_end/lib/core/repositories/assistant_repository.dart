import 'package:assiist_front_end/core/models/generation_accepted_response.dart';

/// Abstract interface for AI assistant operations.
abstract class AssistantRepository {
  /// Submit a message revision request to the AI assistant
  Future<Map<String, dynamic>> reviseDraft(
    Map<String, dynamic> revisionPayload,
  );

  /// Submit a quick draft generation request to the AI assistant
  Future<Map<String, dynamic>> quickDraft(Map<String, dynamic> draftPayload);

  /// Submit a quick task generation request to the AI assistant
  Future<GenerationAcceptedResponseSchema> requestQuickTaskGeneration(
    String contactId,
    String instructions,
  );

  /// Submit a quick draft generation request to the AI assistant
  Future<GenerationAcceptedResponseSchema> requestQuickDraftGeneration(
    String contactId,
    String instructions,
    String language,
  );

  /// Submit an update assistant request (processes notes through AI)
  Future<Map<String, dynamic>> updateAssistant(
    Map<String, dynamic> updatePayload,
  );
}
