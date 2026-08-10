import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('every status has a distinct SCREAMING_SNAKE wire value', () {
    final wires = CampaignStatus.values.map((s) => s.wireValue).toList();
    expect(wires.toSet().length, CampaignStatus.values.length);
    for (final w in wires) {
      expect(w, matches(RegExp(r'^[A-Z][A-Z_]*$')), reason: w);
    }
  });

  test('wire values round-trip', () {
    for (final s in CampaignStatus.values) {
      expect(CampaignStatus.tryParseWire(s.wireValue), s);
    }
  });

  // The whole reason this enum moved into a shared package: an unrecognised
  // value must NOT become an editable draft. campaign_dto.dart used
  // `orElse: () => CampaignStatus.draft`, so a CANCELLED campaign arriving
  // with an unexpected value rendered as editable — a silent misclassification
  // in the direction that grants more permission.
  test('an unknown wire value is null, never a default', () {
    expect(CampaignStatus.tryParseWire('NOT_A_STATUS'), isNull);
    expect(CampaignStatus.tryParseWire(''), isNull);
    expect(
      CampaignStatus.tryParseWire('draft'),
      isNull,
      reason: 'case matters',
    );
  });

  test('decision inputs use SCREAMING_SNAKE, not Dart enum names', () {
    expect(
      CampaignDecisionInput.returnForCorrection.wireValue,
      'RETURN_FOR_CORRECTION',
    );
    expect(CampaignDecisionInput.tryParseWire('returnForCorrection'), isNull);
  });
}
