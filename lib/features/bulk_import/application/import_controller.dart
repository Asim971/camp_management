import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/trace/trace_id.dart';
import '../../../domain/common/status.dart';
import '../../../domain/import/import_job.dart';

/// How long the poll loop keeps retrying before giving up on an import that
/// never reaches a terminal state — a stuck server shouldn't poll forever.
const importPollCap = Duration(seconds: 30);
const importPollInterval = Duration(seconds: 1);

class ImportState {
  const ImportState({
    this.job = const AsyncData(null),
    this.committing = false,
  });
  final AsyncValue<ImportJob?> job;
  final bool committing;

  ImportState copyWith({AsyncValue<ImportJob?>? job, bool? committing}) =>
      ImportState(
        job: job ?? this.job,
        committing: committing ?? this.committing,
      );
}

/// Bulk Import (W-07): upload → dry run (async, polled) → review rows →
/// commit valid + needs-profile rows.
class ImportController extends AutoDisposeFamilyNotifier<ImportState, String> {
  Timer? _pollTimer;

  /// `Ref.mounted` isn't part of this riverpod major's public `Ref` API (it
  /// was removed pre-2.x and never restored) — this is the documented
  /// replacement: a flag flipped by [ref.onDispose], checked after every
  /// `await` a still-running async callback could resume from post-dispose.
  bool _disposed = false;

  /// Overridable so a test can drive the poll lifecycle (processing → a
  /// terminal state, or the cap) in milliseconds of real wall-clock time
  /// instead of the production 1s/30s — see
  /// `test/features/bulk_import/application/import_controller_test.dart`.
  Duration get pollInterval => importPollInterval;
  Duration get pollCap => importPollCap;

  @override
  ImportState build(String campaignId) {
    ref.onDispose(() => _disposed = true);
    return const ImportState();
  }

  Future<void> uploadDryRun(List<int> bytes, String filename) async {
    state = state.copyWith(job: const AsyncLoading());
    final res = await ref
        .read(importRepositoryProvider)
        .uploadDryRun(arg, bytes: bytes, filename: filename);
    res.fold((job) {
      state = state.copyWith(job: AsyncData(job));
      if (job.status == ImportStatus.processing) _startPolling(job.id);
    }, (f) => state = state.copyWith(job: AsyncError(f, StackTrace.current)));
  }

  /// Polls `GET /imports/{jobId}` once every [pollInterval] until the job
  /// reaches a terminal state (`readyToCommit`/`failed`) or [pollCap] elapses
  /// — whichever comes first. The timer is cancelled on either exit AND via
  /// [ref.onDispose], so a screen navigated away from mid-poll (autoDispose)
  /// never leaves a timer calling `ref.read` on a dead provider.
  ///
  /// Hitting the cap is itself a terminal outcome (spec §8): a job that never
  /// reaches `readyToCommit`/`failed` within [pollCap] is surfaced as a
  /// visible failure via [_failStuckJob], NOT left showing "Processing…"
  /// forever — a bare `t.cancel()` here would stop polling but leave the last
  /// `processing` state on screen with no way out.
  void _startPolling(String jobId) {
    final started = DateTime.now();
    _pollTimer?.cancel();
    final timer = Timer.periodic(pollInterval, (t) async {
      if (DateTime.now().difference(started) > pollCap) {
        t.cancel();
        _failStuckJob(jobId);
        return;
      }
      final res = await ref.read(importRepositoryProvider).poll(jobId);
      // The timer callback is async, so the provider may have been disposed
      // (screen navigated away) during the `await` above; writing to `state`
      // after that would throw. `_disposed` (set via ref.onDispose in
      // [build]) is the guard for exactly this "did I outlive my own await"
      // case — cancelling the Timer alone doesn't stop an in-flight callback
      // that already started before dispose.
      if (_disposed) return;
      res.fold((job) {
        state = state.copyWith(job: AsyncData(job));
        if (job.status != ImportStatus.processing) t.cancel();
      }, (_) {});
    });
    _pollTimer = timer;
    ref.onDispose(timer.cancel);
  }

  /// Flips the job the UI is already holding to `failed` so the cap renders
  /// the exact same failure surface (`_statusHeadline`/`_canCommit` in
  /// `BulkImportScreen`) a server-reported `FAILED` status would — never a
  /// permanent spinner.
  void _failStuckJob(String jobId) {
    final current =
        state.job.valueOrNull ??
        ImportJob(id: jobId, campaignId: arg, status: ImportStatus.processing);
    state = state.copyWith(
      job: AsyncData(current.copyWith(status: ImportStatus.failed)),
    );
  }

  Future<void> commit() async {
    final job = state.job.valueOrNull;
    if (job == null) return;
    state = state.copyWith(committing: true);
    final res = await ref
        .read(importRepositoryProvider)
        .commit(arg, job.id, trace: TraceId.generate());
    state = state.copyWith(
      committing: false,
      job: res.fold(AsyncData.new, (f) => AsyncError(f, StackTrace.current)),
    );
  }
}

final importControllerProvider = NotifierProvider.autoDispose
    .family<ImportController, ImportState, String>(ImportController.new);
