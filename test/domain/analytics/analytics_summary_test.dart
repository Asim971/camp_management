import 'package:acsl_campaign/domain/analytics/analytics_summary.dart';
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AnalyticsSummary.fromWire parses the full envelope', () {
    final s = AnalyticsSummary.fromWire({
      'funnel': {
        'target': 500,
        'registered': 320,
        'captured': 210,
        'inReview': 9,
        'approved': 180,
        'rejected': 12,
        'returned': 6,
      },
      'verifiedPerDay': [
        {'date': '2026-08-01', 'count': 14},
        {'date': '2026-08-03', 'count': 2},
      ],
      'bandMix': {'HIGH': 120, 'MEDIUM': 60, 'LOW': 18, 'NO_REFERENCE': 12},
      'campaigns': [
        {
          'id': 'CAMP-1',
          'name': 'ACSL Pilot Carpenter Drive',
          'status': 'ACTIVE',
          'target': 500,
          'verified': 180,
          'inReview': 9,
        },
      ],
      'sample': {'totalAttendance': 210, 'small': false},
      'range': {'from': '2026-07-17', 'to': '2026-08-15'},
      'generatedAt': '2026-08-15T17:20:00Z',
    });
    expect(s.range.from, DateTime.utc(2026, 7, 17));
    expect(s.funnel.captured, 210);
    expect(s.verifiedPerDay, hasLength(2));
    expect(s.verifiedPerDay.first.date, DateTime.utc(2026, 8, 1));
    expect(s.bandMix[MatchBand.high], 120);
    expect(s.campaigns.single.status, CampaignStatus.active);
    expect(s.sample.small, isFalse);
  });

  test('bandMix ignores unknown band keys instead of throwing', () {
    final s = AnalyticsSummary.fromWire({
      'funnel': {
        'target': 0,
        'registered': 0,
        'captured': 0,
        'inReview': 0,
        'approved': 0,
        'rejected': 0,
        'returned': 0,
      },
      'verifiedPerDay': const [],
      'bandMix': {'HIGH': 1, 'FUTURE_BAND': 9},
      'campaigns': const [],
      'sample': {'totalAttendance': 1, 'small': true},
      'range': {'from': '2026-08-01', 'to': '2026-08-15'},
      'generatedAt': '2026-08-15T00:00:00Z',
    });
    expect(s.bandMix, {MatchBand.high: 1});
  });

  test('AnalyticsQuery equality drives provider family identity', () {
    expect(
      const AnalyticsQuery(campaignId: 'C1', range: DateRangePreset.d30),
      const AnalyticsQuery(campaignId: 'C1', range: DateRangePreset.d30),
    );
    expect(DateRangePreset.d90.days, 90);
  });
}
