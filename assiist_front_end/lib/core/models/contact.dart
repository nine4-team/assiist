import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore types
import 'package:assiist_front_end/utils/text_encoding_utils.dart'; // Import the universal text encoding utils

// ignore_for_file: non_constant_identifier_names

// Represents the main Contact structure based on Firestore plan
class Contact {
  final String id; // Document ID from Firestore path
  final String? account_id; // ADDED from backend
  final String? assigned_user; // UID
  final String? created_by; // UID
  final DateTime? created_on;
  final String? first_name;
  final String? last_name;
  final String? addressed_as; // ADDED from backend
  final DateTime? date_of_birth; // ADDED from backend
  // final String? company; // RENAMED
  final String? business_name; // RENAMED from company
  final String? business_type; // ADDED from backend
  final List<PhoneNumber>? phone_numbers;
  final List<EmailAddress>? emails;
  final List<Address>? addresses;
  final PersonalDetails? personal_details;
  final Map<String, RelationshipDetail>?
  relationship_details; // Map<UserId, Detail>
  final BusinessDetails? business_details;
  final String? source;
  final List<String>? tags;
  final DateTime? updated_on;
  final String? updated_by; // UID
  final bool is_deleted;
  final DateTime? last_contacted_on; // ADDED: Last contact timestamp
  final int? last_contacted_days; // ADDED: Days since last contact (computed)
  final bool isVip; // ADDED: VIP status
  final String?
  device_contact_uuid; // ADDED: iOS device contact UUID for sync tracking

  const Contact({
    required this.id,
    this.account_id,
    this.assigned_user,
    this.created_by,
    this.created_on,
    this.first_name,
    this.last_name,
    this.addressed_as,
    this.date_of_birth,
    // this.company,
    this.business_name,
    this.business_type,
    this.phone_numbers,
    this.emails,
    this.addresses,
    this.personal_details,
    this.relationship_details,
    this.business_details,
    this.source,
    this.tags,
    this.updated_on,
    this.updated_by,
    required this.is_deleted,
    this.last_contacted_on, // ADDED
    this.last_contacted_days, // ADDED
    this.isVip = false, // ADDED: VIP status
    this.device_contact_uuid, // ADDED: iOS device contact UUID
  });

  // Helper for display name
  String get displayName {
    if (first_name != null && last_name != null) {
      return '$first_name $last_name';
    } else if (first_name != null) {
      return first_name!;
    } else if (last_name != null) {
      return last_name!;
    } else if (business_name != null) {
      return business_name!;
    } else if (emails?.isNotEmpty ?? false) {
      return emails!.first.address ?? 'Unnamed Contact';
    } else if (phone_numbers?.isNotEmpty ?? false) {
      return phone_numbers!.first.number ?? 'Unnamed Contact';
    }
    return 'Unnamed Contact';
  }

  // Helper for last contacted display
  String get lastContactedDisplay {
    if (last_contacted_days == null) {
      return 'never';
    }

    final days = last_contacted_days!;
    if (days == 0) {
      return 'today';
    } else if (days == 1) {
      return '1d ago';
    } else if (days <= 7) {
      return '${days}d ago';
    } else if (days <= 30) {
      final weeks = (days / 7).round();
      return '${weeks}w ago';
    } else if (days <= 365) {
      final months = (days / 30).round();
      return '${months}mo ago';
    } else {
      final years = (days / 365).round();
      return '${years}y ago';
    }
  }

  // Helper for KPI widget - returns just the days number
  String get lastContactedDays {
    if (last_contacted_on == null) {
      return '∞';
    }

    final now = DateTime.now();
    final lastContacted = last_contacted_on!;
    final difference = now.difference(lastContacted).inDays;

    return '$difference';
  }

  // ADD copyWith method
  Contact copyWith({
    String? id,
    String? account_id,
    String? first_name,
    String? last_name,
    String? business_name,
    String? addressed_as,
    DateTime? date_of_birth,
    String? business_type,
    List<EmailAddress>? emails,
    List<PhoneNumber>? phone_numbers,
    List<Address>? addresses,
    PersonalDetails? personal_details,
    Map<String, RelationshipDetail>? relationship_details,
    BusinessDetails? business_details,
    String? source,
    List<String>? tags,
    bool? is_deleted,
    DateTime? created_on,
    DateTime? updated_on,
    DateTime? last_contacted_on, // ADDED
    int? last_contacted_days, // ADDED
    bool? isVip, // ADDED: VIP status
    String? device_contact_uuid, // ADDED: iOS device contact UUID
  }) {
    return Contact(
      id: id ?? this.id,
      account_id: account_id ?? this.account_id,
      first_name: first_name ?? this.first_name,
      last_name: last_name ?? this.last_name,
      business_name: business_name ?? this.business_name,
      addressed_as: addressed_as ?? this.addressed_as,
      date_of_birth: date_of_birth ?? this.date_of_birth,
      business_type: business_type ?? this.business_type,
      emails: emails ?? this.emails,
      phone_numbers: phone_numbers ?? this.phone_numbers,
      addresses: addresses ?? this.addresses,
      personal_details: personal_details ?? this.personal_details,
      relationship_details: relationship_details ?? this.relationship_details,
      business_details: business_details ?? this.business_details,
      source: source ?? this.source,
      tags: tags ?? this.tags,
      is_deleted: is_deleted ?? this.is_deleted,
      created_on: created_on ?? this.created_on,
      updated_on: updated_on ?? this.updated_on,
      last_contacted_on: last_contacted_on ?? this.last_contacted_on, // ADDED
      last_contacted_days:
          last_contacted_days ?? this.last_contacted_days, // ADDED
      isVip: isVip ?? this.isVip, // ADDED: VIP status
      device_contact_uuid:
          device_contact_uuid ??
          this.device_contact_uuid, // ADDED: iOS device contact UUID
    );
  }

