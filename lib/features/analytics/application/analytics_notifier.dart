import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../domain/analytics/analytics_summary.dart';

/// Feature-scoped state for the analytics dashboard (spec RD3.D1). Keyed by
/// [AnalyticsQuery] (campaign filter + range preset) so distinct filter
/// selections are distinct, independently cached family entries — switching
/// the range back and forth does not re-fetch what is already loaded.
class AnalyticsNotifier
    extends AutoDisposeFamilyAsyncNotifier<AnalyticsSummary, AnalyticsQuery> {
  @override
  Future<AnalyticsSummary> build(AnalyticsQuery query) async {
    final repo = ref.watch(analyticsRepositoryProvider);
    final result = await repo.summary(query);
    return result.fold(
      (summary) => summary,
      (failure) => throw failure, // surfaced as AsyncError → typed UI state
    );
  }
}

final analyticsSummaryProvider = AsyncNotifierProvider.autoDispose
    .family<AnalyticsNotifier, AnalyticsSummary, AnalyticsQuery>(
      AnalyticsNotifier.new,
    );
