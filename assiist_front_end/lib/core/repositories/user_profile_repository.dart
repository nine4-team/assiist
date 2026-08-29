import 'package:assiist_front_end/core/models/user_profile.dart';

/// Abstract repository for managing user profile data.
abstract class UserProfileRepository {
  /// Fetches the user profile for the current user.
  /// Returns null if the profile is not found.
  Future<UserProfile?> getUserProfile();

  /// Updates the user's profile.
  /// Returns the updated profile or null if the update fails.
  Future<UserProfile?> updateUserProfile(UserProfile profile);
}
