import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../../core/network/trace_options.dart';
import '../../core/result/result.dart';
import '../../core/trace/trace_id.dart';
import '../../domain/common/status.dart';
import '../../domain/verification/verification.dart';
import '../../domain/verification/verification_case.dart';
import '../../domain/verification/verification_repository.dart';

/// Dio-backed [VerificationRepository]. Endpoints are placeholders pending the
/// verification-service contract. Signed image URLs are requested per-case and
/// are short-lived; they are never cached to a public/permanent location.
class VerificationRepositoryImpl implements VerificationRepository {
  VerificationRepositoryImpl(this._dio);

  final Dio _dio;

  /// [headers] carry the request's own concerns (the optimistic-lock
  /// `If-Match`); [trace] is layered in via `extra` alongside them. `null`
  /// trace lets CorrelationIdInterceptor mint a per-request id.
  Options _options(Map<String, String> headers, TraceId? trace) => Options(
    headers: headers,
    extra: trace == null ? null : {traceIdExtraKey: trace},
  );

  @override
  Future<Result<List<VerificationQueueItem>>> queue({
    String? assigneeId,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/verification/queue',
        queryParameters: {if (assigneeId != null) 'assignee': assigneeId},
      );
      final items = (res.data!['items'] as List)
          .map((e) => _queueItem(e as Map<String, dynamic>))
          .toList();
      return Ok(items);
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  @override
  Future<Result<VerificationCase>> getCase(String attendanceId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/verification/cases/$attendanceId',
      );
      return Ok(_case(res.data!));
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  @override
  Future<Result<void>> decide(
    VerificationDecision decision, {
    required int expectedVersion,
    TraceId? trace,
  }) async {
    try {
      await _dio.post<void>(
        '/verification/cases/${decision.attendanceId}/decision',
        data: {
          'outcome': decision.outcome.name,
          'reason': decision.reason,
          'supervisorOverride': decision.supervisorOverride,
        },
        options: _options({'If-Match': '$expectedVersion'}, trace),
      );
      return const Ok(null);
    } catch (e) {
      return Err(mapDioError(e)); // 409 → FailureKind.conflict
    }
  }

  // ---- mappers -------------------------------------------------------------

  VerificationQueueItem _queueItem(Map<String, dynamic> j) =>
      VerificationQueueItem(
        attendanceId: j['attendanceId'] as String,
        carpenterName: j['carpenterName'] as String,
        campaignName: j['campaignName'] as String,
        age: Duration(seconds: j['ageSeconds'] as int),
        band: _band(j['band'] as String?),
        referenceSource: _refSource(j['referenceSource'] as String?),
        assigneeId: j['assigneeId'] as String?,
      );

  VerificationCase _case(Map<String, dynamic> j) => VerificationCase(
    attendanceId: j['attendanceId'] as String,
    version: j['version'] as int,
    status: AttendanceStatus.crmReview,
    carpenterName: j['carpenterName'] as String,
    carpenterIdMasked: j['carpenterIdMasked'] as String,
    campaignName: j['campaignName'] as String,
    sessionName: j['sessionName'] as String,
    capturedAt: DateTime.parse(j['capturedAt'] as String),
    capturedImageUrl: j['capturedImageUrl'] as String,
    referenceImageUrl: j['referenceImageUrl'] as String?,
    machine: MachineResult(
      band: _band(j['band'] as String?),
      referenceSource: _refSource(j['referenceSource'] as String?),
      padReview: (j['padReview'] as bool?) ?? false,
      lowQuality: (j['lowQuality'] as bool?) ?? false,
      reasons: ((j['reasons'] as List?) ?? []).cast<String>(),
    ),
  );

  MatchBand _band(String? s) => switch (s) {
    'high' => MatchBand.high,
    'medium' => MatchBand.medium,
    'low' => MatchBand.low,
    _ => MatchBand.noReference,
  };

  ReferenceSource _refSource(String? s) => switch (s) {
    'verifiedProfilePhoto' => ReferenceSource.verifiedProfilePhoto,
    'authorizedNidPhoto' => ReferenceSource.authorizedNidPhoto,
    'approvedBaselinePhoto' => ReferenceSource.approvedBaselinePhoto,
    _ => ReferenceSource.unavailable,
  };
}
