import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('every outcome has a distinct SCREAMING_SNAKE wire value', () {
    final wires = ImportRowOutcome.values.map((o) => o.wireValue).toList();
    expect(wires.toSet().length, ImportRowOutcome.values.length);
    for (final w in wires) {
      expect(w, matches(RegExp(r'^[A-Z][A-Z_]*$')), reason: w);
    }
  });

  test('wire values round-trip and unknown is null', () {
    for (final o in ImportRowOutcome.values) {
      expect(ImportRowOutcome.tryParseWire(o.wireValue), o);
    }
    expect(
      ImportRowOutcome.tryParseWire('NEEDS_PROFILE'),
      ImportRowOutcome.needsProfile,
    );
    expect(ImportRowOutcome.tryParseWire('needsProfile'), isNull);
    expect(ImportRowOutcome.tryParseWire('WHAT'), isNull);
  });

  test('IMPORT_FILE_INVALID is in the error vocabulary', () {
    expect(ApiErrorCode.importFileInvalid.wireValue, 'IMPORT_FILE_INVALID');
    expect(
      ApiErrorCode.tryParseWire('IMPORT_FILE_INVALID'),
      ApiErrorCode.importFileInvalid,
    );
  });
}
