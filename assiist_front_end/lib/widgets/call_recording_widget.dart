import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:assiist_front_end/services/attachment_service.dart';
import 'package:assiist_front_end/providers/service_providers.dart';
import 'package:assiist_front_end/core/models/attachment.dart';
import 'package:assiist_front_end/providers/auth_providers.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:assiist_front_end/theme/app_styles.dart';
import 'package:assiist_front_end/providers/transcription_providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assiist_front_end/providers/repository_providers.dart';

/// Callback signature when transcription completes.
typedef TranscriptionCallback =
    void Function(String transcriptionText, String audioUrl);

class CallRecordingWidget extends ConsumerStatefulWidget {
  final String? contactId; // Required to submit transcription request
  final TranscriptionCallback? onTranscriptionComplete;

  const CallRecordingWidget({
    Key? key,
    this.contactId,
    this.onTranscriptionComplete,
  }) : super(key: key);

  @override
  ConsumerState<CallRecordingWidget> createState() =>
      _CallRecordingWidgetState();
}

/// Simple state machine for UI
enum _UploadState { idle, picking, uploading, transcribing, done, error }

class _CallRecordingWidgetState extends ConsumerState<CallRecordingWidget> {
  _UploadState _state = _UploadState.idle;
  String? _errorMessage;
  Attachment? _audioAttachment;
  String? _transcriptionText;
  String? _transcriptionRequestId;
  bool _isExpanded = false; // Add collapsible state

  @override
  Widget build(BuildContext context) {
    // Watch Firestore doc if we have a request ID
    if (_transcriptionRequestId != null) {
      final docAsync = ref.watch(
        transcriptionDocProvider(_transcriptionRequestId!),
      );

      docAsync.whenData((doc) {
        assert(() {
          debugPrint(
            '[CallRecording] Snapshot: exists=${doc?.exists} data=${doc?.data()}',
          );
          return true;
        }());

        final data = doc?.data();
        if (data == null) return;

        final status = data['status'];

        String? newText;

        if (status == 'enhanced' && data['summary'] != null) {
          final summary = (data['summary'] as String?) ?? '';
          newText = summary.isNotEmpty ? 'Summary:\n$summary' : null;
        } else if (status == 'completed' &&
            data['transcription_text'] != null) {
          newText = data['transcription_text'] as String?;
        }

        if (newText != null && newText != _transcriptionText) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _transcriptionText = newText);
            widget.onTranscriptionComplete?.call(
              newText!,
              _audioAttachment?.publicUrl ?? '',
            );
          });
        }
      });
    }

    return _buildCard(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Enhanced Collapsible Header
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6.0),
                        decoration: BoxDecoration(
                          color: CupertinoColors.black.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: AppStyles.accentIcon(
                          icon: CupertinoIcons.mic,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Call Recording',
                            style: AppStyles.h3StandardTextStyle(context),
                          ),
                          Text(
                            'Upload call recording',
                            style: AppStyles.captionTextStyle(context).copyWith(
                              color: CupertinoColors.secondaryLabel.resolveFrom(
                                context,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(4.0),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGrey5.resolveFrom(context),
                      borderRadius: BorderRadius.circular(6.0),
                    ),
                    child: Icon(
                      _isExpanded
                          ? CupertinoIcons.chevron_up
                          : CupertinoIcons.chevron_down,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Animated Collapsible Content
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: Visibility(
              visible: _isExpanded,
              child: Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: _buildContent(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_state) {
      case _UploadState.idle:
        return _buildUploadButton(
          label: 'Upload Recording',
          icon: CupertinoIcons.mic_fill,
          onPressed: _pickAudioFile,
        );
      case _UploadState.picking:
      case _UploadState.uploading:
        return const Center(child: CupertinoActivityIndicator());
      case _UploadState.transcribing:
        return Column(
          children: const [
            CupertinoActivityIndicator(),
            SizedBox(height: 8),
            Text('Transcribing…'),
          ],
        );
      case _UploadState.done:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Audio uploaded and transcription requested.'),
            if (_transcriptionText != null) Text(_transcriptionText!),
          ],
        );
      case _UploadState.error:
        return Column(
          children: [
            Text(
              _errorMessage ?? 'Unknown error',
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 12),
            _buildUploadButton(
              label: 'Retry',
              icon: CupertinoIcons.arrow_clockwise,
              onPressed: () => setState(() => _state = _UploadState.idle),
            ),
          ],
        );
    }
  }

  // Enhanced upload button matching attachment section style
  Widget _buildUploadButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    Color? backgroundColor,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
            color: CupertinoColors.systemGrey2.resolveFrom(context),
            width: AppStyles.dividerThickness,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppStyles.accentIcon(icon: icon, size: 22),
            const SizedBox(width: 12),
            AppStyles.accentText(
              context,
              label,
              style: AppStyles.buttonTextStyle(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required BuildContext context, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppStyles.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: child,
    );
  }

  Future<void> _pickAudioFile() async {
    setState(() => _state = _UploadState.picking);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m4a', 'mp3', 'wav', 'aac', 'mp4'],
    );
    if (result == null || result.files.isEmpty) {
      setState(() => _state = _UploadState.idle);
      return;
    }

    final filePath = result.files.single.path;
    if (filePath == null) {
      setState(() {
        _state = _UploadState.error;
        _errorMessage = 'Failed to read selected file.';
      });
      return;
    }

    await _uploadAudio(File(filePath));
  }

  Future<void> _uploadAudio(File file) async {
    setState(() => _state = _UploadState.uploading);
    try {
      final attachmentService = ref.read(attachmentServiceProvider);
      final attachment = await attachmentService.uploadFile(file);
      _audioAttachment = attachment;
      await _requestTranscription();
    } catch (e) {
      setState(() {
        _state = _UploadState.error;
        _errorMessage = 'Upload failed: $e';
      });
    }
  }

  Future<void> _requestTranscription() async {
    if (widget.contactId == null || _audioAttachment == null) {
      setState(() {
        _state = _UploadState.error;
        _errorMessage = 'Contact not selected or attachment missing.';
      });
      return;
    }

    setState(() => _state = _UploadState.transcribing);
    try {
      final apiBase = ref.read(baseUrlProvider);
      final authService = ref.read(authServiceProvider);
      final freshToken = await authService.getFreshAuthToken();
      final url = Uri.parse('$apiBase/transcription/transcribe-audio');
      final headers = {
        'Content-Type': 'application/json',
        if (freshToken != null) 'Authorization': 'Bearer $freshToken',
      };
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'contact_id': widget.contactId,
          'attachment_id': _audioAttachment!.id,
        }),
      );

      if (response.statusCode >= 300) {
        throw Exception('API error: ${response.statusCode} ${response.body}');
      }

      final data = jsonDecode(response.body);
      if (data is Map && data['id'] != null) {
        _transcriptionRequestId = data['id'] as String;

        setState(() {
          _state = _UploadState.done;
          _transcriptionText = null; // clear placeholder text
        });
      } else {
        throw Exception('Unexpected response format');
      }
    } catch (e) {
      setState(() {
        _state = _UploadState.error;
        _errorMessage = 'Transcription request failed: $e';
      });
    }
  }
}
