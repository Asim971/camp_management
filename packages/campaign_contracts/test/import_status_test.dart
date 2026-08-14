import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('every import status has a distinct SCREAMING_SNAKE wire value', () {
    final wires = ImportStatus.values.map((s) => s.wireValue).toList();
    expect(wires.toSet().length, ImportStatus.values.length);
    for (final w in wires) {
      expect(w, matches(RegExp(r'^[A-Z][A-Z_]*$')), reason: w);
    }
  });

  test('wire values round-trip', () {
    for (final s in ImportStatus.values) {
      expect(ImportStatus.tryParseWire(s.wireValue), s);
    }
  });

  test('an unknown wire value is null, never a default', () {
    expect(ImportStatus.tryParseWire('NOPE'), isNull);
    expect(ImportStatus.tryParseWire(''), isNull);
    expect(
      ImportStatus.tryParseWire('processing'),
      isNull,
      reason: 'case matters',
    );
  });

  test('the exact vocabulary the server emits', () {
    expect(ImportStatus.readyToCommit.wireValue, 'READY_TO_COMMIT');
    expect(ImportStatus.partiallyCompleted.wireValue, 'PARTIALLY_COMPLETED');
    expect(ImportStatus.processing.wireValue, 'PROCESSING');
  });
}
