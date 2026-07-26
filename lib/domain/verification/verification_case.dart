import 'package:freezed_annotation/freezed_annotation.dart';

import '../common/status.dart';
import 'verification.dart';

part 'verification_case.freezed.dart';

/// Everything a CRM verifier needs for one decision (C-02), using the minimum
/// necessary evidence. The machine result and the human decision stay separate
/// (§8.13). Image URLs are short-lived signed URLs — never permanent/public.
@freezed
class VerificationCase with _$VerificationCase {
  const factory VerificationCase({
    required String attendanceId,
    required int version, // optimistic-lock token for concurrent decisions
    required AttendanceStatus status,
    required String carpenterName,
    required String carpenterIdMasked,
    required String campaignName,
    required String sessionName,
    required DateTime capturedAt,
    required String capturedImageUrl,
    required MachineResult machine,
    String? referenceImageUrl, // null when reference source is unavailable
  }) = _VerificationCase;
}

/// Compact row for the queue (C-01). Sorted by SLA/risk, not creation time.
@freezed
class VerificationQueueItem with _$VerificationQueueItem {
  const factory VerificationQueueItem({
    required String attendanceId,
    required String carpenterName,
    required String campaignName,
    required Duration age,
    required MatchBand band,
    required ReferenceSource referenceSource,
    String? assigneeId,
  }) = _VerificationQueueItem;
}
