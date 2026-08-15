import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_shell.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/design_system/screen_hero.dart';
import '../../../domain/analytics/analytics_summary.dart';
import '../../campaign_list/application/campaign_list_notifier.dart';
import 'analytics_panel.dart';
import 'widgets/range_chip_row.dart';

/// Campaign Analytics (spec A-02) — the global mount of [AnalyticsPanel].
///
/// Holds the [AnalyticsQuery] itself: a campaign filter (all campaigns, or
/// one specific campaign, via [_CampaignFilter]) crossed with the range
/// preset (via [RangeChipRow]), both of which simply rebuild `_query`, which
/// re-keys the `analyticsSummaryProvider` family entry `AnalyticsPanel`
/// watches internally.
///
/// Reached via go_router's `/analytics`, gated by `Permission.export` in
/// `route_table.dart` — that gate lives entirely in the router/redirect
/// layer and this widget has no knowledge of it.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  AnalyticsQuery _query = const AnalyticsQuery();

  @override
  Widget build(BuildContext context) {
    final campaigns =
        ref.watch(campaignListProvider).valueOrNull?.items ?? const [];

    return AppShell(
      title: 'Campaign analytics',
      body: ListView(
        padding: const EdgeInsets.only(bottom: BmdSpace.s6),
        children: [
          ScreenHero(
            title: 'Campaign analytics',
            subtitle:
                'Campaign-linked contribution — activity, not sales impact',
            summary: [
              RangeChipRow(
                value: _query.range,
                onChanged: (range) =>
                    setState(() => _query = _query.copyWith(range: range)),
              ),
            ],
            actions: [
              Semantics(
                identifier: 'analytics_campaign_filter',
                child: DropdownButton<String?>(
                  value: _query.campaignId,
                  onChanged: (id) =>
                      setState(() => _query = _query.copyWith(campaignId: id)),
                  items: [
                    const DropdownMenuItem<String?>(
                      child: Text('All campaigns'),
                    ),
                    for (final c in campaigns)
                      DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(c.name),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: BmdSpace.s6),
          AnalyticsPanel(query: _query),
        ],
      ),
    );
  }
}
