import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/di/providers.dart';
import '../../../core/media/face_quality.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/sync/sync_engine.dart';

/// Identifies which registered carpenter, in which session, is being captured.
class CaptureArgs {
  const CaptureArgs({required this.sessionId, required this.carpenterId});
  final String sessionId;
  final String carpenterId;

  @override
  bool operator ==(Object other) =>
      other is CaptureArgs &&
      other.sessionId == sessionId &&
      other.carpenterId == carpenterId;

  @override
  int get hashCode => Object.hash(sessionId, carpenterId);
}

/// The five capture steps (§8.10): purpose notice → face positioning → live
/// camera → quality result → submit, then a terminal captured state.
enum CaptureStep {
  purposeNotice,
  positioning,
  liveCamera,
  qualityResult,
  captured
}

class CaptureState {
  const CaptureState({
    this.step = CaptureStep.purposeNotice,
    this.noticeLanguage,
    this.quality,
    this.submitting = false,
    this.error,
    this.attendanceId,
  });

  final CaptureStep step;
  final String? noticeLanguage; // recorded with the consent notice version
  final FaceQuality? quality;
  final bool submitting;
  final String? error;
  final String? attendanceId; // set once queued (capture success)

  CaptureState copyWith({
    CaptureStep? step,
    String? noticeLanguage,
    FaceQuality? quality,
    bool? submitting,
    String? error,
    String? attendanceId,
  }) =>
      CaptureState(
        step: step ?? this.step,
        noticeLanguage: noticeLanguage ?? this.noticeLanguage,
        quality: quality ?? this.quality,
        submitting: submitting ?? this.submitting,
        error: error,
        attendanceId: attendanceId ?? this.attendanceId,
      );
}

/// Drives the capture flow and the submit pipeline. Submit is the valuable,
/// testable part: encrypt → persist evidence → write draft → enqueue. It hands
/// off to the [SyncEngine]; from the user's view, a queued item IS a successful
/// capture (capture ≠ upload — §8.11).
class CaptureController
    extends AutoDisposeFamilyNotifier<CaptureState, CaptureArgs> {
  static const _uuid = Uuid();

  // Transient captured bytes — deliberately kept out of persisted state; they
  // exist only between capture and submit.
  List<int>? _pendingBytes;

  @override
  CaptureState build(CaptureArgs arg) => const CaptureState();

  void acceptNotice(String language) {
    state =
        state.copyWith(step: CaptureStep.positioning, noticeLanguage: language);
    // TODO(T-0.5.2): persist consent notice version + language + timestamp.
  }

  void beginCamera() => state = state.copyWith(step: CaptureStep.liveCamera);

  /// Called by the camera step with the freshly captured JPEG bytes.
  Future<void> onCaptured(List<int> bytes) async {
    final checker = ref.read(faceQualityCheckerProvider);
    final quality = await checker.check(bytes);
    _pendingBytes = bytes;
    state = state.copyWith(step: CaptureStep.qualityResult, quality: quality);
  }

  void recapture() {
    _pendingBytes = null;
    state = state.copyWith(step: CaptureStep.liveCamera, quality: null);
  }

  Future<void> submit() async {
    final bytes = _pendingBytes;
    final quality = state.quality;
    if (bytes == null || quality == null || !quality.passes) return;

    state = state.copyWith(submitting: true, error: null);
    try {
      final id = _uuid.v4(); // attendance id == sync idempotency key
      final capturedBy = ref.read(authControllerProvider)?.userId ?? 'unknown';
      final capturedAt = DateTime.now();

      // 1) encrypt at rest, 2) persist to private evidence dir.
      final cipher = await ref.read(mediaEncryptorProvider).encrypt(bytes);
      final path =
          await ref.read(evidenceStoreProvider).write('$id.enc', cipher);

      final qualityJson = jsonEncode({
        'faceCount': quality.faceCount,
        'isSharp': quality.isSharp,
        'isWellLit': quality.isWellLit,
        'isUpright': quality.isUpright,
      });

      // 3) durable draft (survives restart).
      final db = ref.read(appDatabaseProvider);
      await db.into(db.attendanceDrafts).insert(
            AttendanceDraftsCompanion.insert(
              id: id,
              sessionId: arg.sessionId,
              carpenterId: arg.carpenterId,
              encryptedMediaPath: path,
              capturedAt: capturedAt,
              capturedBy: capturedBy,
              qualityJson: Value(qualityJson),
            ),
          );

      // 4) enqueue for sync (idempotent).
      await ref.read(syncEngineProvider).enqueue(
            SyncTaskSpec(
              idempotencyKey: id,
              type: 'attendance',
              payload: {
                'encryptedMediaPath': path,
                'sessionId': arg.sessionId,
                'carpenterId': arg.carpenterId,
                'capturedAt': capturedAt.toIso8601String(),
                'capturedBy': capturedBy,
              },
            ),
          );
      // TODO(T-0.3.6): emit AuditAction.attendanceCaptured.

      _pendingBytes = null;
      state = state.copyWith(
        step: CaptureStep.captured,
        submitting: false,
        attendanceId: id,
      );
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
    }
  }
}

final captureControllerProvider = NotifierProvider.autoDispose
    .family<CaptureController, CaptureState, CaptureArgs>(
  CaptureController.new,
);
