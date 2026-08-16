import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/app_shell.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/auth/permission_gate.dart';
import '../../../core/auth/rbac.dart';
import '../../../core/design_system/bmd_button.dart';
import '../../../core/design_system/bmd_cards.dart';
import '../../../core/design_system/bmd_state_view.dart';
import '../../../core/design_system/screen_hero.dart';
import '../../../core/design_system/status_chip.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/motion/reveal.dart';
import '../../../domain/analytics/analytics_summary.dart';
import '../../../domain/common/status.dart';
import '../../../domain/common/status_labels.dart';
import '../../../domain/session/campaign_session.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../analytics/presentation/analytics_panel.dart';
import '../../analytics/presentation/widgets/range_chip_row.dart';
import '../application/campaign_detail_controller.dart';

/// Campaign Detail & Session Operations (W-05). One operational source: header
/// with lifecycle status + next action, and tabs for overview, sessions,
/// registrations, attendance, analytics and audit. Attendance activity is kept
/// visually distinct from commercial outcome.
class CampaignDetailScreen extends ConsumerWidget {
  const CampaignDetailScreen({required this.campaignId, super.key});
  final String campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(campaignDetailProvider(campaignId));

    return AppShell(
      title: 'Campaign detail',
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => BmdStateView.error(
          title: "Couldn't load this campaign",
          message: 'Check your connection and try again.',
          onRetry: () => ref.invalidate(campaignDetailProvider(campaignId)),
        ),
        data: (data) => DefaultTabController(
          length: 6,
          // A fixed hero+TabBar above the Column left the Sessions ListView a
          // ~96dp scroll viewport on short phone screens — found by session_ops
          // in CI, where Maestro's scrollUntilVisible swipes at screen center,
          // landing in the non-scrollable hero so session_start could never be
          // scrolled into view. NestedScrollView lets the hero scroll away with
          // the page, giving tab content real height and making gesture-at-
          // screen-center scrolling work.
          child: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverToBoxAdapter(
                child: _Header(campaignId: campaignId, data: data),
              ),
            ],
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Overview'),
                    Tab(text: 'Sessions'),
                    Tab(text: 'Registrations'),
                    Tab(text: 'Attendance'),
                    Tab(text: 'Analytics'),
                    Tab(text: 'Audit'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _OverviewTab(data: data),
                      _SessionsTab(campaignId: campaignId, data: data),
                      _RegistrationsTab(campaignId: campaignId),
                      const _Placeholder(
                        'Attendance timeline — W-05 follow-up',
                      ),
                      _DetailAnalyticsTab(campaignId: campaignId),
                      const _Placeholder('Audit trail — AD-01'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.campaignId, required this.data});
  final String campaignId;
  final CampaignDetailData data;
  @override
  Widget build(BuildContext context) {
    final c = data.campaign;

    // Contextual primary next action(s). Built once so both the presence
    // check below and the Wrap's children list see the same list — a Row
    // squeezed the Expanded(name) to near-zero on narrow viewports once a
    // second button (Bulk import) joined "Add registrations" here; a Wrap
    // lets these flow to a second line instead.
    final actions = <Widget>[
      if (c.status == CampaignStatus.pendingApproval)
        PermissionGate.disabled(
          Permission.campaignApprove,
          reason: 'Only a Marketing Approver can approve this campaign.',
          label: 'Review approval',
          child: BmdButton(
            label: 'Review approval',
            onPressed: () => context.go('/campaigns/$campaignId/approve'),
          ),
        )
      else if (c.status == CampaignStatus.approved ||
          c.status == CampaignStatus.active) ...[
        PermissionGate.disabled(
          Permission.campaignCreate,
          reason: 'Only a Campaign Creator can add registrations.',
          label: 'Add registrations',
          child: BmdButton(
            label: 'Add registrations',
            onPressed: () => context.go('/campaigns/$campaignId/register'),
          ),
        ),
        // W-07: bulk import entry point (Permission.bulkImport, route
        // '/campaigns/:id/import' — see route_table.dart). Same
        // contextual-action pattern as "Add registrations" above.
        PermissionGate.disabled(
          Permission.bulkImport,
          reason:
              'Only a user with bulk import access can import participants.',
          label: 'Bulk import',
          child: BmdButton(
            label: 'Bulk import',
            variant: BmdButtonVariant.outlined,
            onPressed: () => context.go('/campaigns/$campaignId/import'),
          ),
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ScreenHero(
        title: c.name,
        summary: [
          StatusChip(
            label: c.status.label(AppL10n.of(context)),
            tone: StatusTone.info,
          ),
        ],
        actions: actions,
        meter: _ProgressMeter(
          verified: c.verifiedAttendance,
          target: c.targetAudience,
        ),
      ),
    );
  }
}

/// S4: verified attendance vs target as a rounded linear gauge (§6.3 — the
/// defence line beneath says exactly what the number is). Cyan is the data
/// accent (never an action color). Under reduced motion the fill renders at
/// its final width in one frame ([reduced] collapses the duration; see
/// CountUp's note on TweenAnimationBuilder and zero durations).
class _ProgressMeter extends StatelessWidget {
  const _ProgressMeter({required this.verified, required this.target});
  final int verified;
  final int target;

  @override
  Widget build(BuildContext context) {
    final bmd = Theme.of(context).bmd;
    final fraction = target <= 0
        ? 0.0
        : (verified / target).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: fraction),
          duration: reduced(context, MotionDur.slow),
          curve: MotionCurve.emphasized,
          builder: (context, f, _) => ClipRRect(
            borderRadius: BorderRadius.circular(BmdRadius.chip),
            child: LinearProgressIndicator(
              value: f,
              minHeight: 10,
              backgroundColor: bmd.surfaceSunken,
              valueColor: AlwaysStoppedAnimation(bmd.accent),
            ),
          ),
        ),
        const SizedBox(height: BmdSpace.s1),
        Text(
          target <= 0 ? 'No target set' : '$verified of $target verified',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: bmd.textSecondary),
        ),
      ],
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.data});
  final CampaignDetailData data;
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        // Attendance activity counts — NOT sales impact (§1.1, §2).
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _kpi(context, 'Registered', data.registered),
            _kpi(context, 'Pending sync', data.pendingSync),
            _kpi(context, 'In review', data.inReview),
            _kpi(context, 'Approved', data.approved),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Target: ${data.campaign.targetAudience}',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }

  Widget _kpi(BuildContext context, String label, int value) => SizedBox(
    width: 260,
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: reduced(context, MotionDur.slow),
      curve: MotionCurve.emphasized,
      builder: (context, v, _) => KpiCard(
        label: label,
        value: '${v.round()}',
        definition: _definitionFor(label),
        source: 'Campaign service',
        freshness: 'Live',
        glass: true,
      ),
    ),
  );

  String _definitionFor(String label) => switch (label) {
    'Registered' => 'Participants registered across all sessions.',
    'Pending sync' => 'Captures waiting to upload from field devices.',
    'In review' => 'Attendance records awaiting CRM verification.',
    'Approved' => 'Attendance approved by verification.',
    _ => label,
  };
}

