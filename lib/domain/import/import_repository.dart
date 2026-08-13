import '../../core/result/result.dart';
import '../../core/trace/trace_id.dart';
import 'import_job.dart';

/// Bulk import operations (W-07). The dry run validates every row without
/// committing; commit persists the committable rows (valid + needs-profile)
/// and is idempotent (§9.2).
abstract interface class ImportRepository {
  Future<Result<ImportJob>> uploadDryRun(
    String campaignId, {
    required List<int> bytes,
    required String filename,
  });

  /// Polls the job's current state (`GET /imports/{jobId}`) while it is
  /// processing asynchronously on the server.
  Future<Result<ImportJob>> poll(String jobId);

  /// Commits [jobId] under its owning [campaignId] — the path is namespaced
  /// as `/campaigns/{campaignId}/imports/{jobId}/commit`, so an id alone is
  /// no longer enough to name the resource.
  ///
  /// [trace] is the per-action correlation id; pass the same one to the audit
  /// event for this action so the two can be joined (Architecture §12).
  Future<Result<ImportJob>> commit(
    String campaignId,
    String jobId, {
    TraceId? trace,
  });
}
