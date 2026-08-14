import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:campaign_service/src/campaign/session_machine.dart';
import 'package:test/test.dart';

void main() {
  group('transitions', () {
    test('start goes UPCOMING/PAUSED -> ACTIVE', () {
      expect(allowedFrom(SessionAction.start), {
        SessionStatus.upcoming,
        SessionStatus.paused,
      });
      expect(targetOf(SessionAction.start), SessionStatus.active);
    });

    test('pause goes ACTIVE -> PAUSED', () {
      expect(allowedFrom(SessionAction.pause), {SessionStatus.active});
      expect(targetOf(SessionAction.pause), SessionStatus.paused);
    });

    test('close goes ACTIVE/PAUSED -> CAPTURE_CLOSED', () {
      expect(allowedFrom(SessionAction.close), {
        SessionStatus.active,
        SessionStatus.paused,
      });
      expect(targetOf(SessionAction.close), SessionStatus.captureClosed);
    });

    test('CAPTURE_CLOSED and COMPLETED are terminal for every action', () {
      for (final action in SessionAction.values) {
        expect(
          allowedFrom(action),
          isNot(contains(SessionStatus.captureClosed)),
        );
        expect(allowedFrom(action), isNot(contains(SessionStatus.completed)));
      }
    });
  });

  group('readiness', () {
    final future = DateTime.utc(2026, 9, 1, 9);

    test('ready when campaign approved/active AND venue AND start time', () {
      for (final s in [CampaignStatus.approved, CampaignStatus.active]) {
        expect(
          isReady(campaignStatus: s, venue: 'Hall A', startAt: future),
          isTrue,
        );
      }
    });

    test('not ready without a venue', () {
      expect(
        isReady(
          campaignStatus: CampaignStatus.approved,
          venue: '',
          startAt: future,
        ),
        isFalse,
      );
      expect(
        isReady(
          campaignStatus: CampaignStatus.approved,
          venue: null,
          startAt: future,
        ),
        isFalse,
      );
    });

    test('not ready without a start time', () {
      expect(
        isReady(
          campaignStatus: CampaignStatus.approved,
          venue: 'Hall A',
          startAt: null,
        ),
        isFalse,
      );
    });

    test('not ready when the campaign is not approved/active', () {
      for (final s in [
        CampaignStatus.draft,
        CampaignStatus.pendingApproval,
        CampaignStatus.returned,
        CampaignStatus.paused,
        CampaignStatus.completed,
        CampaignStatus.cancelled,
      ]) {
        expect(
          isReady(campaignStatus: s, venue: 'Hall A', startAt: future),
          isFalse,
          reason: s.name,
        );
      }
    });
  });
}
