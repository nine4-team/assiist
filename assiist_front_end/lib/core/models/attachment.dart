class Attachment {
  final String id;
  final String publicUrl;
  final String filename;
  final String originalFilename;
  final String fileType;
  final int fileSize;
  final DateTime createdOn;

  const Attachment({
    required this.id,
    required this.publicUrl,
    required this.filename,
    required this.originalFilename,
    required this.fileType,
    required this.fileSize,
    required this.createdOn,
  });

  /// Create Attachment from API JSON response
  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['attachment_id'] as String,
      publicUrl: json['public_url'] as String,
      filename: json['filename'] as String,
      originalFilename: json['original_filename'] as String,
      fileType: json['file_type'] as String,
      fileSize: json['file_size'] as int,
      createdOn: DateTime.parse(json['created_on'] as String),
    );
  }

  /// Convert to JSON for API requests
  Map<String, dynamic> toJson() {
    return {
      'attachment_id': id,
      'public_url': publicUrl,
      'filename': filename,
      'original_filename': originalFilename,
      'file_type': fileType,
      'file_size': fileSize,
      'created_on': createdOn.toIso8601String(),
    };
  }

  /// Get human-readable file size
  String get formattedFileSize {
    if (fileSize < 1024) {
      return '$fileSize B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  /// Check if this is an image file
  bool get isImage {
    return fileType.startsWith('image/');
  }

  /// Check if this is a document file
  bool get isDocument {
    return fileType == 'application/pdf' ||
        fileType.contains('document') ||
        fileType.contains('sheet') ||
        fileType.contains('presentation') ||
        fileType == 'text/plain';
  }

  @override
  String toString() {
    return 'Attachment(id: $id, filename: $originalFilename, fileType: $fileType)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Attachment && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
