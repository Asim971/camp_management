import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/bmd_button.dart';
import '../../../core/design_system/status_chip.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../domain/common/status.dart';
import '../../../domain/session/campaign_session.dart';
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

    return AdaptiveScaffold(
      title: 'Campaign detail',
      selectedIndex: 1,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: BmdButton(
            label: 'Retry',
            variant: BmdButtonVariant.outlined,
            onPressed: () => ref.invalidate(campaignDetailProvider(campaignId)),
          ),
        ),
        data: (data) => DefaultTabController(
          length: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(campaignId: campaignId, data: data),
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
                    const _Placeholder('Attendance timeline — W-05 follow-up'),
                    const _Placeholder('Analytics — see A-02'),
                    const _Placeholder('Audit trail — AD-01'),
                  ],
                ),
              ),
            ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(c.name, style: Theme.of(context).textTheme.titleLarge),
          ),
          StatusChip(label: c.status.name, tone: StatusTone.info),
          const SizedBox(width: 12),
          // Contextual primary next action.
          if (c.status == CampaignStatus.pendingApproval)
            BmdButton(
              label: 'Review approval',
              onPressed: () => context.go('/campaigns/$campaignId/approve'),
            )
          else if (c.status == CampaignStatus.approved ||
              c.status == CampaignStatus.active)
            BmdButton(
              label: 'Add registrations',
              onPressed: () => context.go('/campaigns/$campaignId/register'),
            ),
        ],
      ),
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
        Text('Target: ${data.campaign.targetAudience}',
            style: Theme.of(context).textTheme.bodyLarge,),
      ],
    );
  }

  Widget _kpi(BuildContext context, String label, int value) => SizedBox(
        width: 160,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 6),
                Text('$value',
                    style: Theme.of(context).textTheme.headlineMedium,),
              ],
            ),
          ),
        ),
      );
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
        for (final s in data.sessions) _SessionCard(session: s, controller: c),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(session.venue,
                      style: Theme.of(context).textTheme.titleMedium,),
                ),
                if (!session.readinessOk)
                  const StatusChip(label: 'Readiness', tone: StatusTone.warning)
                else if (session.overCapacity)
                  const StatusChip(
                      label: 'Over capacity', tone: StatusTone.warning,)
                else
                  StatusChip(label: session.status.name, tone: StatusTone.info),
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
                    label: 'Start',
                    variant: BmdButtonVariant.tonal,
                    onPressed: session.readinessOk
                        ? () => controller.startSession(session.id)
                        : null,
                  ),
                if (session.status == SessionStatus.active) ...[
                  BmdButton(
                    label: 'Pause',
                    variant: BmdButtonVariant.outlined,
                    onPressed: () => controller.pauseSession(session.id),
                  ),
                  const SizedBox(width: 8),
                  BmdButton(
                    label: 'Close capture',
                    variant: BmdButtonVariant.outlined,
                    onPressed: () => controller.closeSession(session.id),
                  ),
                ],
                if (session.status == SessionStatus.paused)
                  BmdButton(
                    label: 'Resume',
                    variant: BmdButtonVariant.tonal,
                    onPressed: () => controller.startSession(session.id),
                  ),
              ],
            ),
          ],
        ),
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
      child: BmdButton(
        label: 'Open registration workspace',
        onPressed: () => context.go('/campaigns/$campaignId/register'),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(child: Text(text));
}
