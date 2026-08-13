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

  @override
  ImportState build(String campaignId) => const ImportState();

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

  /// Polls `GET /imports/{jobId}` once a second until the job reaches a
  /// terminal state (`readyToCommit`/`failed`) or [importPollCap] elapses —
  /// whichever comes first. The timer is cancelled on either exit AND via
  /// [ref.onDispose], so a screen navigated away from mid-poll (autoDispose)
  /// never leaves a timer calling `ref.read` on a dead provider.
  void _startPolling(String jobId) {
    final started = DateTime.now();
    _pollTimer?.cancel();
    final timer = Timer.periodic(importPollInterval, (t) async {
      if (DateTime.now().difference(started) > importPollCap) {
        t.cancel();
        return;
      }
      final res = await ref.read(importRepositoryProvider).poll(jobId);
      res.fold((job) {
        state = state.copyWith(job: AsyncData(job));
        if (job.status != ImportStatus.processing) t.cancel();
      }, (_) {});
    });
    _pollTimer = timer;
    ref.onDispose(timer.cancel);
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
