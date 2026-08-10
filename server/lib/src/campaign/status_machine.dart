import 'package:campaign_contracts/campaign_contracts.dart';

/// The campaign lifecycle. The server is the only authority for it: the mock
/// set status unconditionally, which allowed approving a campaign that was
/// never submitted.
///
/// ACTIVE, PAUSED and COMPLETED are reachable in the lifecycle but are driven
/// by session operations (sub-project 3), not by the endpoints in this slice.
CampaignStatus? nextStatusForSubmit(CampaignStatus current) =>
    switch (current) {
      CampaignStatus.draft ||
      CampaignStatus.returned => CampaignStatus.pendingApproval,
      _ => null,
    };

CampaignStatus? nextStatusForDecision(
  CampaignStatus current,
  CampaignDecisionInput decision,
) {
  if (current != CampaignStatus.pendingApproval) return null;
  return switch (decision) {
    CampaignDecisionInput.approve => CampaignStatus.approved,
    CampaignDecisionInput.returnForCorrection => CampaignStatus.returned,
    CampaignDecisionInput.reject => CampaignStatus.cancelled,
  };
}
