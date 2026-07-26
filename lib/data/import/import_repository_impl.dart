import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../../core/result/result.dart';
import '../../domain/common/status.dart';
import '../../domain/import/import_job.dart';

class ImportRepositoryImpl implements ImportRepository {
  ImportRepositoryImpl(this._dio);
  final Dio _dio;

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
  Future<Result<ImportJob>> commit(String jobId) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/imports/$jobId/commit',
        options: Options(headers: {'Idempotency-Key': jobId}),
      );
      return Ok(_fromJson(res.data!));
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  ImportJob _fromJson(Map<String, dynamic> j) => ImportJob(
        id: j['id'] as String,
        campaignId: j['campaignId'] as String,
        status: ImportStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => ImportStatus.dryRun,
        ),
        rows: [
          for (final r in (j['rows'] as List? ?? []))
            _rowFromJson(r as Map<String, dynamic>),
        ],
      );

  ImportRow _rowFromJson(Map<String, dynamic> j) => ImportRow(
        rowId: j['rowId'] as String,
        name: (j['name'] as String?) ?? '',
        outcome: ImportRowOutcome.values.firstWhere(
          (o) => o.name == j['outcome'],
          orElse: () => ImportRowOutcome.error,
        ),
        message: j['message'] as String?,
        linkedCarpenterId: j['linkedCarpenterId'] as String?,
      );
}
