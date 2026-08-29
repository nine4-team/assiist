class CalendarConnection {
  final String provider;
  final String email;
  final String? accessToken;
  final String? idToken;
  final String? createdOn;
  final String? refreshToken;
  final String? tokenExpiry;
  final List<String>? scopes;
  final String? syncStatus;
  final String? syncStatusMessage;
  final String? icsUrl;

  CalendarConnection({
    required this.provider,
    required this.email,
    this.accessToken,
    this.idToken,
    this.createdOn,
    this.refreshToken,
    this.tokenExpiry,
    this.scopes,
    this.syncStatus,
    this.syncStatusMessage,
    this.icsUrl,
  });

  factory CalendarConnection.fromJson(Map<String, dynamic> json) {
    return CalendarConnection(
      provider: json['provider'] as String,
      email: json['email'] as String,
      accessToken: json['access_token'] as String?,
      idToken: json['id_token'] as String?,
      createdOn: json['created_on'] as String?,
      refreshToken: json['refresh_token'] as String?,
      tokenExpiry: json['token_expiry'] as String?,
      scopes: json['scopes'] != null ? List<String>.from(json['scopes']) : null,
      syncStatus: json['sync_status'] as String?,
      syncStatusMessage: json['sync_status_message'] as String?,
      icsUrl: json['ics_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'email': email,
      'access_token': accessToken,
      'id_token': idToken,
      'created_on': createdOn,
      'refresh_token': refreshToken,
      'token_expiry': tokenExpiry,
      'scopes': scopes,
      'sync_status': syncStatus,
      'sync_status_message': syncStatusMessage,
      'ics_url': icsUrl,
    };
  }
}
