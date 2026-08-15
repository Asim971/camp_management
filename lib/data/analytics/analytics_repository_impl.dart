import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../../core/result/result.dart';
import '../../domain/analytics/analytics_repository.dart';
import '../../domain/analytics/analytics_summary.dart';

/// Dio-backed [AnalyticsRepository]. Translates wire JSON → domain (via
/// [AnalyticsSummary.fromWire]) and Dio errors → [Failure].
///
/// This is the ONLY place client-side "today" is computed (spec RD3.D1):
/// `to` is today's UTC date and `from` is `to - (range.days - 1)`, both
/// serialized `yyyy-MM-dd` (the first 10 chars of `toIso8601String()`).
/// Presentation must consume the summary's echoed `range` instead of
/// recomputing "today" itself.
class AnalyticsRepositoryImpl implements AnalyticsRepository {
  AnalyticsRepositoryImpl(this._dio);

  final Dio _dio;

  @override
  Future<Result<AnalyticsSummary>> summary(AnalyticsQuery query) async {
    try {
      final now = DateTime.now().toUtc();
      final to = DateTime.utc(now.year, now.month, now.day);
      final from = to.subtract(Duration(days: query.range.days - 1));
      final res = await _dio.get<Map<String, dynamic>>(
        '/analytics/summary',
        queryParameters: {
          if (query.campaignId != null) 'campaignId': query.campaignId,
          'from': _wireDate(from),
          'to': _wireDate(to),
        },
      );
      return Ok(AnalyticsSummary.fromWire(res.data!));
    } catch (e) {
      return Err(mapDioError(e));
    }
  }
}

String _wireDate(DateTime date) => date.toIso8601String().substring(0, 10);
