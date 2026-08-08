import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/di/providers.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/consent/notice.dart';
import '../../../core/media/face_quality.dart';
import '../../../core/result/result.dart';
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
  captured,
}

class CaptureState {
  const CaptureState({
    this.step = CaptureStep.purposeNotice,
    this.notice,
    this.consent,
    this.noticeBlocked = false,
    this.quality,
    this.submitting = false,
    this.error,
    this.attendanceId,
  });

  final CaptureStep step;

  /// The notice resolved for the notice step — the exact text on screen. There
  /// is deliberately no separate `noticeLanguage`: it is [ConsentNotice.language]
  /// and keeping both invites them to disagree.
  final ConsentNotice? notice;

  /// What was accepted, built from [notice] itself. Written to the draft by
  /// [CaptureController.submit].
  final ConsentRecord? consent;

  /// No notice could be resolved, so capture is blocked (spec D7): you cannot
  /// photograph someone without showing them a notice.
  final bool noticeBlocked;

  final FaceQuality? quality;
  final bool submitting;
  final String? error;
  final String? attendanceId; // set once queued (capture success)

  /// Changes a subset of fields, keeping the rest.
  ///
  /// [notice] and [consent] are deliberately NOT parameters. Every field here
  /// except `error` uses the `?? this.x` idiom, under which `copyWith(x: null)`
  /// silently keeps the previous value instead of clearing it — and a kept-but-
  /// stale notice is a legal defect, not a cosmetic one: `acceptNotice()` would
  /// record consent for text the user was no longer looking at. The three
  /// transitions that change either field construct a [CaptureState] explicitly
  /// instead, so the idiom cannot be applied to them by accident. Omitting them
  /// here turns the mistake into a compile error rather than a comment.
  CaptureState copyWith({
    CaptureStep? step,
    bool? noticeBlocked,
    FaceQuality? quality,
    bool? submitting,
    String? error,
    String? attendanceId,
  }) => CaptureState(
    step: step ?? this.step,
    // These two read the FIELDS: copyWith has no parameter of either name, on
    // purpose (see above), so they always carry through unchanged.
    notice: notice,
    consent: consent,
    noticeBlocked: noticeBlocked ?? this.noticeBlocked,
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

  /// Resolves the notice to show. Called when the notice step is entered and
  /// again whenever the language is switched.
  Future<void> loadNotice(String language) async {
    final result = await ref.read(noticeRepositoryProvider).resolve(language);

    if (result case Ok(:final value)) {
      // Explicit construction, not copyWith: see [CaptureState.copyWith].
      state = CaptureState(
        step: state.step,
        notice: value,
        consent: state.consent,
      );
      return;
    }

    // Spec D7: consent fails CLOSED. Without a notice there is nothing to show,
    // and photographing someone without showing them one is a legal defect — so
    // capture stops here rather than proceeding blank.
    //
    // Explicit construction, and it MUST stay that way: `copyWith` cannot clear
    // `notice`, so a copyWith here would leave the previously resolved notice in
    // state while the screen showed a block, and `acceptNotice()` would record
    // consent for wording the user was not looking at.
    state = CaptureState(step: state.step, noticeBlocked: true);
  }

  /// Switches the notice's language. Independent of the app locale: the
  /// carpenter must understand the notice, and the field user's UI preference is
  /// irrelevant to that (T-2.3.3). The app locale is only the default.
  Future<void> selectNoticeLanguage(String language) => loadNotice(language);

  /// Records consent for the notice currently displayed, then advances.
  ///
  /// Takes no language argument on purpose: the old signature let a caller
  /// record a language that did not match the text on screen.
  Future<void> acceptNotice() async {
    final shown = state.notice;
    // Both halves matter. `noticeBlocked` is checked as well as the notice
    // itself so that acceptance can never step over a fail-closed block.
    if (shown == null || state.noticeBlocked) return;

    // `await shown.hash()` is computed inline, on the very object being
    // recorded, and is never hoisted or cached: any gap between "text shown"
    // and "hash recorded" is a record that proves the wrong wording.
    final record = ConsentRecord.of(
      shown,
      DateTime.now().toUtc(),
      await shown.hash(),
    );

    // Hashing is asynchronous, so a language switch could have landed while it
    // was in flight. If the displayed notice moved on — or a failed switch
    // blocked the flow — this acceptance is stale and must not advance.
    if (!identical(state.notice, shown) || state.noticeBlocked) return;

    state = CaptureState(
      step: CaptureStep.positioning,
      notice: shown,
      consent: record,
    );
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
    // Explicit construction because `quality` genuinely has to be cleared, and
    // `copyWith(quality: null)` — what this line used to be — cannot clear it.
    // The consent already recorded is carried forward on purpose: the notice was
    // shown and accepted once, and submit() refuses without it.
    state = CaptureState(
      step: CaptureStep.liveCamera,
      notice: state.notice,
      consent: state.consent,
    );
  }

  Future<void> submit() async {
    final bytes = _pendingBytes;
    final quality = state.quality;
    if (bytes == null || quality == null || !quality.passes) return;

    final consent = state.consent;
    if (consent == null) {
      // A capture with no consent record must never reach the queue. Reaching
      // here means the flow was driven out of order, so say so: a bare `return`
      // would leave the user tapping Submit against a screen that never moves.
      state = state.copyWith(
        error:
            'Consent was not recorded. Start this capture again to show '
            'the notice.',
      );
      return;
    }

    state = state.copyWith(submitting: true, error: null);
    try {
      final id = _uuid.v4(); // attendance id == sync idempotency key
      final capturedBy = switch (ref.read(authStateProvider)) {
        AuthSignedIn(:final session) => session.userId,
        _ => 'unknown',
      };
      final capturedAt = DateTime.now();

      // 1) encrypt at rest, 2) persist to private evidence dir.
      final cipher = await ref.read(mediaEncryptorProvider).encrypt(bytes);
      final path = await ref
          .read(evidenceStoreProvider)
          .write('$id.enc', cipher);

      final qualityJson = jsonEncode({
        'faceCount': quality.faceCount,
        'isSharp': quality.isSharp,
        'isWellLit': quality.isWellLit,
        'isUpright': quality.isUpright,
      });

      // 3) durable draft (survives restart).
      final db = ref.read(appDatabaseProvider);
      await db
          .into(db.attendanceDrafts)
          .insert(
            AttendanceDraftsCompanion.insert(
              id: id,
              sessionId: arg.sessionId,
              carpenterId: arg.carpenterId,
              encryptedMediaPath: path,
              capturedAt: capturedAt,
              capturedBy: capturedBy,
              qualityJson: Value(qualityJson),
              // What was shown, recorded beside the photo it belongs to. The
              // hash is what makes the record prove the wording rather than
              // point at a version.
              consentVersion: Value(consent.version),
              consentLanguage: Value(consent.language),
              consentShownAt: Value(consent.shownAt),
              consentContentHash: Value(consent.contentHash),
            ),
          );

      // 4) enqueue for sync (idempotent).
      await ref
          .read(syncEngineProvider)
          .enqueue(
            SyncTaskSpec(
              idempotencyKey: id,
              type: 'attendance',
              payload: {
                'encryptedMediaPath': path,
                'sessionId': arg.sessionId,
                'carpenterId': arg.carpenterId,
                'capturedAt': capturedAt.toIso8601String(),
                'capturedBy': capturedBy,
                // The draft columns alone would leave the record on the device:
                // DioSyncUploader confirms an attendance with `spec.payload`, so
                // the consent has to ride with it to reach the server.
                'consentVersion': consent.version,
                'consentLanguage': consent.language,
                'consentShownAt': consent.shownAt.toIso8601String(),
                'consentContentHash': consent.contentHash,
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
