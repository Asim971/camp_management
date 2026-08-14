import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/campaign/campaign.dart';
import '../../../domain/common/status.dart';
import '../../../domain/verification/verification_case.dart';
import '../../campaign_list/application/campaign_list_notifier.dart';
import '../../offline_queue/application/offline_queue_provider.dart';
import '../../verification_queue/application/verification_queue_notifier.dart';

/// How old a queue item ([VerificationQueueItem.age]) must be before it counts
/// as the `overdue_verification` exception. There is no server-defined SLA
/// surfaced to the client yet, so a 24-hour threshold is used as the best
/// available proxy (documented as best-effort in the task report).
const overdueVerificationThreshold = Duration(hours: 24);

/// One row in the dashboard's exception-first summary (W-01). Exceptions are
/// always shown — including a zero count — so the operator sees the full,
/// stable taxonomy every time rather than a list that reshuffles as counts
/// change (Guideline §8.2: exception-first, never alphabetical/incidental).
class DashboardException {
  const DashboardException({
    required this.key,
    required this.label,
    required this.count,
    required this.tone,
  });

  /// Stable identifier (e.g. for widget keys / analytics), not shown to users.
  final String key;
  final String label;
  final int count;
  final StatusTone tone;
}

/// A single at-a-glance metric below the exceptions.
class DashboardKpi {
  const DashboardKpi({required this.label, required this.value});

  final String label;
  final int value;
}

/// A best-effort attendance funnel composed from data already available to
/// this slice (campaign target/verified counts + queue size). A real
/// registered → checked-in → verified funnel needs session/registration/
/// attendance reads that are out of scope here (spec RD.D5 — this slice is a
/// client-side composition of existing reads, not a new endpoint); see the
/// task report for the exact gap.
class AttendanceFunnel {
  const AttendanceFunnel({required this.stages});

  final List<(String, int)> stages;
}

/// Campaign counts grouped by [CampaignStatus], for the status chart.
class CampaignStatusBreakdown {
  const CampaignStatusBreakdown({required this.byStatus});

  final Map<CampaignStatus, int> byStatus;
}

/// The composed view-model for the Dashboard (W-01). [exceptions] is declared
/// — and populated — ahead of [kpis] on every read path: it is the thing an
/// operator should see first (Guideline §8.2 exception-first).
class DashboardView {
  const DashboardView({
    required this.exceptions,
    required this.kpis,
    required this.funnel,
    required this.statusBreakdown,
  });

  final List<DashboardException> exceptions;
  final List<DashboardKpi> kpis;
  final AttendanceFunnel funnel;
  final CampaignStatusBreakdown statusBreakdown;
}

/// Composes the Dashboard purely from existing reads — the verification
/// queue, the campaign list, and the offline-sync pending count — with NO new
/// network call (spec RD.D5). Modeled on
/// `verification_queue_notifier.dart`/`campaign_list_notifier.dart`: each
/// source already throws its [Failure] on `Err` inside its own `build`/fetch,
/// so watching `.future` here rethrows automatically and surfaces as
/// `AsyncError` — no separate Result-folding needed at this layer.
class DashboardNotifier extends AutoDisposeAsyncNotifier<DashboardView> {
  @override
  Future<DashboardView> build() async {
    final queue = await ref.watch(
      verificationQueueProvider(QueueFilter.all).future,
    );
    final campaigns = await ref.watch(campaignListProvider.future);
    final pendingSync = ref.watch(pendingCountProvider);

    return _compose(
      queue: queue,
      campaigns: campaigns.items,
      pendingSync: pendingSync,
    );
  }

  DashboardView _compose({
    required List<VerificationQueueItem> queue,
    required List<Campaign> campaigns,
    required int pendingSync,
  }) {
    final overdue = queue
        .where((item) => item.age > overdueVerificationThreshold)
        .length;
    final escalated = queue.where((item) => item.escalatedAt != null).length;
    final noReference = queue
        .where((item) => item.band == MatchBand.noReference)
        .length;
    // RETURNED is the closest client-visible proxy for "rejected" — the
    // queue/campaign reads composed here carry no separate rejected-count
    // read (best-effort derivation; see task report).
    final rejected = campaigns
        .where((c) => c.status == CampaignStatus.returned)
        .length;

    final exceptions = [
      DashboardException(
        key: 'overdue_verification',
        label: 'Overdue verification',
        count: overdue,
        tone: overdue > 0 ? StatusTone.error : StatusTone.neutral,
      ),
      DashboardException(
        key: 'escalated',
        label: 'Escalated',
        count: escalated,
        tone: escalated > 0 ? StatusTone.warning : StatusTone.neutral,
      ),
      DashboardException(
        key: 'no_reference',
        label: 'No reference photo',
        count: noReference,
        tone: noReference > 0 ? StatusTone.warning : StatusTone.neutral,
      ),
      DashboardException(
        key: 'pending_sync',
        label: 'Pending sync',
        count: pendingSync,
        tone: pendingSync > 0 ? StatusTone.info : StatusTone.neutral,
      ),
      DashboardException(
        key: 'rejected',
        label: 'Returned / rejected',
        count: rejected,
        tone: rejected > 0 ? StatusTone.warning : StatusTone.neutral,
      ),
      // Neither a per-item integrity-flag read (IntegrityFlag.suspectedSpoof)
      // nor a reconciliation feed is surfaced to this slice's source
      // providers — kept in the taxonomy at 0 rather than fabricating a new
      // server call (spec RD.D5 scopes this to existing reads only).
      const DashboardException(
        key: 'suspected_spoof',
        label: 'Suspected spoof',
        count: 0,
        tone: StatusTone.neutral,
      ),
      const DashboardException(
        key: 'reconciliation',
        label: 'Reconciliation',
        count: 0,
        tone: StatusTone.neutral,
      ),
    ];

    final kpis = [
      DashboardKpi(label: 'Campaigns', value: campaigns.length),
      DashboardKpi(
        label: 'Active campaigns',
        value: campaigns.where((c) => c.status == CampaignStatus.active).length,
      ),
      DashboardKpi(label: 'Verification queue', value: queue.length),
      DashboardKpi(label: 'Pending sync', value: pendingSync),
    ];

    final targetAudience = campaigns.fold<int>(
      0,
      (sum, c) => sum + c.targetAudience,
    );
    final verifiedAttendance = campaigns.fold<int>(
      0,
      (sum, c) => sum + c.verifiedAttendance,
    );
    final funnel = AttendanceFunnel(
      stages: [
        ('Target audience', targetAudience),
        ('Verified attendance', verifiedAttendance),
        ('Pending verification', queue.length),
        ('Escalated', escalated),
      ],
    );

    final byStatus = <CampaignStatus, int>{
      for (final status in CampaignStatus.values)
        status: campaigns.where((c) => c.status == status).length,
    };

    return DashboardView(
      exceptions: exceptions,
      kpis: kpis,
      funnel: funnel,
      statusBreakdown: CampaignStatusBreakdown(byStatus: byStatus),
    );
  }
}

final dashboardProvider =
    AutoDisposeAsyncNotifierProvider<DashboardNotifier, DashboardView>(
      DashboardNotifier.new,
    );
