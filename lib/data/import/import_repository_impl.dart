import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';

import '../../core/network/dio_client.dart';
import '../../core/network/trace_options.dart';
import '../../core/result/result.dart';
import '../../core/trace/trace_id.dart';
import '../../domain/common/status.dart';
import '../../domain/import/import_job.dart';
import '../../domain/import/import_repository.dart';

const _uuid = Uuid();

class ImportRepositoryImpl implements ImportRepository {
  ImportRepositoryImpl(this._dio);
  final Dio _dio;

  /// [headers] carry the request's own concerns (e.g. an idempotency key);
  /// [trace] is layered in via `extra` alongside them. `null` trace lets
  /// CorrelationIdInterceptor mint a per-request id.
  Options _options(Map<String, String> headers, TraceId? trace) => Options(
    headers: headers,
    extra: trace == null ? null : {traceIdExtraKey: trace},
  );

  @override
  Future<Result<ImportJob>> uploadDryRun(
    String campaignId, {
    required List<int> bytes,
    required String filename,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final res = await _dio.post<Map<String, dynamic>>(
        '/campaigns/$campaignId/imports/dry-run',
        data: form,
      );
      return Ok(_fromJson(res.data!));
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  @override
  Future<Result<ImportJob>> poll(String jobId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/imports/$jobId');
      return Ok(_fromJson(res.data!));
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  @override
  Future<Result<ImportJob>> commit(
    String campaignId,
    String jobId, {
    TraceId? trace,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/campaigns/$campaignId/imports/$jobId/commit',
        options: _options({'Idempotency-Key': _uuid.v4()}, trace),
      );
      return Ok(_fromJson(res.data!));
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  ImportJob _fromJson(Map<String, dynamic> j) {
    final wireStatus = j['status'] as String;
    final parsedStatus = ImportStatus.tryParseWire(wireStatus);
    // An unrecognized wire status is a chosen fallback, not a silent default:
    // `ImportJob` carries no free-text field for it, so the "message" this
    // fallback owes the reader is a debug-visible log line naming the raw
    // wire value, while the job itself is surfaced as `failed` — the most
    // conservative terminal state (no rows read as committable) — rather
    // than silently read as e.g. still a fresh dry run.
    if (parsedStatus == null) {
      debugPrint(
        'ImportRepositoryImpl: unrecognised import status "$wireStatus" for '
        'job ${j['id']}; treating it as failed.',
      );
    }
    final status = parsedStatus ?? ImportStatus.failed;
    return ImportJob(
      id: j['id'] as String,
      campaignId: j['campaignId'] as String,
      status: status,
      rows: [
        // A PROCESSING job's rows are not yet classified: the server's
        // `find()` returns them with `outcome: null` until `classify`
        // reaches them. Those rows carry no useful outcome for the UI yet —
        // progress during PROCESSING is read from the job's own
        // totalRows/processedRows — so they're skipped here rather than
        // forced through a non-nullable cast. Every row carries a non-null
        // outcome once the job reaches READY_TO_COMMIT, so nothing is lost
        // by the time the UI needs to render row-level results.
        for (final r in (j['rows'] as List? ?? []).cast<Map<String, dynamic>>())
          if (r['outcome'] != null) _rowFromJson(r),
      ],
    );
  }

  ImportRow _rowFromJson(Map<String, dynamic> j) {
    final wireOutcome = j['outcome'] as String;
    // Same policy as the job status above: an unrecognized row outcome is
    // surfaced as `error` — a visible, chosen fallback — never silently
    // treated as e.g. `valid`.
    final outcome =
        ImportRowOutcome.tryParseWire(wireOutcome) ?? ImportRowOutcome.error;
    return ImportRow(
      rowId: j['rowId'] as String,
      name: (j['name'] as String?) ?? '',
      outcome: outcome,
      message: j['message'] as String?,
      linkedCarpenterId: j['linkedCarpenterId'] as String?,
    );
  }
}