class _SessionsTab extends ConsumerWidget {
  const _SessionsTab({required this.campaignId, required this.data});
  final String campaignId;
  final CampaignDetailData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.sessions.isEmpty) {
      return const Center(child: Text('No sessions configured.'));
    }
    final c = ref.read(campaignDetailProvider(campaignId).notifier);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        for (final (i, s) in data.sessions.indexed)
          Reveal(
            index: i < 8 ? i : 8,
            child: _SessionCard(session: s, controller: c),
          ),
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.controller});
  final CampaignSession session;
  final CampaignDetailController controller;

  @override
  Widget build(BuildContext context) {
    final bmd = Theme.of(context).bmd;
    final accent = (!session.readinessOk || session.overCapacity)
        ? bmd.warning
        : bmd.info;

    return Card(
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        session.venue,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (!session.readinessOk)
                      const StatusChip(
                        label: 'Readiness',
                        tone: StatusTone.warning,
                      )
                    else if (session.overCapacity)
                      const StatusChip(
                        label: 'Over capacity',
                        tone: StatusTone.warning,
                      )
                    else
                      StatusChip(
                        label: session.status.label(AppL10n.of(context)),
                        tone: StatusTone.info,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Registered ${session.registeredCount} · pending ${session.pendingSyncCount} '
                  '· review ${session.reviewCount} · approved ${session.approvedCount}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (session.status == SessionStatus.upcoming)
                      BmdButton(
                        identifier: 'session_start',
                        label: 'Start',
                        variant: BmdButtonVariant.tonal,
                        onPressed: session.readinessOk
                            ? () => controller.startSession(session.id)
                            : null,
                      ),
                    if (session.status == SessionStatus.active) ...[
                      BmdButton(
                        identifier: 'session_pause',
                        label: 'Pause',
                        variant: BmdButtonVariant.outlined,
                        onPressed: () => controller.pauseSession(session.id),
                      ),
                      const SizedBox(width: 8),
                      BmdButton(
                        identifier: 'session_close',
                        label: 'Close capture',
                        variant: BmdButtonVariant.outlined,
                        onPressed: () => controller.closeSession(session.id),
                      ),
                    ],
                    if (session.status == SessionStatus.paused) ...[
                      BmdButton(
                        identifier: 'session_start',
                        label: 'Resume',
                        variant: BmdButtonVariant.tonal,
                        onPressed: session.readinessOk
                            ? () => controller.startSession(session.id)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      BmdButton(
                        identifier: 'session_close',
                        label: 'Close capture',
                        variant: BmdButtonVariant.outlined,
                        onPressed: () => controller.closeSession(session.id),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(BmdRadius.card),
                bottomLeft: Radius.circular(BmdRadius.card),
              ),
              child: ColoredBox(color: accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegistrationsTab extends StatelessWidget {
  const _RegistrationsTab({required this.campaignId});
  final String campaignId;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: PermissionGate.disabled(
        Permission.campaignCreate,
        reason: 'Only a Campaign Creator can open the registration workspace.',
        label: 'Open registration workspace',
        child: BmdButton(
          label: 'Open registration workspace',
          onPressed: () => context.go('/campaigns/$campaignId/register'),
        ),
      ),
    );
  }
}

/// Campaign-detail Analytics tab (spec A-02) — the campaign-scoped mount of
/// [AnalyticsPanel]. Holds its own range preset (the panel's drill table is
/// dropped via `showDrillTable: false`; the campaign is already fixed by the
/// tab's context, so that table would only ever show one row).
class _DetailAnalyticsTab extends StatefulWidget {
  const _DetailAnalyticsTab({required this.campaignId});
  final String campaignId;

  @override
  State<_DetailAnalyticsTab> createState() => _DetailAnalyticsTabState();
}

class _DetailAnalyticsTabState extends State<_DetailAnalyticsTab> {
  DateRangePreset _range = DateRangePreset.d30;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        RangeChipRow(
          value: _range,
          onChanged: (range) => setState(() => _range = range),
        ),
        const SizedBox(height: 16),
        AnalyticsPanel(
          query: AnalyticsQuery(campaignId: widget.campaignId, range: _range),
          showDrillTable: false,
        ),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(child: Text(text));
}
