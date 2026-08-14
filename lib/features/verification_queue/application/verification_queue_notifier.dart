import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/result/result.dart';
import '../../../domain/verification/verification_case.dart';
import '../../../domain/verification/verification_repository.dart';

/// Outcome of a claim/release action, so the screen can react precisely: a
/// conflict (someone else claimed/decided first) shows a specific message
/// rather than a generic failure (mirrors `DecisionResult` in
/// `crm_case_controller.dart`).
enum QueueActionResult { done, conflict, error }

/// Loads the verification queue for one [QueueFilter] (C-01) and exposes
/// claim/release actions that refresh the list on success.
class VerificationQueueNotifier
    extends
        AutoDisposeFamilyAsyncNotifier<
          List<VerificationQueueItem>,
          QueueFilter
        > {
  @override
  Future<List<VerificationQueueItem>> build(QueueFilter filter) =>
      _fetch(filter);

  Future<List<VerificationQueueItem>> _fetch(QueueFilter filter) async {
    final repo = ref.read(verificationRepositoryProvider);
    final result = await repo.queue(filter: filter);
    return result.fold(
      (items) => items,
      (failure) => throw failure, // surfaced as AsyncError → typed UI state
    );
  }

  Future<QueueActionResult> claim(String attendanceId) =>
      _act((repo) => repo.claim(attendanceId));

  Future<QueueActionResult> release(String attendanceId) =>
      _act((repo) => repo.release(attendanceId));

  Future<QueueActionResult> _act(
    Future<Result<void>> Function(VerificationRepository repo) call,
  ) async {
    final repo = ref.read(verificationRepositoryProvider);
    final result = await call(repo);
    return result.fold(
      (_) {
        ref.invalidateSelf(); // reload so the acted-on item's state is fresh
        return QueueActionResult.done;
      },
      (failure) {
        if (failure.kind == FailureKind.conflict) {
          // Someone else claimed/decided it first — reload so the item shows
          // its real, current assignee rather than the stale one this screen
          // was still showing.
          ref.invalidateSelf();
          return QueueActionResult.conflict;
        }
        return QueueActionResult.error;
      },
    );
  }
}

final verificationQueueProvider = AsyncNotifierProvider.autoDispose
    .family<
      VerificationQueueNotifier,
      List<VerificationQueueItem>,
      QueueFilter
    >(VerificationQueueNotifier.new);
