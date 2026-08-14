import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/middleware.dart';
import '../db/pool.dart';
import '../infra/correlation.dart';
import '../infra/error_envelope.dart';
import '../infra/idempotency.dart';
import 'attendance_repo.dart';

/// `POST /attendance/<key>/confirm` — attendance_capture + the existing
/// Idempotency-Key middleware. Idempotent replay returns the stored response,
/// which the client treats as success.
Router attendanceRouter({required Db db}) {
  final router = Router();
  final repo = AttendanceRepo(db);

  router.post(
    '/attendance/<key>/confirm',
    const Pipeline()
        .addMiddleware(requirePermission('attendance_capture'))
        .addMiddleware(idempotency(db: db))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final key = request.params['key']!;
          final decoded = jsonDecode(await request.readAsString());
          final payload = (decoded as Map).cast<String, Object?>();
          final result = await repo.confirm(
            attendanceId: key,
            organizationId: auth.organizationId,
            capturedBy: auth.userId,
            payload: payload,
            correlationId: correlationOf(request),
          );
          switch (result.outcome) {
            case AttendanceConfirmOutcome.confirmed:
              return Response.ok(
                jsonEncode({'status': result.status, 'id': key}),
                headers: {'content-type': 'application/json'},
              );
            case AttendanceConfirmOutcome.sessionNotFound:
            case AttendanceConfirmOutcome.carpenterNotFound:
              throw ApiException(ApiErrorCode.notFound);
            case AttendanceConfirmOutcome.evidenceMissing:
              throw ApiException(
                ApiErrorCode.attendanceEvidenceMissing,
                message: 'No uploaded evidence for this attendance.',
              );
          }
        }),
  );

  return router;
}
