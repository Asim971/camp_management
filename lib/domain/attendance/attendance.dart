import 'package:freezed_annotation/freezed_annotation.dart';

import '../common/status.dart';

part 'attendance.freezed.dart';

/// Execution-time attendance record (PRD Appendix B "Attendance", FR-009).
/// [mediaRef] resolves to encrypted evidence via a short-lived signed URL; the
/// raw image is never embedded in the record or a public URL.
@freezed
class Attendance with _$Attendance {
  const factory Attendance({
    required String id, // == client idempotency key on capture
    required String campaignId,
    required String sessionId,
    required String carpenterId,
    required AttendanceStatus status,
    String? mediaRef,
    DateTime? capturedAt,
    String? capturedBy,
    @Default(<IntegrityFlag>[]) List<IntegrityFlag> flags,
  }) = _Attendance;
}
