import '../../core/result/result.dart';
import 'import_job.dart';

/// Bulk import operations (W-07). The dry run validates every row without
/// committing; commit persists only valid rows and is idempotent (§9.2).
abstract interface class ImportRepository {
  Future<Result<ImportJob>> uploadDryRun(
    String campaignId, {
    required List<int> bytes,
    required String filename,
  });

  Future<Result<ImportJob>> commit(String jobId);
}
