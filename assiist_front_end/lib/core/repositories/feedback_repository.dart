import 'package:assiist_front_end/core/models/feedback.dart';

abstract class FeedbackRepository {
  Future<Feedback> submitFeedback(FeedbackSubmissionRequest request);
  Future<FeedbackListResponse> getFeedbackList();
}
