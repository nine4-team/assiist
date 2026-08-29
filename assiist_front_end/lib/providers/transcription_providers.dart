import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Streams the audio_transcriptions document corresponding to [requestId].
final transcriptionDocProvider =
    StreamProvider.family<DocumentSnapshot<Map<String, dynamic>>?, String>((
      ref,
      requestId,
    ) {
      final firestore = FirebaseFirestore.instanceFor(
        app: Firebase.app(), // ensure same app
        databaseId: 'assiist-app',
      );
      return firestore
          .collection('audio_transcriptions')
          .doc(requestId)
          .snapshots();
    });
