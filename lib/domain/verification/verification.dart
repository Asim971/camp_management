import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

export 'package:campaign_contracts/campaign_contracts.dart'
    show MatchBand, ReferenceSource, VerificationOutcome;

part 'verification.freezed.dart';

/// The machine result and the human decision are SEPARATE objects
/// (Guideline §1.1, §8.13). Field users never see [MachineResult]; CRM sees
/// the band + reasons, not the raw score.
@freezed
class MachineResult with _$MachineResult {
  const factory MachineResult({
    required MatchBand band, // advisory only
    required ReferenceSource referenceSource,
    @Default(false) bool padReview,
    @Default(false) bool lowQuality,
    @Default(<String>[]) List<String> reasons,
  }) = _MachineResult;
}

/// The authoritative human decision (FR-011). Reason is mandatory for
/// reject/return; overrides require explicit explanation (§2 human-in-the-loop).
@freezed
class VerificationDecision with _$VerificationDecision {
  const factory VerificationDecision({
    required String attendanceId,
    required String verifierId,
    required VerificationOutcome outcome,
    required String reason,
    DateTime? decidedAt,
    @Default(false) bool supervisorOverride,
  }) = _VerificationDecision;
}
