import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/core/trace/trace_id.dart';
import 'package:acsl_campaign/domain/campaign/campaign.dart';
import 'package:acsl_campaign/domain/campaign/campaign_draft.dart';
import 'package:acsl_campaign/domain/campaign/campaign_repository.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/domain/verification/verification.dart';
import 'package:acsl_campaign/domain/verification/verification_case.dart';
import 'package:acsl_campaign/domain/verification/verification_repository.dart';
import 'package:acsl_campaign/features/dashboard/application/dashboard_notifier.dart';
import 'package:acsl_campaign/features/offline_queue/application/offline_queue_provider.dart';
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _overdueId = 'ATT-OVERDUE';
const _escalatedId = 'ATT-ESCALATED';
const _freshId = 'ATT-FRESH';

/// In-memory [VerificationRepository] returning a fixed queue regardless of
/// filter — the dashboard always reads [QueueFilter.all] — so the fake just
/// needs to be a faithful stand-in for the interface (mirrors
/// `_FakeVerificationRepository` in `test/widget/verification_queue_screen_test.dart`).
class _FakeVerificationRepository implements VerificationRepository {
  _FakeVerificationRepository(this._result);

  final Result<List<VerificationQueueItem>> _result;

  @override
  Future<Result<List<VerificationQueueItem>>> queue({
    required QueueFilter filter,
  }) async => _result;

  @override
  Future<Result<void>> claim(String attendanceId) =>
      throw UnimplementedError('not exercised by the dashboard');

  @override
  Future<Result<void>> release(String attendanceId) =>
      throw UnimplementedError('not exercised by the dashboard');

  @override
  Future<Result<VerificationCase>> getCase(String attendanceId) =>
      throw UnimplementedError('not exercised by the dashboard');

  @override
  Future<Result<void>> decide(
    VerificationDecision decision, {
    required int expectedVersion,
    TraceId? trace,
  }) => throw UnimplementedError('not exercised by the dashboard');
}

/// In-memory [CampaignRepository] returning a fixed page regardless of query
/// (mirrors `_StubCampaignRepository` in
/// `test/features/campaign_approval/application/approval_controller_test.dart`).
class _FakeCampaignRepository implements CampaignRepository {
  _FakeCampaignRepository(this._result);

  final Result<Paged<Campaign>> _result;

  @override
  Future<Result<Paged<Campaign>>> list(CampaignQuery query) async => _result;

  @override
  Future<Result<Campaign>> getById(String id) =>
      throw UnimplementedError('not exercised by the dashboard');

  @override
  Future<Result<Campaign>> createDraft(CampaignDraft draft, {TraceId? trace}) =>
      throw UnimplementedError('not exercised by the dashboard');

  @override
  Future<Result<Campaign>> updateDraft(
    String id,
    CampaignDraft draft, {
    required int version,
  }) => throw UnimplementedError('not exercised by the dashboard');

  @override
  Future<Result<Campaign>> submitForApproval(
    String id, {
    required int version,
    TraceId? trace,
  }) => throw UnimplementedError('not exercised by the dashboard');

  @override
  Future<Result<Campaign>> decide(
    String id, {
    required CampaignDecision decision,
    String? reason,
    required int version,
    required List<String> acknowledgedWarnings,
    TraceId? trace,
  }) => throw UnimplementedError('not exercised by the dashboard');
}

List<VerificationQueueItem> _seedQueue() => const [
  VerificationQueueItem(
    attendanceId: _overdueId,
    carpenterName: 'Karim Uddin',
    campaignName: 'Campaign A',
    age: Duration(hours: 30), // past overdueVerificationThreshold (24h)
    band: MatchBand.noReference,
    referenceSource: ReferenceSource.unavailable,
    assigneeId: null,
    escalatedAt: null,
  ),
  VerificationQueueItem(
    attendanceId: _escalatedId,
    carpenterName: 'Rina Akter',
    campaignName: 'Campaign B',
    age: Duration(hours: 2),
    band: MatchBand.medium,
    referenceSource: ReferenceSource.verifiedProfilePhoto,
    assigneeId: 'u-someone-else',
    escalatedAt: null, // set below via copyWith to keep a real DateTime
  ),
  VerificationQueueItem(
    attendanceId: _freshId,
    carpenterName: 'Nasrin Begum',
    campaignName: 'Campaign B',
    age: Duration(minutes: 10),
    band: MatchBand.high,
    referenceSource: ReferenceSource.authorizedNidPhoto,
    assigneeId: null,
    escalatedAt: null,
  ),
];

