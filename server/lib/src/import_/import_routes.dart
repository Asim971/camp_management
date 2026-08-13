import 'dart:async';
import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:cryptography/dart.dart' show DartSha256;
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/shelf_multipart.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/middleware.dart';
import '../db/pool.dart';
import '../infra/correlation.dart';
import '../infra/error_envelope.dart';
import '../infra/idempotency.dart';
import 'import_file.dart';
import 'import_repo.dart';

/// `/campaigns/<id>/imports/*` and `/imports/<jobId>`. Reads and writes all
/// require `bulk_import` (no read-only import role in the claim vocabulary).
///
/// [databaseUrl] lets the background classify task open its OWN Db connection
/// (2b.D1) — the request-serving connection must never be held for a classify.
Router importRouter({required Db db, required String databaseUrl}) {
  final router = Router();
  final repo = ImportRepo(db);

  router.post(
    '/campaigns/<id>/imports/dry-run',
    const Pipeline().addMiddleware(requirePermission('bulk_import')).addHandler(
      (Request request) async {
        final auth = authOf(request);
        final campaignId = request.params['id']!;

        // Opportunistic reaper on the write path (2b.D2), same shape as
        // idempotency's sweep.
        await repo.reapStale();

        final upload = await _readFilePart(request);
        if (upload == null) {
          throw ApiException(
            ApiErrorCode.badRequest,
            message: 'Expected a multipart "file" part.',
          );
        }
        final parsed = parseImportCsv(upload.bytes); // throws 422 on bad file
        final fileHash = base64.encode(
          const DartSha256().hashSync(upload.bytes).bytes,
        );

        final job = await repo.createJob(
          campaignId: campaignId,
          organizationId: auth.organizationId,
          parsed: parsed,
          filename: upload.filename ?? 'import.csv',
          fileHash: fileHash,
          uploadedBy: auth.userId,
        );
        if (job == null) throw ApiException(ApiErrorCode.notFound);

        // Fire-and-forget classify on its OWN connection (2b.D1). unawaited
        // satisfies the lint; the task swallows its own faults into a FAILED
        // flip (§6a), so no unhandled error can reach the top level.
        unawaited(_classifyInBackground(databaseUrl, job.id));

        return Response(
          202,
          body: jsonEncode(job.toWireJson()),
          headers: {'content-type': 'application/json'},
        );
      },
    ),
  );

  router.get('/imports/<jobId>', (Request request, String jobId) async {
    final auth = authOf(request);
    await repo.reapStale();
    final job = await repo.find(jobId, organizationId: auth.organizationId);
    if (job == null) throw ApiException(ApiErrorCode.notFound);
    return Response.ok(
      jsonEncode(job.toWireJson()),
      headers: {'content-type': 'application/json'},
    );
  });

  router.post(
    '/campaigns/<id>/imports/<jobId>/commit',
    const Pipeline()
        .addMiddleware(requirePermission('bulk_import'))
        .addMiddleware(idempotency(db: db))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final campaignId = request.params['id']!;
          final jobId = request.params['jobId']!;
          final job = await repo.commit(
            campaignId: campaignId,
            organizationId: auth.organizationId,
            jobId: jobId,
            committedBy: auth.userId,
            correlationId: correlationOf(request),
          );
          if (job == null) throw ApiException(ApiErrorCode.notFound);
          return Response.ok(
            jsonEncode(job.toWireJson()),
            headers: {'content-type': 'application/json'},
          );
        }),
  );

  return router;
}

/// Opens a fresh connection and runs the classify, closing after. Any error
/// is already swallowed inside [ImportRepo.classify]; this wrapper also guards
/// the open/close so a connection fault cannot escape either (§6a).
Future<void> _classifyInBackground(String databaseUrl, String jobId) async {
  Db? worker;
  try {
    worker = await Db.open(databaseUrl);
    await ImportRepo(worker).classify(jobId);
  } on Object {
    // The job stays PROCESSING and the reaper (TTL) will fail it.
  } finally {
    await worker?.close();
  }
}

/// Reads the single `file` part from a multipart/form-data request, or null if
/// there is no such part. API verified against shelf_multipart 2.0.1 source:
/// `request.formData()` → `FormDataRequest?`; `form.formData` is a
/// `Stream<FormData>`; `FormData` exposes `.name` (String), `.filename`
/// (String?), and `.part` (a `Multipart` with `.readBytes() → Future<Uint8List>`).
Future<({List<int> bytes, String? filename})?> _readFilePart(
  Request request,
) async {
  final form = request.formData();
  if (form == null) return null;
  await for (final formData in form.formData) {
    if (formData.name == 'file') {
      return (
        bytes: await formData.part.readBytes(),
        filename: formData.filename,
      );
    }
  }
  return null;
}
