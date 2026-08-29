class GenerationAcceptedResponseSchema {
  final String requestId;
  final String status;
  final String message;

  GenerationAcceptedResponseSchema({
    required this.requestId,
    required this.status,
    required this.message,
  });

  factory GenerationAcceptedResponseSchema.fromJson(Map<String, dynamic> json) {
    return GenerationAcceptedResponseSchema(
      requestId: json['id'] as String? ?? '', // Expect 'id' field from API
      status: json['status'] as String? ?? 'unknown', // Provide default
      message: json['message'] as String? ?? '', // Provide default
    );
  }
}
