import 'package:acsl_campaign/domain/campaign/campaign.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:flutter_test/flutter_test.dart';

/// Domain tests are pure Dart (no Flutter/IO) and run fastest — the highest-
/// value layer per the testing strategy (Architecture §14). This exemplar
/// pins the campaign lifecycle state machine (§9.1).
void main() {
  Campaign campaignWith(CampaignStatus status) => Campaign(
        id: 'c1',
        name: 'Pilot',
        type: 'seminar',
        organizationId: 'org1',
        status: status,
        ownerId: 'u1',
      );

  group('Campaign.canTransitionTo', () {
    test('draft can only be submitted for approval', () {
      final c = campaignWith(CampaignStatus.draft);
      expect(c.canTransitionTo(CampaignStatus.pendingApproval), isTrue);
      expect(c.canTransitionTo(CampaignStatus.active), isFalse);
    });

    test('pending approval can be approved, returned or cancelled', () {
      final c = campaignWith(CampaignStatus.pendingApproval);
      expect(c.canTransitionTo(CampaignStatus.approved), isTrue);
      expect(c.canTransitionTo(CampaignStatus.returned), isTrue);
      expect(c.canTransitionTo(CampaignStatus.cancelled), isTrue);
      expect(c.canTransitionTo(CampaignStatus.completed), isFalse);
    });

    test('terminal states cannot transition', () {
      expect(
        campaignWith(CampaignStatus.completed)
            .canTransitionTo(CampaignStatus.active),
        isFalse,
      );
      expect(
        campaignWith(CampaignStatus.cancelled)
            .canTransitionTo(CampaignStatus.draft),
        isFalse,
      );
    });
  });
}
