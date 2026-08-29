import 'package:assiist_front_end/core/models/user_metrics.dart';

abstract class UserMetricsRepository {
  Future<UserMetrics?> getMetricsForContact(String contactId);
  Future<void> incrementMessagesSent(String contactId);
  Future<void> incrementNotesLogged(String contactId);
  Future<Map<String, int>> getMetricsForUser();
}
