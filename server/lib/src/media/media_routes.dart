import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/middleware.dart';
import '../db/pool.dart';
import '../infra/error_envelope.dart';
import 'media_repo.dart';
import 'signed_url.dart';

const int _maxUploadBytes = 8 * 1024 * 1024;

/// `POST /media/presign` (attendance_capture) mints a signed upload URL;
/// `PUT /media/upload/<id>` is bearer-less and authorized by that signature
/// (4a.D3). The upload leg must NOT be wrapped in `authenticate` — see app.dart.
Router mediaRouter({required Db db, required String signingKey}) {
  final router = Router();
  final repo = MediaRepo(db);

  router.post(
    '/media/presign',
    const Pipeline()
        .addMiddleware(requirePermission('attendance_capture'))
        .addHandler((Request request) async {
          final decoded = jsonDecode(await request.readAsString());
          final attendanceId = (decoded is Map
              ? decoded['attendanceId']
              : null);
          if (attendanceId is! String || attendanceId.isEmpty) {
            throw ApiException(
              ApiErrorCode.badRequest,
              message: 'attendanceId is required.',
            );
          }
          // Build the URL from the request host so the emulator (10.0.2.2:8080)
          // and the Cloud tunnel both reach the upload endpoint.
          final u = request.requestedUri;
          final baseUrl = '${u.scheme}://${u.authority}';
          final url = await signUploadUrl(
            baseUrl: baseUrl,
            id: attendanceId,
            signingKey: signingKey,
            now: DateTime.now(),
          );
          return Response.ok(
            jsonEncode({'url': url}),
            headers: {'content-type': 'application/json'},
          );
        }),
  );

  router.put('/media/upload/<id>', (Request request, String id) async {
    final exp = int.tryParse(request.url.queryParameters['exp'] ?? '');
    final sig = request.url.queryParameters['sig'];
    if (exp == null ||
        sig == null ||
        !await verifyUploadSignature(
          id: id,
          exp: exp,
          sig: sig,
          signingKey: signingKey,
          now: DateTime.now(),
        )) {
      throw ApiException(
        ApiErrorCode.forbidden,
        message: 'Invalid or expired upload URL.',
      );
    }
    final bytes = <int>[];
    await for (final chunk in request.read()) {
      bytes.addAll(chunk);
      if (bytes.length > _maxUploadBytes) {
        return Response(413, body: 'Evidence exceeds the size limit.');
      }
    }
    await repo.put(
      id,
      contentType:
          request.headers['content-type'] ?? 'application/octet-stream',
      bytes: bytes,
    );
    return Response.ok('');
  });

  return router;
}
