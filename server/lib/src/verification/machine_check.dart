import 'package:campaign_contracts/campaign_contracts.dart';

/// The machine verdict a captured attendance carries into CRM review — advisory
/// only. Real 1:1 face-match / PAD is ML that swaps in behind [MachineCheck]
/// later (sub-project 5a.D2); this slice ships a deterministic stub.
class MachineResultData {
  const MachineResultData({
    required this.band,
    required this.referenceSource,
    required this.reasons,
  });
  final MatchBand band;
  final ReferenceSource referenceSource;
  final List<String> reasons;
}

abstract interface class MachineCheck {
  MachineResultData check({required bool hasReference});
}

/// Deterministic stub: routes everything to human review. A carpenter with a
/// reference photo gets MEDIUM (inconclusive → review); none gets NO_REFERENCE.
/// Nothing auto-approves in 5a.
class StubMachineCheck implements MachineCheck {
  const StubMachineCheck();

  @override
  MachineResultData check({required bool hasReference}) => hasReference
      ? const MachineResultData(
          band: MatchBand.medium,
          referenceSource: ReferenceSource.approvedBaselinePhoto,
          reasons: ['Face comparison inconclusive — manual review required.'],
        )
      : const MachineResultData(
          band: MatchBand.noReference,
          referenceSource: ReferenceSource.unavailable,
          reasons: ['No reference photo on file for this carpenter.'],
        );
}
