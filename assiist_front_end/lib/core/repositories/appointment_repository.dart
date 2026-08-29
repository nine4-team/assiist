import 'package:assiist_front_end/core/models/appointment.dart';

/// Abstract interface for appointment data operations.
abstract class AppointmentRepository {
  /// Retrieves all appointments associated with a specific contact ID.
  Future<List<Appointment>> getAppointmentsForContact(String contactId);

  /// Retrieves a specific appointment by its ID.
  Future<Appointment?> getAppointmentById(String appointmentId);

  /// Retrieves all appointments for the current user.
  Future<List<Appointment>> getAllAppointmentsForUser();

  // Add other methods as needed (getForUser, create, update, delete)
}
