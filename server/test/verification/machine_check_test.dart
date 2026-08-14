import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:campaign_service/src/verification/machine_check.dart';
import 'package:test/test.dart';

void main() {
  const check = StubMachineCheck();

  test('with a reference photo -> MEDIUM, baseline source', () {
    final r = check.check(hasReference: true);
    expect(r.band, MatchBand.medium);
    expect(r.referenceSource, ReferenceSource.approvedBaselinePhoto);
    expect(r.reasons, isNotEmpty);
  });

  test('without a reference photo -> NO_REFERENCE, unavailable', () {
    final r = check.check(hasReference: false);
    expect(r.band, MatchBand.noReference);
    expect(r.referenceSource, ReferenceSource.unavailable);
  });
}
