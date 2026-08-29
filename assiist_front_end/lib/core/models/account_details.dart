class AccountDetailsResponse {
  final String? businessDescription;
  final String? businessType;

  AccountDetailsResponse({this.businessDescription, this.businessType});

  factory AccountDetailsResponse.fromJson(Map<String, dynamic> json) {
    return AccountDetailsResponse(
      businessDescription: json['business_description'] as String?,
      businessType: json['business_type'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (businessDescription != null)
      'business_description': businessDescription,
    if (businessType != null) 'business_type': businessType,
  };
}

class AccountDetailsUpdateRequest {
  final String? businessDescription;
  final String? businessType;

  AccountDetailsUpdateRequest({this.businessDescription, this.businessType});

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (businessDescription != null) {
      data['business_description'] = businessDescription;
    }
    if (businessType != null) {
      data['business_type'] = businessType;
    }
    return data;
  }
}
