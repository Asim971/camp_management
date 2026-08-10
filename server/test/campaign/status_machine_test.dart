import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:campaign_service/src/campaign/status_machine.dart';
import 'package:test/test.dart';

void main() {
  group('submit', () {
    // The authoring PRD: "transition only from Draft/Returned to Pending
    // approval". The mock's setStatus was unconditional, so a DRAFT could be
    // approved without ever being submitted.
    test('is legal only from DRAFT and RETURNED', () {
      expect(
        nextStatusForSubmit(CampaignStatus.draft),
        CampaignStatus.pendingApproval,
      );
      expect(
        nextStatusForSubmit(CampaignStatus.returned),
        CampaignStatus.pendingApproval,
      );

      for (final s in CampaignStatus.values.where(
        (s) => s != CampaignStatus.draft && s != CampaignStatus.returned,
      )) {
        expect(nextStatusForSubmit(s), isNull, reason: 'submit from ${s.name}');
      }
    });
  });

  group('decision', () {
    test('is legal only from PENDING_APPROVAL', () {
      for (final d in CampaignDecisionInput.values) {
        for (final s in CampaignStatus.values.where(
          (s) => s != CampaignStatus.pendingApproval,
        )) {
          expect(
            nextStatusForDecision(s, d),
            isNull,
            reason: '${d.name} from ${s.name}',
          );
        }
      }
    });

    test('maps each decision to its state', () {
      const pending = CampaignStatus.pendingApproval;
      expect(
        nextStatusForDecision(pending, CampaignDecisionInput.approve),
        CampaignStatus.approved,
      );
      expect(
        nextStatusForDecision(
          pending,
          CampaignDecisionInput.returnForCorrection,
        ),
        CampaignStatus.returned,
      );
      expect(
        nextStatusForDecision(pending, CampaignDecisionInput.reject),
        CampaignStatus.cancelled,
      );
    });

    test('CANCELLED is terminal from every action', () {
      for (final d in CampaignDecisionInput.values) {
        expect(nextStatusForDecision(CampaignStatus.cancelled, d), isNull);
      }
      expect(nextStatusForSubmit(CampaignStatus.cancelled), isNull);
    });

    // A returned campaign must remain correctable and resubmittable — the PRD
    // requires return "without deleting draft data".
    test('RETURNED can be resubmitted, closing the correction loop', () {
      final resubmitted = nextStatusForSubmit(CampaignStatus.returned);
      expect(resubmitted, CampaignStatus.pendingApproval);
      expect(
        nextStatusForDecision(resubmitted!, CampaignDecisionInput.approve),
        CampaignStatus.approved,
      );
    });
  });
}