  factory Contact.fromJson(Map<String, dynamic> json) {
    // Fix UTF-8 encoding issues for all text fields automatically
    final fixedJson =
        TextEncodingUtils.fixUtf8InJson(json) as Map<String, dynamic>;

    return Contact(
      id: fixedJson['id'] as String,
      account_id: fixedJson['account_id'] as String?,
      assigned_user: fixedJson['assigned_user'] as String?,
      created_by: fixedJson['created_by'] as String?,
      created_on:
          fixedJson['created_on'] is Timestamp
              ? (fixedJson['created_on'] as Timestamp).toDate()
              : fixedJson['created_on'] != null
              ? DateTime.parse(fixedJson['created_on'] as String)
              : null,
      first_name: fixedJson['first_name'] as String?,
      last_name: fixedJson['last_name'] as String?,
      addressed_as: fixedJson['addressed_as'] as String?,
      date_of_birth:
          fixedJson['date_of_birth'] is Timestamp
              ? (fixedJson['date_of_birth'] as Timestamp).toDate()
              : fixedJson['date_of_birth'] != null
              ? DateTime.parse(fixedJson['date_of_birth'] as String)
              : null,
      business_name: fixedJson['business_name'] as String?,
      business_type: fixedJson['business_type'] as String?,
      phone_numbers:
          (fixedJson['phone_numbers'] as List<dynamic>?)
              ?.map((e) => PhoneNumber.fromJson(e as Map<String, dynamic>))
              .toList(),
      emails:
          (fixedJson['emails'] as List<dynamic>?)
              ?.map((e) => EmailAddress.fromJson(e as Map<String, dynamic>))
              .toList(),
      addresses:
          (fixedJson['addresses'] as List<dynamic>?)
              ?.map((e) => Address.fromJson(e as Map<String, dynamic>))
              .toList(),
      personal_details:
          fixedJson['personal_details'] != null
              ? PersonalDetails.fromJson(
                fixedJson['personal_details'] as Map<String, dynamic>,
              )
              : null,
      relationship_details:
          (fixedJson['relationship_details'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              key,
              RelationshipDetail.fromJson(value as Map<String, dynamic>),
            ),
          ),
      business_details:
          fixedJson['business_details'] != null
              ? BusinessDetails.fromJson(
                fixedJson['business_details'] as Map<String, dynamic>,
              )
              : null,
      source: fixedJson['source'] as String?,
      tags:
          (fixedJson['tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList(),
      updated_on:
          fixedJson['updated_on'] is Timestamp
              ? (fixedJson['updated_on'] as Timestamp).toDate()
              : fixedJson['updated_on'] != null
              ? DateTime.parse(fixedJson['updated_on'] as String)
              : null,
      updated_by: fixedJson['updated_by'] as String?,
      is_deleted: fixedJson['is_deleted'] as bool? ?? false,
      last_contacted_on:
          fixedJson['last_contacted_on'] is Timestamp
              ? (fixedJson['last_contacted_on'] as Timestamp).toDate()
              : fixedJson['last_contacted_on'] != null
              ? DateTime.parse(fixedJson['last_contacted_on'] as String)
              : null,
      last_contacted_days: fixedJson['last_contacted_days'] as int?,
      isVip:
          fixedJson['is_vip'] as bool? ?? false, // Map from backend snake_case
      device_contact_uuid: fixedJson['device_contact_uuid'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'account_id': account_id,
      'assigned_user': assigned_user,
      'created_by': created_by,
      'created_on': created_on?.toIso8601String(),
      'first_name': first_name,
      'last_name': last_name,
      'addressed_as': addressed_as,
      'date_of_birth': date_of_birth?.toIso8601String(),
      'business_name': business_name,
      'business_type': business_type,
      'phone_numbers': phone_numbers?.map((e) => e.toJson()).toList(),
      'emails': emails?.map((e) => e.toJson()).toList(),
      'addresses':
          (addresses ?? const <Address>[]).map((e) => e.toJson()).toList(),
      'personal_details': personal_details?.toJson(),
      'relationship_details':
          relationship_details != null
              ? relationship_details!.map(
                (key, value) => MapEntry(key, value.toJson()),
              )
              : <String, dynamic>{},
      'business_details': business_details?.toJson(),
      'source': source,
      'tags': tags ?? const <String>[],
      'updated_on': updated_on?.toIso8601String(),
      'updated_by': updated_by,
      'is_deleted': is_deleted,
      'last_contacted_on': last_contacted_on?.toIso8601String(),
      'last_contacted_days': last_contacted_days,
      'is_vip': isVip, // Send as snake_case to backend
      'device_contact_uuid': device_contact_uuid,
    };
  }
}

class EmailAddress {
  final String? label;
  final String? address;

  EmailAddress({this.label, this.address});

  factory EmailAddress.fromJson(Map<String, dynamic> json) {
    return EmailAddress(
      label: json['label'] as String?,
      address: json['address'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {'label': label, 'address': address};
  }
}

class Address {
  final String? label;
  final String? street;
  final String? city;
  final String? state;
  final String? zip;
  final String? country;

  Address({
    this.label,
    this.street,
    this.city,
    this.state,
    this.zip,
    this.country,
  });

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      label: json['label'] as String?,
      street: json['street'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      zip: json['zip'] as String?,
      country: json['country'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'street': street,
      'city': city,
      'state': state,
      'zip': zip,
      'country': country,
    };
  }
}

class PersonalDetails {
  final String? family;
  final String? occupation;
  final String? recreation;
  final String? dreams;
  final String? additional_info; // ADDED from backend

  PersonalDetails({
    this.family,
    this.occupation,
    this.recreation,
    this.dreams,
    this.additional_info,
  });

  factory PersonalDetails.fromJson(Map<String, dynamic> json) {
    final fixedJson =
        TextEncodingUtils.fixUtf8InJson(json) as Map<String, dynamic>;
    return PersonalDetails(
      family: fixedJson['family'] as String?,
      occupation: fixedJson['occupation'] as String?,
      recreation: fixedJson['recreation'] as String?,
      dreams: fixedJson['dreams'] as String?,
      additional_info: fixedJson['additional_info'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'family': family,
      'occupation': occupation,
      'recreation': recreation,
      'dreams': dreams,
      'additional_info': additional_info,
    };
  }
}

// Represents the value object within the relationship_details map
class RelationshipDetail {
  final String? user_id; // ADDED from backend
  final String? details;

  RelationshipDetail({this.user_id, this.details});

  factory RelationshipDetail.fromJson(Map<String, dynamic> json) {
    final fixedJson =
        TextEncodingUtils.fixUtf8InJson(json) as Map<String, dynamic>;
    return RelationshipDetail(
      user_id: fixedJson['user_id'] as String?,
      details: fixedJson['details'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {'user_id': user_id, 'details': details};
  }
}

class BusinessOpportunity {
  final String? opportunity_description;
  final String? latest_development;

  BusinessOpportunity({this.opportunity_description, this.latest_development});

  factory BusinessOpportunity.fromJson(Map<String, dynamic> json) {
    final fixedJson =
        TextEncodingUtils.fixUtf8InJson(json) as Map<String, dynamic>;
    return BusinessOpportunity(
      opportunity_description: fixedJson['opportunity_description'] as String?,
      latest_development: fixedJson['latest_development'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'opportunity_description': opportunity_description,
      'latest_development': latest_development,
    };
  }

  // Add copyWith
  BusinessOpportunity copyWith({
    String? opportunity_description,
    String? latest_development,
  }) {
    return BusinessOpportunity(
      opportunity_description:
          opportunity_description ?? this.opportunity_description,
      latest_development: latest_development ?? this.latest_development,
    );
  }
}

class BusinessDetails {
  final List<BusinessOpportunity>? opportunities;

  BusinessDetails({this.opportunities});

  factory BusinessDetails.fromJson(Map<String, dynamic> json) {
    return BusinessDetails(
      opportunities:
          (json['opportunities'] as List<dynamic>?)
              ?.map(
                (e) => BusinessOpportunity.fromJson(e as Map<String, dynamic>),
              )
              .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'opportunities': opportunities?.map((e) => e.toJson()).toList()};
  }

  // Add copyWith
  BusinessDetails copyWith({List<BusinessOpportunity>? opportunities}) {
    return BusinessDetails(opportunities: opportunities ?? this.opportunities);
  }
}

// Helper for firstOrNull on Lists
extension FirstOrNullExtension<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

class PhoneNumber {
  final String? label;
  final String? number;

  PhoneNumber({this.label, this.number});

  factory PhoneNumber.fromJson(Map<String, dynamic> json) {
    return PhoneNumber(
      label: json['label'] as String?,
      number: json['number'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {'label': label, 'number': number};
  }
}
