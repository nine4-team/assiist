import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String id; // Backend user ID
  final String firebaseUid; // Firebase UID for reference
  final String? email;
  final String? firstName;
  final String? lastName;
  final String? displayName;
  final Timestamp? createdOn;
  final String? accountId;
  // Add other fields as needed

  UserProfile({
    required this.id,
    required this.firebaseUid,
    this.email,
    this.firstName,
    this.lastName,
    this.displayName,
    this.createdOn,
    this.accountId,
  });

  // Factory constructor to create a UserProfile from a Firestore snapshot
  factory UserProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('Missing data for UserProfile ${snapshot.id}');
    }
    return UserProfile(
      id: snapshot.id, // Document ID (backend user ID)
      firebaseUid: snapshot.id, // Same as document ID in Firestore context
      email: data['email'] as String?,
      firstName: data['first_name'] as String?,
      lastName: data['last_name'] as String?,
      displayName: null,
      createdOn: data['created_on'] as Timestamp?,
      accountId: data['account_id'] as String?,
    );
  }

  // Method to convert UserProfile to a Map for Firestore
  Map<String, dynamic> toFirestore() {
    return {
      if (email != null) 'email': email,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (accountId != null) 'account_id': accountId,
      'created_on': createdOn ?? FieldValue.serverTimestamp(),
      // Only include non-null fields
    };
  }

  // Optional: Getter for a display name derived from first/last
  String get derivedDisplayName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    } else if (firstName != null) {
      return firstName!;
    } else if (lastName != null) {
      return lastName!;
    } else if (displayName != null) {
      return displayName!;
    } else if (email != null) {
      return email!; // Fallback to email
    }
    return 'User'; // Fallback
  }
}
