class Reservation {
  final String id;
  final String contactId;
  final String contactName;
  final String? contactEmail;
  final String? contactPhone;
  final String userId;
  final String accountId;
  final DateTime createdOn;
  final DateTime updatedOn;

  Reservation({
    required this.id,
    required this.contactId,
    required this.contactName,
    this.contactEmail,
    this.contactPhone,
    required this.userId,
    required this.accountId,
    required this.createdOn,
    required this.updatedOn,
  });

  factory Reservation.fromJson(Map<String, dynamic> json) {
    return Reservation(
      id: json['id'] as String,
      contactId: json['contact_id'] as String,
      contactName: json['contact_name'] as String,
      contactEmail: json['contact_email'] as String?,
      contactPhone: json['contact_phone'] as String?,
      userId: json['user_id'] as String,
      accountId: json['account_id'] as String,
      createdOn: DateTime.parse(json['created_on'] as String),
      updatedOn: DateTime.parse(json['updated_on'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'contact_id': contactId,
      'contact_name': contactName,
      'contact_email': contactEmail,
      'contact_phone': contactPhone,
      'user_id': userId,
      'account_id': accountId,
      'created_on': createdOn.toIso8601String(),
      'updated_on': updatedOn.toIso8601String(),
    };
  }
}
