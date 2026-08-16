import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/domain/analytics/analytics_repository.dart';
import 'package:acsl_campaign/domain/analytics/analytics_summary.dart';
import 'package:acsl_campaign/features/analytics/application/analytics_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/harness.dart';

/// In-memory [AnalyticsRepository] that records every query it was called
/// with and returns a fixed [Result] regardless of the query — the fake
/// mirrors the campaign/verification fakes elsewhere in the suite (e.g.
/// `_FakeCampaignRepository` in `test/features/dashboard/dashboard_notifier_test.dart`).
class _FakeAnalyticsRepository implements AnalyticsRepository {
  _FakeAnalyticsRepository(this._result);

  final Result<AnalyticsSummary> _result;
  final List<AnalyticsQuery> queriesSeen = [];

  @override
  Future<Result<AnalyticsSummary>> summary(AnalyticsQuery query) async {
    queriesSeen.add(query);
    return _result;
  }
}

AnalyticsSummary _summary() => AnalyticsSummary(
  funnel: const AnalyticsFunnel(
    target: 100,
    registered: 80,
    captured: 60,
    inReview: 10,
    approved: 40,
    rejected: 5,
    returned: 5,
  ),
  verifiedPerDay: [DailyCount(date: DateTime.utc(2026, 8, 10), count: 4)],
  bandMix: const {},
  campaigns: const [],
  sample: const AnalyticsSample(totalAttendance: 60, small: false),
  range: AnalyticsRange(
    from: DateTime.utc(2026, 7, 17),
    to: DateTime.utc(2026, 8, 15),
  ),
  generatedAt: DateTime.utc(2026, 8, 15, 9),
);

void main() {
  test("build() returns the fake's summary for the query it was called with, "
      'and the query (campaignId + range) passes through unchanged', () async {
    final summary = _summary();
    final repo = _FakeAnalyticsRepository(Ok(summary));
    final container = buildTestContainer(
      overrides: [analyticsRepositoryProvider.overrideWithValue(repo)],
    );

    const query = AnalyticsQuery(campaignId: 'c1', range: DateRangePreset.d90);
    final result = await container.read(analyticsSummaryProvider(query).future);

    expect(result, summary);
    expect(repo.queriesSeen, [query]);
    expect(repo.queriesSeen.single.campaignId, 'c1');
    expect(repo.queriesSeen.single.range, DateRangePreset.d90);
  });

  test('a Failure from the repository surfaces as AsyncError', () async {
    final repo = _FakeAnalyticsRepository(
      const Err(Failure(FailureKind.network)),
    );
    final container = buildTestContainer(
      overrides: [analyticsRepositoryProvider.overrideWithValue(repo)],
    );

    const query = AnalyticsQuery();

    await expectLater(
      container.read(analyticsSummaryProvider(query).future),
      throwsA(isA<Failure>()),
    );
    expect(
      container.read(analyticsSummaryProvider(query)),
      isA<AsyncError<AnalyticsSummary>>(),
    );
  });

  test('distinct queries are distinct family entries — each is fetched '
      'independently rather than sharing one cached result', () async {
    final repo = _FakeAnalyticsRepository(Ok(_summary()));
    final container = buildTestContainer(
      overrides: [analyticsRepositoryProvider.overrideWithValue(repo)],
    );

    const queryA = AnalyticsQuery(range: DateRangePreset.d7);
    const queryB = AnalyticsQuery(campaignId: 'c2', range: DateRangePreset.d30);

    await container.read(analyticsSummaryProvider(queryA).future);
    await container.read(analyticsSummaryProvider(queryB).future);

    expect(repo.queriesSeen, [queryA, queryB]);
    expect(repo.queriesSeen.length, 2);
  });
}
