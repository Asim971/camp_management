import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('every status has a distinct SCREAMING_SNAKE wire value', () {
    final wires = SessionStatus.values.map((s) => s.wireValue).toList();
    expect(wires.toSet().length, SessionStatus.values.length);
    for (final w in wires) {
      expect(w, matches(RegExp(r'^[A-Z][A-Z_]*$')), reason: w);
    }
  });

  test('wire values round-trip', () {
    for (final s in SessionStatus.values) {
      expect(SessionStatus.tryParseWire(s.wireValue), s);
    }
  });

  test('the specific wire spellings the contract fixes', () {
    expect(SessionStatus.captureClosed.wireValue, 'CAPTURE_CLOSED');
    expect(SessionStatus.upcoming.wireValue, 'UPCOMING');
  });

  // The whole reason this enum moved: the client used
  // `firstWhere(orElse: () => upcoming)` on the camelCase Dart name, so an
  // unknown status silently became a startable session. Parsing must be null
  // on anything unrecognised, and case-sensitive.
  test('an unknown wire value is null, never a default', () {
    expect(SessionStatus.tryParseWire('NOT_A_STATUS'), isNull);
    expect(SessionStatus.tryParseWire(''), isNull);
    expect(
      SessionStatus.tryParseWire('active'),
      isNull,
      reason: 'case matters',
    );
    expect(
      SessionStatus.tryParseWire('captureClosed'),
      isNull,
      reason: 'the old camelCase name is not the wire value',
    );
  });
}
