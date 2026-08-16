import '../../core/result/result.dart';
import 'analytics_summary.dart';

/// Repository interface lives in the domain layer; the Dio implementation
/// lives in data/. Features depend only on this abstraction.
abstract interface class AnalyticsRepository {
  Future<Result<AnalyticsSummary>> summary(AnalyticsQuery query);
}
