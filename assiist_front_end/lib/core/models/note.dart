import 'package:cloud_firestore/cloud_firestore.dart';

class ProcessedNote {
  final String body;
  final List<String> keyPoints;

  ProcessedNote({required this.body, required this.keyPoints});

  factory ProcessedNote.fromJson(Map<String, dynamic> json) {
    return ProcessedNote(
      body: json['body'] as String? ?? '',
      keyPoints:
          (json['key_points'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {'body': body, 'key_points': keyPoints};
  }
}

class Note {
  final String? id;
  final String? contact_id;
  final String? createdBy;
  final String rawNote;
  final ProcessedNote? processedNote;
  final DateTime createdOn;
  final DateTime? updatedOn;
  final String? updatedBy;

  Note({
    this.id,
    this.contact_id,
    this.createdBy,
    required this.rawNote,
    this.processedNote,
    required this.createdOn,
    this.updatedOn,
    this.updatedBy,
  });

  // <<< Add back timestamp helpers >>>
  static DateTime? _timestampToDateTime(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    } else if (timestamp is String) {
      return DateTime.tryParse(timestamp)?.toLocal();
    }
    return null;
  }

  static DateTime _timestampToDateTimeRequired(dynamic timestamp) {
    DateTime? dt = _timestampToDateTime(timestamp);
    if (dt == null) {
      print(
        "Warning: Could not parse required DateTime from backend: $timestamp. Using current time.",
      );
      return DateTime.now();
    }
    return dt;
  }
  // <<< End timestamp helpers >>>

  // Factory constructor for creating a new Note instance from a map
  factory Note.fromJson(Map<String, dynamic> json, String? docId) {
    // Handle potential Timestamp from Firestore or ISO String from API
    dynamic timestampData = json['created_on'];
    DateTime createdOn;
    if (timestampData is Timestamp) {
      createdOn = timestampData.toDate();
    } else if (timestampData is String) {
      createdOn = DateTime.parse(timestampData);
    } else {
      // Default or throw error if format is unexpected
      createdOn = DateTime.now(); // Fallback, consider logging/throwing
    }

    // Extract fields from JSON
    String rawNote = json['raw_note'] as String? ?? '';
    ProcessedNote? processedNote;

    // Handle processed_note structure
    if (json['processed_note'] != null && json['processed_note'] is Map) {
      processedNote = ProcessedNote.fromJson(
        json['processed_note'] as Map<String, dynamic>,
      );
    }

    return Note(
      id: docId,
      contact_id: json['contact_id'] as String?,
      createdBy: json['created_by'] as String?,
      rawNote: rawNote,
      processedNote: processedNote,
      createdOn: createdOn,
      updatedOn: _timestampToDateTime(json['updated_on']),
      updatedBy: json['updated_by'] as String?,
    );
  }

  // Method for converting a Note instance to a map
  Map<String, dynamic> toJson() {
    return {
      'contact_id': contact_id,
      'created_by': createdBy,
      'raw_note': rawNote,
      'processed_note': processedNote?.toJson(),
      'updated_by': updatedBy,
    }..removeWhere((key, value) => value == null);
  }

  // CopyWith method for immutability
  Note copyWith({
    String? id,
    String? contact_id,
    String? createdBy,
    String? rawNote,
    ProcessedNote? processedNote,
    DateTime? createdOn,
    DateTime? updatedOn,
    String? updatedBy,
    bool setProcessedNoteNull = false,
    bool setCreatedByNull = false,
    bool setUpdatedOnNull = false,
    bool setUpdatedByNull = false,
    bool setContactIdNull = false,
  }) {
    return Note(
      id: id ?? this.id,
      contact_id: setContactIdNull ? null : (contact_id ?? this.contact_id),
      createdBy: setCreatedByNull ? null : (createdBy ?? this.createdBy),
      rawNote: rawNote ?? this.rawNote,
      processedNote:
          setProcessedNoteNull ? null : (processedNote ?? this.processedNote),
      createdOn: createdOn ?? this.createdOn,
      updatedOn: setUpdatedOnNull ? null : (updatedOn ?? this.updatedOn),
      updatedBy: setUpdatedByNull ? null : (updatedBy ?? this.updatedBy),
    );
  }

  // Optional: Override toString for easier debugging
  @override
  String toString() {
    return 'Note(id: ${id ?? 'null'}, contact_id: $contact_id, createdBy: $createdBy, rawNote: $rawNote, processedNote: $processedNote, createdOn: $createdOn, updatedOn: $updatedOn, updatedBy: $updatedBy)';
  }
}
