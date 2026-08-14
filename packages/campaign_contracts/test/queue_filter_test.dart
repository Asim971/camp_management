import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('QueueFilter wire values are SCREAMING_SNAKE and round-trip', () {
    final wires = QueueFilter.values.map((f) => f.wireValue).toList();
    expect(wires.toSet().length, QueueFilter.values.length);
    for (final f in QueueFilter.values) {
      expect(f.wireValue, matches(RegExp(r'^[A-Z][A-Z_]*$')), reason: f.name);
      expect(QueueFilter.tryParseWire(f.wireValue), f);
    }
  });

  test('specific wire values', () {
    expect(QueueFilter.all.wireValue, 'ALL');
    expect(QueueFilter.mine.wireValue, 'MINE');
    expect(QueueFilter.unassigned.wireValue, 'UNASSIGNED');
    expect(QueueFilter.escalated.wireValue, 'ESCALATED');
  });

  test('an unknown wire value is null, never a default', () {
    expect(QueueFilter.tryParseWire('NOPE'), isNull);
    expect(QueueFilter.tryParseWire(''), isNull);
    expect(QueueFilter.tryParseWire('all'), isNull, reason: 'case matters');
  });
}
