import 'package:campaign_contracts/campaign_contracts.dart'
    show ImportRowOutcome;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../common/status.dart';

export 'package:campaign_contracts/campaign_contracts.dart'
    show ImportRowOutcome;

part 'import_job.freezed.dart';

/// A bulk registration import (W-07, FR-004/005). Every row carries a stable id
/// and an explicit outcome — never a single generic "upload failed" (§8.7).
@freezed
class ImportJob with _$ImportJob {
  const factory ImportJob({
    required String id,
    required String campaignId,
    required ImportStatus status,
    @Default(<ImportRow>[]) List<ImportRow> rows,
  }) = _ImportJob;

  const ImportJob._();

  int count(ImportRowOutcome o) => rows.where((r) => r.outcome == o).length;

  int get committable =>
      count(ImportRowOutcome.valid) + count(ImportRowOutcome.needsProfile);
}

@freezed
class ImportRow with _$ImportRow {
  const factory ImportRow({
    required String rowId,
    required String name,
    required ImportRowOutcome outcome,
    String? message,
    String? linkedCarpenterId,
  }) = _ImportRow;
}
