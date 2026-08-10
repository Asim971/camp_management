import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('every error has a distinct SCREAMING_SNAKE wire value', () {
    final wires = ApiErrorCode.values.map((c) => c.wireValue).toList();
    expect(wires.toSet().length, ApiErrorCode.values.length);
    for (final w in wires) {
      expect(w, matches(RegExp(r'^[A-Z][A-Z_]*$')), reason: w);
    }
  });

  test('wire values round-trip', () {
    for (final c in ApiErrorCode.values) {
      expect(ApiErrorCode.tryParseWire(c.wireValue), c);
    }
  });

  test('an unknown wire value is null, never a default', () {
    expect(ApiErrorCode.tryParseWire('NOT_A_CODE'), isNull);
    expect(ApiErrorCode.tryParseWire(''), isNull);
    expect(
      ApiErrorCode.tryParseWire('internal'),
      isNull,
      reason: 'case matters',
    );
  });

  // The IETF Idempotency-Key draft's in-flight signal: a second request for
  // a key whose first attempt hasn't finished yet. Named explicitly here so
  // a future rename/removal of the value is caught by a failing assertion
  // rather than silently changing the wire contract.
  test('idempotencyKeyInFlight is IDEMPOTENCY_KEY_IN_FLIGHT', () {
    expect(
      ApiErrorCode.idempotencyKeyInFlight.wireValue,
      'IDEMPOTENCY_KEY_IN_FLIGHT',
    );
  });
}
