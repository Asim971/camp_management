import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/core/trace/trace_id.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/domain/import/import_job.dart';
import 'package:acsl_campaign/domain/import/import_repository.dart';
import 'package:acsl_campaign/features/bulk_import/application/import_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fix-round follow-up (spec §8 gap): the previous widget tests only injected
/// a TERMINAL job straight into a controller's `build()`, so nothing ever
/// exercised the poll loop actually running — neither the processing ->
/// terminal transition, nor the 30s cap. Both are pinned here by driving the
/// REAL [ImportController]/[ImportController._startPolling] against a
/// scripted fake repository, with [pollInterval]/[pollCap] shrunk to
/// milliseconds so the test runs in real wall-clock time without needing
/// `fake_async`.
class _ScriptedImportRepository implements ImportRepository {
  _ScriptedImportRepository(this._pollScript);

  /// Consumed in order as `poll` is called; once exhausted, the last entry
  /// repeats (so a "stuck" script is just a one-element list).
  final List<ImportJob> _pollScript;
  int pollCalls = 0;

  @override
  Future<Result<ImportJob>> uploadDryRun(
    String campaignId, {
    required List<int> bytes,
    required String filename,
  }) async => Ok(
    ImportJob(
      id: 'IMPORT-1',
      campaignId: campaignId,
      status: ImportStatus.processing,
    ),
  );

  @override
  Future<Result<ImportJob>> poll(String jobId) async {
    pollCalls++;
    final job = pollCalls <= _pollScript.length
        ? _pollScript[pollCalls - 1]
        : _pollScript.last;
    return Ok(job);
  }

  @override
  Future<Result<ImportJob>> commit(
    String campaignId,
    String jobId, {
    TraceId? trace,
  }) => throw UnimplementedError('not exercised by this test');
}

ImportJob _job(ImportStatus status) =>
    ImportJob(id: 'IMPORT-1', campaignId: 'camp-1', status: status);

/// Shrinks the production 1s/30s poll timing to milliseconds so these tests
/// finish fast and deterministically on real timers — no fake clock needed.
class _FastPollController extends ImportController {
  @override
  Duration get pollInterval => const Duration(milliseconds: 5);

  @override
  Duration get pollCap => const Duration(milliseconds: 30);
}

void main() {
  test('the poll loop transitions processing -> readyToCommit and then stops '
      'polling (the timer cancels on the terminal state)', () async {
    final repo = _ScriptedImportRepository([
      _job(ImportStatus.processing),
      _job(ImportStatus.processing),
      _job(ImportStatus.readyToCommit),
    ]);
    final container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(repo),
        importControllerProvider.overrideWith(_FastPollController.new),
      ],
    );
    addTearDown(container.dispose);
    // `container.read` alone does not keep an autoDispose provider alive —
    // Riverpod disposes it as soon as nothing is *listening*. `listen` is
    // the real subscription these tests need to hold across the awaited
    // gaps below (mirrors how a widget's `ref.watch` keeps the same
    // provider alive in the widget tests).
    container.listen(importControllerProvider('camp-1'), (_, _) {});

    final notifier = container.read(
      importControllerProvider('camp-1').notifier,
    );
    await notifier.uploadDryRun([1, 2, 3], 'sample.csv');

    // 3 scripted poll ticks at a 5ms interval, plus generous scheduling
    // slack: well past the readyToCommit tick, nowhere near the 30ms cap.
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final state = container.read(importControllerProvider('camp-1'));
    expect(state.job.value?.status, ImportStatus.readyToCommit);

    final callsAtTerminal = repo.pollCalls;
    expect(
      callsAtTerminal,
      greaterThanOrEqualTo(3),
      reason: 'the script only reaches readyToCommit on its 3rd poll',
    );

    // If the timer failed to cancel on the terminal state, polling would
    // keep incrementing pollCalls past the terminal script entry (the
    // scripted repository just keeps re-returning readyToCommit).
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(
      repo.pollCalls,
      callsAtTerminal,
      reason:
          'polling must stop once a terminal state is reached, not keep '
          'ticking forever',
    );
  });

  test('a job stuck in "processing" past the poll cap surfaces as a visible '
      'failure, not a permanent spinner (spec §8)', () async {
    // Always answers "processing" — the job never reaches a terminal
    // state on its own, so only the cap can end the loop.
    final repo = _ScriptedImportRepository([_job(ImportStatus.processing)]);
    final container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(repo),
        importControllerProvider.overrideWith(_FastPollController.new),
      ],
    );
    addTearDown(container.dispose);
    // `container.read` alone does not keep an autoDispose provider alive —
    // Riverpod disposes it as soon as nothing is *listening*. `listen` is
    // the real subscription these tests need to hold across the awaited
    // gaps below (mirrors how a widget's `ref.watch` keeps the same
    // provider alive in the widget tests).
    container.listen(importControllerProvider('camp-1'), (_, _) {});

    final notifier = container.read(
      importControllerProvider('camp-1').notifier,
    );
    await notifier.uploadDryRun([1, 2, 3], 'sample.csv');

    // Past the 30ms cap, with slack for scheduling jitter.
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final state = container.read(importControllerProvider('camp-1'));
    expect(
      state.job.value?.status,
      ImportStatus.failed,
      reason:
          'hitting the cap must flip the job to a visible failed state — '
          'leaving it at "processing" renders as a permanent spinner',
    );
    expect(state.job.hasError, isFalse);

    final callsAtCap = repo.pollCalls;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(
      repo.pollCalls,
      callsAtCap,
      reason:
          'the cap must stop the timer, not just relabel the state '
          'while polling keeps going',
    );
  });
}
