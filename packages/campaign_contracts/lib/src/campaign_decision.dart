/// What an approver submits. Distinct from [CampaignStatus]: `APPROVE` is an
/// action, `APPROVED` is a state, and conflating them is how "reject" ended up
/// mapping to CANCELLED with no record of which action caused it.
enum CampaignDecisionInput {
  approve,
  returnForCorrection,
  reject;

  String get wireValue => switch (this) {
    approve => 'APPROVE',
    returnForCorrection => 'RETURN_FOR_CORRECTION',
    reject => 'REJECT',
  };

  static CampaignDecisionInput? tryParseWire(String wire) {
    for (final d in values) {
      if (d.wireValue == wire) return d;
    }
    return null;
  }
}
