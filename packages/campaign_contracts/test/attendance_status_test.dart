import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('AttendanceStatus wire values are SCREAMING_SNAKE and round-trip', () {
    final wires = AttendanceStatus.values.map((s) => s.wireValue).toList();
    expect(wires.toSet().length, AttendanceStatus.values.length);
    for (final s in AttendanceStatus.values) {
      expect(s.wireValue, matches(RegExp(r'^[A-Z][A-Z_]*$')), reason: s.name);
      expect(AttendanceStatus.tryParseWire(s.wireValue), s);
    }
  });

  test('specific wire values are exactly as the server emits', () {
    expect(AttendanceStatus.crmReview.wireValue, 'CRM_REVIEW');
    expect(AttendanceStatus.returned.wireValue, 'RETURNED');
    expect(AttendanceStatus.matchProcessing.wireValue, 'MATCH_PROCESSING');
    expect(AttendanceStatus.notCaptured.wireValue, 'NOT_CAPTURED');
  });

  test('an unknown wire value is null, never a default', () {
    expect(AttendanceStatus.tryParseWire('NOT_A_STATUS'), isNull);
    expect(AttendanceStatus.tryParseWire(''), isNull);
    expect(
      AttendanceStatus.tryParseWire('crmReview'),
      isNull,
      reason: 'case matters',
    );
  });
}
