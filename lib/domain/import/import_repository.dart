import '../../core/result/result.dart';
import '../../core/trace/trace_id.dart';
import 'import_job.dart';

/// Bulk import operations (W-07). The dry run validates every row without
/// committing; commit persists only valid rows and is idempotent (§9.2).
abstract interface class ImportRepository {
  Future<Result<ImportJob>> uploadDryRun(
    String campaignId, {
    required List<int> bytes,
    required String filename,
  });

  /// [trace] is the per-action correlation id; pass the same one to the audit
  /// event for this action so the two can be joined (Architecture §12).
  Future<Result<ImportJob>> commit(String jobId, {TraceId? trace});
}
