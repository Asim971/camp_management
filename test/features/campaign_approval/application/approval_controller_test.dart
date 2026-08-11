import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/core/trace/trace_id.dart';
import 'package:acsl_campaign/domain/campaign/campaign.dart';
import 'package:acsl_campaign/domain/campaign/campaign_draft.dart';
import 'package:acsl_campaign/domain/campaign/campaign_repository.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/features/campaign_approval/application/approval_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 10 fix-round (F3): a 422 (WARNINGS_UNACKNOWLEDGED,
/// DECISION_REASON_REQUIRED) previously fell into the same generic `.error`
/// bucket as a network failure, dead-ending the screen on
/// "Couldn't record the decision. Try again." with no way to learn why.
/// These assert the CONTROLLER's rendered state — the [ApprovalResult] it
/// returns and [ApprovalController.lastFailureMessage] — distinguishes
/// `.validation` from `.conflict` and from the generic `.error`.
class _StubCampaignRepository implements CampaignRepository {
  _StubCampaignRepository(this._campaign, this._decideResult);

  final Campaign _campaign;
  final Result<Campaign> _decideResult;

  final List<int> versionsSeen = [];
  final List<List<String>> acknowledgedWarningsSeen = [];

  @override
  Future<Result<Campaign>> getById(String id) async => Ok(_campaign);

  @override
  Future<Result<Campaign>> decide(
    String id, {
    required CampaignDecision decision,
    String? reason,
    required int version,
    required List<String> acknowledgedWarnings,
    TraceId? trace,
  }) async {
    versionsSeen.add(version);
    acknowledgedWarningsSeen.add(acknowledgedWarnings);
    return _decideResult;
  }

  @override
  Future<Result<Campaign>> createDraft(CampaignDraft draft, {TraceId? trace}) =>
      throw UnimplementedError('not exercised by this test');

  @override
  Future<Result<Campaign>> updateDraft(
    String id,
    CampaignDraft draft, {
    required int version,
  }) => throw UnimplementedError('not exercised by this test');

  @override
  Future<Result<Campaign>> submitForApproval(
    String id, {
    required int version,
    TraceId? trace,
  }) => throw UnimplementedError('not exercised by this test');

  @override
  Future<Result<Paged<Campaign>>> list(CampaignQuery query) =>
      throw UnimplementedError('not exercised by this test');
}

Campaign _pendingCampaign() => const Campaign(
  id: 'c1',
  name: 'Q3 Drive',
  type: 'seminar',
  organizationId: 'org-1',
  status: CampaignStatus.pendingApproval,
  ownerId: 'someone-else',
  version: 4,
);

void main() {
  test('a validation failure returns .validation and carries the server '
      'message, not the generic error text', () async {
    final repo = _StubCampaignRepository(
      _pendingCampaign(),
      const Err(
        Failure(
          FailureKind.validation,
          message: 'A reason is required to return or reject a campaign.',
        ),
      ),
    );
    final container = ProviderContainer(
      overrides: [campaignRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await container.read(approvalControllerProvider('c1').future);
    final notifier = container.read(approvalControllerProvider('c1').notifier);

    final result = await notifier.decide(
      decision: CampaignDecision.returnForCorrection,
      acknowledgedWarnings: const [],
    );

    expect(result, ApprovalResult.validation);
    expect(
      notifier.lastFailureMessage,
      'A reason is required to return or reject a campaign.',
    );
    // The version the controller sent is the loaded campaign's — the whole
    // point of threading `version` through in the first place.
    expect(repo.versionsSeen, [4]);
  });

  test(
    'a conflict failure returns .conflict, not .validation, and reloads',
    () async {
      final repo = _StubCampaignRepository(
        _pendingCampaign(),
        const Err(Failure(FailureKind.conflict)),
      );
      final container = ProviderContainer(
        overrides: [campaignRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await container.read(approvalControllerProvider('c1').future);
      final notifier = container.read(
        approvalControllerProvider('c1').notifier,
      );

      final result = await notifier.decide(
        decision: CampaignDecision.reject,
        reason: 'Budget missing',
        acknowledgedWarnings: const [],
      );

      expect(result, ApprovalResult.conflict);
      // Distinct rendered state from validation: no failure message is
      // recorded for a conflict, since there is nothing campaign-specific
      // to explain — a reload is the whole remedy.
      expect(notifier.lastFailureMessage, isNull);
    },
  );

  test('an unrelated failure (e.g. network) returns the generic .error, '
      'distinct from both .validation and .conflict', () async {
    final repo = _StubCampaignRepository(
      _pendingCampaign(),
      const Err(Failure(FailureKind.network)),
    );
    final container = ProviderContainer(
      overrides: [campaignRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await container.read(approvalControllerProvider('c1').future);
    final notifier = container.read(approvalControllerProvider('c1').notifier);

    final result = await notifier.decide(
      decision: CampaignDecision.reject,
      reason: 'Budget missing',
      acknowledgedWarnings: const [],
    );

    expect(result, ApprovalResult.error);
    expect(notifier.lastFailureMessage, isNull);
  });
}
