class Feedback {
  final String id;
  final String accountId;
  final String userId;
  final String feedbackText;
  final String feedbackType;
  final String userEmail;
  final String userName;
  final String? appVersion;
  final String? platform;
  final String? screenContext;
  final DateTime createdOn;
  final String status;

  const Feedback({
    required this.id,
    required this.accountId,
    required this.userId,
    required this.feedbackText,
    required this.feedbackType,
    required this.userEmail,
    required this.userName,
    this.appVersion,
    this.platform,
    this.screenContext,
    required this.createdOn,
    required this.status,
  });

  factory Feedback.fromJson(Map<String, dynamic> json) {
    return Feedback(
      id: json['id'] as String,
      accountId: json['account_id'] as String,
      userId: json['user_id'] as String,
      feedbackText: json['feedback_text'] as String,
      feedbackType: json['feedback_type'] as String,
      userEmail: json['user_email'] as String,
      userName: json['user_name'] as String,
      appVersion: json['app_version'] as String?,
      platform: json['platform'] as String?,
      screenContext: json['screen_context'] as String?,
      createdOn: DateTime.parse(json['created_on'] as String),
      status: json['status'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'account_id': accountId,
      'user_id': userId,
      'feedback_text': feedbackText,
      'feedback_type': feedbackType,
      'user_email': userEmail,
      'user_name': userName,
      'app_version': appVersion,
      'platform': platform,
      'screen_context': screenContext,
      'created_on': createdOn.toIso8601String(),
      'status': status,
    };
  }
}

class FeedbackSubmissionRequest {
  final String feedbackText;
  final String feedbackType;
  final String? appVersion;
  final String? platform;
  final String? screenContext;

  const FeedbackSubmissionRequest({
    required this.feedbackText,
    this.feedbackType = 'general',
    this.appVersion,
    this.platform,
    this.screenContext,
  });

  Map<String, dynamic> toJson() {
    return {
      'feedback_text': feedbackText,
      'feedback_type': feedbackType,
      if (appVersion != null) 'app_version': appVersion,
      if (platform != null) 'platform': platform,
      if (screenContext != null) 'screen_context': screenContext,
    };
  }
}

class FeedbackListResponse {
  final List<Feedback> feedback;
  final int totalCount;

  const FeedbackListResponse({
    required this.feedback,
    required this.totalCount,
  });

  factory FeedbackListResponse.fromJson(Map<String, dynamic> json) {
    final feedbackList =
        (json['feedback'] as List)
            .map((item) => Feedback.fromJson(item as Map<String, dynamic>))
            .toList();

    return FeedbackListResponse(
      feedback: feedbackList,
      totalCount: json['total_count'] as int,
    );
  }
}
