import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test(
    'every registration status has a distinct SCREAMING_SNAKE wire value',
    () {
      final wires = RegistrationStatus.values.map((s) => s.wireValue).toList();
      expect(wires.toSet().length, RegistrationStatus.values.length);
      for (final w in wires) {
        expect(w, matches(RegExp(r'^[A-Z][A-Z_]*$')), reason: w);
      }
    },
  );

  test('wire values round-trip', () {
    for (final s in RegistrationStatus.values) {
      expect(RegistrationStatus.tryParseWire(s.wireValue), s);
    }
  });

  test('an unknown wire value is null, never a default', () {
    expect(RegistrationStatus.tryParseWire('NOT_A_STATUS'), isNull);
    expect(RegistrationStatus.tryParseWire(''), isNull);
    expect(
      RegistrationStatus.tryParseWire('registered'),
      isNull,
      reason: 'case matters',
    );
  });

  test('the exact vocabulary the server emits', () {
    expect(
      RegistrationStatus.pendingProfileSync.wireValue,
      'PENDING_PROFILE_SYNC',
    );
    expect(RegistrationStatus.registered.wireValue, 'REGISTERED');
  });

  test('UNKNOWN_CARPENTER is in the error vocabulary', () {
    expect(ApiErrorCode.unknownCarpenter.wireValue, 'UNKNOWN_CARPENTER');
    expect(
      ApiErrorCode.tryParseWire('UNKNOWN_CARPENTER'),
      ApiErrorCode.unknownCarpenter,
    );
  });
}
