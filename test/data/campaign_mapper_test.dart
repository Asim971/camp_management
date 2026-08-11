import 'package:acsl_campaign/data/campaign/campaign_mapper.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> wire({String status = 'DRAFT'}) => {
    'id': 'c1',
    'name': 'Q3 Drive',
    'type': 'ATTENDANCE',
    'organizationId': 'org-1',
    'status': status,
    'ownerId': 'user-1',
    'startAt': '2026-09-01T09:00:00.000Z',
    'endAt': null,
    'venue': 'Hall A',
    'objective': 'Verify',
    'territoryIds': ['terr-1'],
    'targetAudience': 100,
    'verifiedAttendance': 0,
    'version': 3,
  };

  test('maps a well-formed payload', () {
    final c = campaignFromWire(wire());
    expect(c.id, 'c1');
    expect(c.status, CampaignStatus.draft);
    expect(c.startAt, DateTime.utc(2026, 9, 1, 9));
  });

  // The defect this task exists to close. campaign_dto.dart used
  // `orElse: () => CampaignStatus.draft`, so a CANCELLED campaign arriving with
  // an unexpected status rendered as an EDITABLE DRAFT — a silent
  // misclassification in the direction that grants more permission.
  test('an unrecognised status throws instead of becoming a draft', () {
    expect(
      () => campaignFromWire(wire(status: 'SOMETHING_NEW')),
      throwsA(isA<FormatException>()),
    );
  });

  test('a missing status throws rather than defaulting', () {
    final json = wire()..remove('status');
    expect(() => campaignFromWire(json), throwsA(isA<FormatException>()));
  });

  test('decision wire values are SCREAMING_SNAKE', () {
    expect(
      draftDecisionWire(CampaignDecision.returnForCorrection),
      'RETURN_FOR_CORRECTION',
    );
  });
}
