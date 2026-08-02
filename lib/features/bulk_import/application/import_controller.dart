import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../domain/import/import_job.dart';

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

/// Bulk Import (W-07): upload → dry run → review rows → commit valid rows.
class ImportController extends AutoDisposeFamilyNotifier<ImportState, String> {
  @override
  ImportState build(String campaignId) => const ImportState();

  Future<void> uploadDryRun(List<int> bytes, String filename) async {
    state = state.copyWith(job: const AsyncLoading());
    final res = await ref
        .read(importRepositoryProvider)
        .uploadDryRun(arg, bytes: bytes, filename: filename);
    state = state.copyWith(
      job: res.fold(
        AsyncData.new,
        (f) => AsyncError(f, StackTrace.current),
      ),
    );
  }

  Future<void> commit() async {
    final job = state.job.valueOrNull;
    if (job == null) return;
    state = state.copyWith(committing: true);
    final res = await ref.read(importRepositoryProvider).commit(job.id);
    state = state.copyWith(
      committing: false,
      job: res.fold(
        AsyncData.new,
        (f) => AsyncError(f, StackTrace.current),
      ),
    );
  }
}

final importControllerProvider = NotifierProvider.autoDispose
    .family<ImportController, ImportState, String>(ImportController.new);