List<VerificationQueueItem> _seedQueueWithEscalation() {
  final items = _seedQueue();
  final escalated = items[1].copyWith(escalatedAt: DateTime(2026, 8, 10));
  return [items[0], escalated, items[2]];
}

List<Campaign> _seedCampaigns() => const [
  Campaign(
    id: 'c1',
    name: 'Q3 Drive',
    type: 'seminar',
    organizationId: 'org-1',
    status: CampaignStatus.active,
    ownerId: 'owner-1',
    targetAudience: 100,
    verifiedAttendance: 40,
  ),
  Campaign(
    id: 'c2',
    name: 'Q4 Drive',
    type: 'seminar',
    organizationId: 'org-1',
    status: CampaignStatus.returned,
    ownerId: 'owner-1',
    targetAudience: 50,
    verifiedAttendance: 0,
  ),
];

ProviderContainer _containerFor({
  required Result<List<VerificationQueueItem>> queueResult,
  required Result<Paged<Campaign>> campaignResult,
  int pendingSync = 0,
}) {
  final container = ProviderContainer(
    overrides: [
      verificationRepositoryProvider.overrideWithValue(
        _FakeVerificationRepository(queueResult),
      ),
      campaignRepositoryProvider.overrideWithValue(
        _FakeCampaignRepository(campaignResult),
      ),
      pendingCountProvider.overrideWithValue(pendingSync),
    ],
  );
  return container;
}

void main() {
  test('composes an exception-first DashboardView: a seeded overdue item and '
      'an escalated item each surface as their own exception, ahead of the '
      'KPIs', () async {
    final container = _containerFor(
      queueResult: Ok(_seedQueueWithEscalation()),
      campaignResult: Ok(Paged(items: _seedCampaigns(), total: 2)),
      pendingSync: 3,
    );
    addTearDown(container.dispose);

    final view = await container.read(dashboardProvider.future);

    DashboardException byKey(String key) =>
        view.exceptions.firstWhere((e) => e.key == key);

    // Exception-first: the field is declared (and populated) ahead of
    // kpis in DashboardView; the specific seeded counts land correctly.
    expect(view.exceptions, isNotEmpty);
    expect(byKey('overdue_verification').count, 1); // ATT-OVERDUE (30h)
    expect(byKey('escalated').count, 1); // the copyWith'd escalated item
    expect(byKey('no_reference').count, 1); // ATT-OVERDUE's band
    expect(byKey('pending_sync').count, 3);
    expect(byKey('rejected').count, 1); // c2 is RETURNED

    // KPIs carry the expected fields/values.
    DashboardKpi kpi(String label) =>
        view.kpis.firstWhere((k) => k.label == label);
    expect(kpi('Campaigns').value, 2);
    expect(kpi('Active campaigns').value, 1);
    expect(kpi('Verification queue').value, 3);
    expect(kpi('Pending sync').value, 3);

    expect(view.funnel.stages, isNotEmpty);
    expect(view.statusBreakdown.byStatus[CampaignStatus.active], 1);
    expect(view.statusBreakdown.byStatus[CampaignStatus.returned], 1);
  });

  test('a Failure from the verification queue source surfaces as AsyncError, '
      'not a silently empty dashboard', () async {
    final container = _containerFor(
      queueResult: const Err(Failure(FailureKind.network)),
      campaignResult: Ok(Paged(items: _seedCampaigns(), total: 2)),
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(dashboardProvider.future),
      throwsA(isA<Failure>()),
    );
    expect(container.read(dashboardProvider), isA<AsyncError<DashboardView>>());
  });

  test(
    'a Failure from the campaign list source surfaces as AsyncError',
    () async {
      final container = _containerFor(
        queueResult: Ok(_seedQueue()),
        campaignResult: const Err(Failure(FailureKind.server)),
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(dashboardProvider.future),
        throwsA(isA<Failure>()),
      );
      expect(
        container.read(dashboardProvider),
        isA<AsyncError<DashboardView>>(),
      );
    },
  );
}
