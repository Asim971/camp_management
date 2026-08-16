import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'analytics_summary.freezed.dart';

/// The three range presets the analytics filter offers (spec RD3.D1); the
/// query sends explicit from/to dates computed from `days`.
enum DateRangePreset {
  d7(7),
  d30(30),
  d90(90);

  const DateRangePreset(this.days);
  final int days;
}

@freezed
class AnalyticsQuery with _$AnalyticsQuery {
  const factory AnalyticsQuery({
    String? campaignId,
    @Default(DateRangePreset.d30) DateRangePreset range,
  }) = _AnalyticsQuery;
}

@freezed
class AnalyticsFunnel with _$AnalyticsFunnel {
  const factory AnalyticsFunnel({
    required int target,
    required int registered,
    required int captured,
    required int inReview,
    required int approved,
    required int rejected,
    required int returned,
  }) = _AnalyticsFunnel;
}

@freezed
class DailyCount with _$DailyCount {
  const factory DailyCount({required DateTime date, required int count}) =
      _DailyCount;
}

@freezed
class AnalyticsCampaignRow with _$AnalyticsCampaignRow {
  const factory AnalyticsCampaignRow({
    required String id,
    required String name,
    required CampaignStatus status,
    required int target,
    required int verified,
    required int inReview,
  }) = _AnalyticsCampaignRow;
}

@freezed
class AnalyticsSample with _$AnalyticsSample {
  const factory AnalyticsSample({
    required int totalAttendance,
    required bool small,
  }) = _AnalyticsSample;
}

@freezed
class AnalyticsRange with _$AnalyticsRange {
  const factory AnalyticsRange({required DateTime from, required DateTime to}) =
      _AnalyticsRange;
}

@freezed
class AnalyticsSummary with _$AnalyticsSummary {
  const factory AnalyticsSummary({
    required AnalyticsFunnel funnel,
    required List<DailyCount> verifiedPerDay,
    required Map<MatchBand, int> bandMix,
    required List<AnalyticsCampaignRow> campaigns,
    required AnalyticsSample sample,
    required AnalyticsRange range,
    required DateTime generatedAt,
  }) = _AnalyticsSummary;

  /// Wire → domain. Unknown band keys are skipped (a future server band must
  /// not crash an older client); unknown campaign statuses fall back the way
  /// `campaignFromWire` handles them (use `CampaignStatus` tryParse + throw,
  /// matching the strictness of `lib/data/campaign/campaign_mapper.dart` —
  /// read it and mirror its exact status-parse behavior).
  factory AnalyticsSummary.fromWire(Map<String, dynamic> json) {
    // Parse funnel
    final funnelJson = json['funnel'] as Map<String, dynamic>;
    final funnel = AnalyticsFunnel(
      target: funnelJson['target'] as int,
      registered: funnelJson['registered'] as int,
      captured: funnelJson['captured'] as int,
      inReview: funnelJson['inReview'] as int,
      approved: funnelJson['approved'] as int,
      rejected: funnelJson['rejected'] as int,
      returned: funnelJson['returned'] as int,
    );

    // Parse verifiedPerDay
    final verifiedPerDayJson = json['verifiedPerDay'] as List<dynamic>;
    final verifiedPerDay = [
      for (final item in verifiedPerDayJson)
        _parseDailyCount(item as Map<String, dynamic>),
    ];

    // Parse bandMix - skip unknown band keys
    final bandMixJson = json['bandMix'] as Map<String, dynamic>;
    final bandMix = <MatchBand, int>{};
    for (final entry in bandMixJson.entries) {
      final band = MatchBand.tryParseWire(entry.key);
      if (band != null) {
        bandMix[band] = entry.value as int;
      }
    }

    // Parse campaigns - use strict status parsing like campaign_mapper.dart
    final campaignsJson = json['campaigns'] as List<dynamic>;
    final campaigns = [
      for (final item in campaignsJson)
        _parseCampaignRow(item as Map<String, dynamic>),
    ];

    // Parse sample
    final sampleJson = json['sample'] as Map<String, dynamic>;
    final sample = AnalyticsSample(
      totalAttendance: sampleJson['totalAttendance'] as int,
      small: sampleJson['small'] as bool,
    );

    // Parse range
    final rangeJson = json['range'] as Map<String, dynamic>;
    final range = AnalyticsRange(
      from: DateTime.parse('${rangeJson['from']}T00:00:00Z'),
      to: DateTime.parse('${rangeJson['to']}T00:00:00Z'),
    );

    // Parse generatedAt
    final generatedAt = DateTime.parse(json['generatedAt'] as String).toUtc();

    return AnalyticsSummary(
      funnel: funnel,
      verifiedPerDay: verifiedPerDay,
      bandMix: bandMix,
      campaigns: campaigns,
      sample: sample,
      range: range,
      generatedAt: generatedAt,
    );
  }
}

/// Helper to parse a daily count entry.
DailyCount _parseDailyCount(Map<String, dynamic> json) {
  return DailyCount(
    date: DateTime.parse('${json['date']}T00:00:00Z'),
    count: json['count'] as int,
  );
}

/// Helper to parse a campaign row with strict status validation.
/// Mirrors the behavior of campaign_mapper.dart: throws FormatException
/// on unrecognised status.
AnalyticsCampaignRow _parseCampaignRow(Map<String, dynamic> json) {
  final rawStatus = json['status'];
  if (rawStatus is! String) {
    throw FormatException('Campaign row is missing a status.', json.toString());
  }
  final status = CampaignStatus.tryParseWire(rawStatus);
  if (status == null) {
    throw FormatException(
      'Unrecognised campaign status "$rawStatus". This app version cannot '
      'safely display this campaign.',
      rawStatus,
    );
  }
  return AnalyticsCampaignRow(
    id: json['id'] as String,
    name: json['name'] as String,
    status: status,
    target: json['target'] as int,
    verified: json['verified'] as int,
    inReview: json['inReview'] as int,
  );
}
