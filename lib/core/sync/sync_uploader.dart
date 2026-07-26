import 'package:dio/dio.dart';

import '../media/evidence_store.dart';
import '../result/result.dart';
import 'sync_engine.dart';

/// Transport seam for draining a [SyncTaskSpec] to the server. Kept behind an
/// interface so the [SyncEngine] is testable without a network, and so the
/// 🔒 pre-signed-URL / media contract (Task T-2.2.4) is isolated to one place.
abstract interface class SyncUploader {
  /// Uploads one task. The implementation MUST send the task's idempotency key
  /// so the server dedups replays (Architecture §9.2).
  Future<Result<void>> upload(SyncTaskSpec spec);
}

/// Dio-backed uploader. For attendance: request a short-lived pre-signed URL,
/// PUT the encrypted evidence, then confirm. Endpoints are placeholders pending
/// the media-service contract.
class DioSyncUploader implements SyncUploader {
  DioSyncUploader(this._dio, {EvidenceStore? evidenceStore})
      : _evidence = evidenceStore ?? createEvidenceStore();

  final Dio _dio;
  final EvidenceStore _evidence;

  @override
  Future<Result<void>> upload(SyncTaskSpec spec) async {
    try {
      switch (spec.type) {
        case 'attendance':
          await _uploadAttendance(spec);
        case 'import_commit':
          await _dio.post<void>(
            '/imports/commit',
            data: spec.payload,
            options: Options(headers: {'Idempotency-Key': spec.idempotencyKey}),
          );
        default:
          return Err(
            Failure(FailureKind.unknown, message: 'Unknown task ${spec.type}'),
          );
      }
      return const Ok(null);
    } catch (e) {
      // Error mapping lives in dio_client.mapDioError; the engine decides
      // retry vs give-up from the returned Failure.kind.
      return Err(_map(e));
    }
  }

  Future<void> _uploadAttendance(SyncTaskSpec spec) async {
    final encryptedPath = spec.payload['encryptedMediaPath'] as String;

    // 1) short-lived pre-signed upload URL (🔒 media contract).
    final presign = await _dio.post<Map<String, dynamic>>(
      '/media/presign',
      data: {'attendanceId': spec.idempotencyKey},
      options: Options(headers: {'Idempotency-Key': spec.idempotencyKey}),
    );
    final uploadUrl = presign.data!['url'] as String;

    // 2) PUT the encrypted bytes directly to storage.
    final bytes = await _evidence.readBytes(encryptedPath);
    await Dio().put<void>(
      uploadUrl,
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {Headers.contentLengthHeader: bytes.length},
        contentType: 'application/octet-stream',
      ),
    );

    // 3) confirm — server begins quality/PAD/1:1 and routes to CRM.
    await _dio.post<void>(
      '/attendance/${spec.idempotencyKey}/confirm',
      data: spec.payload,
      options: Options(headers: {'Idempotency-Key': spec.idempotencyKey}),
    );
  }

  Failure _map(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      final kind = switch (code) {
        401 => FailureKind.unauthorized,
        403 => FailureKind.forbidden,
        409 =>
          FailureKind.conflict, // already confirmed — treat as success upstream
        422 => FailureKind.validation,
        _ when e.type == DioExceptionType.connectionError =>
          FailureKind.network,
        _ when code != null && code >= 500 => FailureKind.server,
        _ => FailureKind.unknown,
      };
      return Failure(kind, message: e.message, code: code?.toString());
    }
    return Failure(FailureKind.unknown, message: e.toString());
  }
}
