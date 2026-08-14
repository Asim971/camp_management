import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('MatchBand wire values are SCREAMING_SNAKE and round-trip', () {
    expect(MatchBand.noReference.wireValue, 'NO_REFERENCE');
    for (final b in MatchBand.values) {
      expect(b.wireValue, matches(RegExp(r'^[A-Z][A-Z_]*$')));
      expect(MatchBand.tryParseWire(b.wireValue), b);
    }
    expect(
      MatchBand.tryParseWire('high'),
      isNull,
      reason: 'camelCase is not the wire value',
    );
    expect(MatchBand.tryParseWire('NOPE'), isNull);
  });

  test('ReferenceSource round-trips SCREAMING_SNAKE', () {
    expect(
      ReferenceSource.verifiedProfilePhoto.wireValue,
      'VERIFIED_PROFILE_PHOTO',
    );
    for (final r in ReferenceSource.values) {
      expect(ReferenceSource.tryParseWire(r.wireValue), r);
    }
    expect(ReferenceSource.tryParseWire('unavailable'), isNull);
  });

  test('VerificationOutcome round-trips SCREAMING_SNAKE', () {
    expect(
      VerificationOutcome.returnForRecapture.wireValue,
      'RETURN_FOR_RECAPTURE',
    );
    for (final o in VerificationOutcome.values) {
      expect(VerificationOutcome.tryParseWire(o.wireValue), o);
    }
    expect(
      VerificationOutcome.tryParseWire('approved'),
      isNull,
      reason: 'camelCase name is not the wire value',
    );
  });
}
