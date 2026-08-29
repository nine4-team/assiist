// lib/services/native_calendar_service.dart
import 'package:flutter/foundation.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Simple model matching backend expectation for native events
// Adapt this if your backend expects a different structure
class NativeCalendarEvent {
  final String? localId; // ID from the device calendar plugin
  final String? calendarId; // ID of the source calendar on device
  final String? title;
  final DateTime? start;
  final DateTime? end;
  final bool? allDay;

  NativeCalendarEvent({
    this.localId,
    this.calendarId,
    this.title,
    this.start,
    this.end,
    this.allDay,
  });

  Map<String, dynamic> toJson() => {
    'localId': localId,
    'calendarId': calendarId,
    'title': title,
    'start': start?.toIso8601String(),
    'end': end?.toIso8601String(),
    'allDay': allDay,
  };
}

class NativeCalendarService {
  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();
  final _firebaseAuth = fb_auth.FirebaseAuth.instance;

  // Backend base URL loaded from environment
  final String _backendBaseUrl =
      (() {
        final String? apiUrl = dotenv.env['API_URL'];
        if (apiUrl == null || apiUrl.isEmpty) {
          throw Exception(
            "API_URL not found in environment. Please ensure it is set in your .env file.",
          );
        }
        return apiUrl;
      })();
  // *** Ensure this endpoint exists on your Python backend ***
  late final String _backendSyncNativeEndpoint =
      "$_backendBaseUrl/calendar/sync-native";

  Future<bool> requestPermissions() async {
    var status =
        await Permission.calendarFullAccess
            .request(); // Or .calendarWrite for only read

    if (status.isGranted) {
      return true;
    } else {
      // Handle permission denial (e.g., show dialog, disable feature)
      print("Calendar permission denied.");
      // You might want to open app settings using permission_handler's openAppSettings()
      return false;
    }
  }

  Future<bool> hasPermissions() async {
    var status =
        await Permission.calendarFullAccess.status; // Or .calendarWrite
    return status.isGranted;
  }

  Future<List<NativeCalendarEvent>> fetchNativeEvents({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (!await hasPermissions()) {
      print("Cannot fetch native events: Permissions not granted.");
      return [];
    }

    try {
      final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
      if (calendarsResult.isSuccess && calendarsResult.data != null) {
        List<NativeCalendarEvent> allEvents = [];
        final fetchStart = startDate ?? DateTime.now();
        final fetchEnd =
            endDate ??
            DateTime.now().add(const Duration(days: 30)); // Fetch next 30 days

        for (var calendar in calendarsResult.data!) {
          // Skip read-only calendars if you don't need them? Or filter specific ones?
          if (calendar.id == null) continue;

          final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
            calendar.id,
            RetrieveEventsParams(startDate: fetchStart, endDate: fetchEnd),
          );

          if (eventsResult.isSuccess && eventsResult.data != null) {
            allEvents.addAll(
              eventsResult.data!.map(
                (e) => NativeCalendarEvent(
                  localId: e.eventId,
                  calendarId: e.calendarId,
                  title: e.title,
                  start: e.start,
                  end: e.end,
                  allDay: e.allDay,
                ),
              ),
            );
          } else {
            print(
              "Failed to retrieve events for calendar ${calendar.name}: ${eventsResult.errors}",
            );
          }
        }
        print("Fetched ${allEvents.length} native events.");
        return allEvents;
      } else {
        print("Failed to retrieve calendars: ${calendarsResult.errors}");
        return [];
      }
    } catch (e) {
      print("Error fetching native calendar events: $e");
      return [];
    }
  }

  /// Fetches native events and sends them to the backend.
  Future<bool> syncNativeEventsToBackend({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return false; // Need logged in user
    String? firebaseIdToken = await user.getIdToken();
    if (firebaseIdToken == null)
      return false; // Need token to auth backend call

    List<NativeCalendarEvent> nativeEvents = await fetchNativeEvents(
      startDate: startDate,
      endDate: endDate,
    );
    if (nativeEvents.isEmpty) {
      print("No native events fetched to sync.");
      // Consider if this is a success or failure case - returning true as nothing failed.
      return true;
    }

    print("Syncing ${nativeEvents.length} native events to backend...");
    try {
      final response = await http.post(
        Uri.parse(_backendSyncNativeEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Bearer $firebaseIdToken', // Authenticate this request
        },
        // Send the list of events as JSON
        body: json.encode({
          'events': nativeEvents.map((e) => e.toJson()).toList(),
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        print("Backend successfully synced native events.");
        return true;
      } else {
        print(
          "Backend native event sync failed: ${response.statusCode} ${response.body}",
        );
        return false;
      }
    } catch (e) {
      print("Exception syncing native events to backend: $e");
      return false;
    }
  }

  // New method to get iCal URLs from native calendars
  Future<List<Map<String, String>>> getNativeCalendarICalUrls() async {
    if (!await hasPermissions()) {
      print("Cannot fetch native calendars: Permissions not granted.");
      return [];
    }

    try {
      final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
      if (calendarsResult.isSuccess && calendarsResult.data != null) {
        List<Map<String, String>> calendarUrls = [];

        for (var calendar in calendarsResult.data!) {
          if (calendar.id == null) continue;

          // For Apple Calendar, we can construct the iCal URL using the calendar ID
          // The calendar ID is typically in the format: YYYYYYYY-YYYY-YYYY-YYYY-YYYYYYYYYYYY
          if (calendar.id!.contains('-')) {
            calendarUrls.add({
              'name': calendar.name ?? 'Unknown Calendar',
              'url':
                  'https://pXX-caldav.icloud.com/XXXXXXXX/calendars/${calendar.id}/public/basic.ics',
              'id': calendar.id!,
            });
          }
        }

        return calendarUrls;
      }
    } catch (e) {
      print("Error fetching native calendar iCal URLs: $e");
    }

    return [];
  }
}
