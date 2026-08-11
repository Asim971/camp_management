import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/core/trace/trace_id.dart';
import 'package:acsl_campaign/domain/campaign/campaign.dart';
import 'package:acsl_campaign/domain/campaign/campaign_draft.dart';
import 'package:acsl_campaign/domain/campaign/campaign_repository.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/features/campaign_wizard/application/wizard_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the `version` it is handed on every `updateDraft`/
/// `submitForApproval` call, and replies with `version + 1` — exactly the
/// server's own "every mutation bumps version" contract. Used to prove
/// [WizardController] threads `WizardState.savedVersion` from one call's
/// response into the next call's request (Task 10 fix-round F2: this was
/// previously verified only by a reviewer reading the diff).
class _RecordingCampaignRepository implements CampaignRepository {
  final List<int> updateVersionsSeen = [];
  final List<int> submitVersionsSeen = [];
  int createCalls = 0;

  Campaign _campaign({
    required int version,
    CampaignStatus status = CampaignStatus.draft,
  }) => Campaign(
    id: 'c1',
    name: 'Q3 Drive',
    type: 'seminar',
    organizationId: 'org-1',
    status: status,
    ownerId: 'user-1',
    version: version,
  );

  @override
  Future<Result<Campaign>> createDraft(
    CampaignDraft draft, {
    TraceId? trace,
  }) async {
    createCalls++;
    return Ok(_campaign(version: 1));
  }

  @override
  Future<Result<Campaign>> updateDraft(
    String id,
    CampaignDraft draft, {
    required int version,
  }) async {
    updateVersionsSeen.add(version);
    return Ok(_campaign(version: version + 1));
  }

  @override
  Future<Result<Campaign>> submitForApproval(
    String id, {
    required int version,
    TraceId? trace,
  }) async {
    submitVersionsSeen.add(version);
    return Ok(
      _campaign(version: version + 1, status: CampaignStatus.pendingApproval),
    );
  }

  @override
  Future<Result<Campaign>> getById(String id) =>
      throw UnimplementedError('not exercised by this test');

  @override
  Future<Result<Campaign>> decide(
    String id, {
    required CampaignDecision decision,
    String? reason,
    required int version,
    required List<String> acknowledgedWarnings,
    TraceId? trace,
  }) => throw UnimplementedError('not exercised by this test');

  @override
  Future<Result<Paged<Campaign>>> list(CampaignQuery query) =>
      throw UnimplementedError('not exercised by this test');
}

CampaignDraft _validDraft() => CampaignDraft(
  name: 'Q3 Drive',
  type: 'seminar',
  audienceTypes: const ['carpenter'],
  territoryIds: const ['terr-1'],
  target: 50,
  approverId: 'approver-1',
  sessions: [
    CampaignSessionDraft(
      id: 's1',
      venue: 'Hall A',
      capacity: 40,
      startAt: DateTime.utc(2026, 9, 1, 9),
      endAt: DateTime.utc(2026, 9, 1, 13),
    ),
  ],
);

void main() {
  test(
    'saveDraft -> saveDraft -> submit threads savedVersion 1 -> 2 -> 3, and '
    'each call sends back the version the PREVIOUS response returned',
    () async {
      final repo = _RecordingCampaignRepository();
      final container = ProviderContainer(
        overrides: [campaignRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(wizardControllerProvider.notifier);

      // A fresh draft: no savedId yet, so this is a create -> version 1.
      await notifier.saveDraft();
      var state = container.read(wizardControllerProvider);
      expect(state.savedId, 'c1');
      expect(state.savedVersion, 1);
      expect(repo.createCalls, 1);
      expect(repo.updateVersionsSeen, isEmpty);

      // Saving again now has a savedId, so this is an update. It must send
      // the version the CREATE response returned (1), and the response's
      // version + 1 (2) becomes the new savedVersion.
      await notifier.saveDraft();
      state = container.read(wizardControllerProvider);
      expect(state.savedVersion, 2);
      expect(repo.updateVersionsSeen, [1]);

      // Fill in a valid draft (name/type/audience/territory/sessions/target/
      // approver — everything wizard_controller.submit() requires before it
      // will call the repository at all) then submit.
      notifier.edit((_) => _validDraft());
      await notifier.submit();

      // submit() re-saves first (update at the CURRENT savedVersion, 2) and
      // THEN calls submitForApproval with the version THAT update returned
      // (3) — never the stale value from two calls ago.
      expect(repo.updateVersionsSeen, [1, 2]);
      expect(repo.submitVersionsSeen, [3]);
      state = container.read(wizardControllerProvider);
      expect(state.submittedId, 'c1');
      expect(state.error, isNull);
    },
  );

  test('submit() on a never-saved draft creates first, then submits at the '
      "create response's version (1) — not version 0", () async {
    final repo = _RecordingCampaignRepository();
    final container = ProviderContainer(
      overrides: [campaignRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(wizardControllerProvider.notifier);
    notifier.edit((_) => _validDraft());

    await notifier.submit();

    expect(repo.createCalls, 1);
    expect(repo.updateVersionsSeen, isEmpty);
    expect(repo.submitVersionsSeen, [1]);
  });
}
