import 'package:campaign_service/src/campaign/validation.dart';
import 'package:test/test.dart';

void main() {
  CampaignDraftInput valid({List<SessionInput>? sessions}) =>
      CampaignDraftInput(
        name: 'Q3 Carpenter Drive',
        type: 'ATTENDANCE',
        objective: 'Verify attendance',
        territoryIds: const ['terr-1'],
        target: 100,
        budgetReference: 'BUD-1',
        approverId: 'user-2',
        ownerId: 'user-1',
        geofenceEnabled: true,
        sessions:
            sessions ??
            [
              SessionInput(
                venue: 'Hall A',
                capacity: 50,
                startAt: DateTime.utc(2026, 9, 1, 9),
                endAt: DateTime.utc(2026, 9, 1, 12),
              ),
            ],
      );

  test('a complete draft has no errors', () {
    expect(validateForSubmit(valid()), isEmpty);
  });

  test('errors are keyed by field so the wizard can render them inline', () {
    final errors = validateForSubmit(
      CampaignDraftInput(
        name: '',
        type: '',
        objective: null,
        territoryIds: const [],
        target: 0,
        budgetReference: null,
        approverId: null,
        ownerId: 'user-1',
        geofenceEnabled: false,
        sessions: const [],
      ),
    );

    final fields = errors.map((e) => e.field).toSet();
    expect(
      fields,
      containsAll(<String>[
        'name',
        'type',
        'territoryIds',
        'approverId',
        'sessions',
      ]),
    );
    // Every error must name a field: a single opaque message satisfies the
    // endpoint and fails the screen.
    expect(errors.every((e) => e.field.isNotEmpty), isTrue);
    expect(errors.every((e) => e.message.isNotEmpty), isTrue);
  });

  // Explicitly required by the PRD, and the acceptance criterion names the
  // affected windows.
  test('overlapping sessions are rejected and identify both windows', () {
    final errors = validateForSubmit(
      valid(
        sessions: [
          SessionInput(
            venue: 'Hall A',
            capacity: 10,
            startAt: DateTime.utc(2026, 9, 1, 9),
            endAt: DateTime.utc(2026, 9, 1, 12),
          ),
          SessionInput(
            venue: 'Hall A',
            capacity: 10,
            startAt: DateTime.utc(2026, 9, 1, 11),
            endAt: DateTime.utc(2026, 9, 1, 14),
          ),
        ],
      ),
    );

    final overlap = errors.where((e) => e.field.startsWith('sessions'));
    expect(overlap, isNotEmpty);
    expect(overlap.first.message, contains('overlap'));
  });

  test('adjacent sessions that merely touch do not overlap', () {
    expect(
      validateForSubmit(
        valid(
          sessions: [
            SessionInput(
              venue: 'Hall A',
              capacity: 10,
              startAt: DateTime.utc(2026, 9, 1, 9),
              endAt: DateTime.utc(2026, 9, 1, 12),
            ),
            SessionInput(
              venue: 'Hall A',
              capacity: 10,
              startAt: DateTime.utc(2026, 9, 1, 12),
              endAt: DateTime.utc(2026, 9, 1, 15),
            ),
          ],
        ),
      ),
      isEmpty,
      reason: 'end == start is back-to-back scheduling, not a conflict',
    );
  });

  test('a session ending before it starts is rejected', () {
    final errors = validateForSubmit(
      valid(
        sessions: [
          SessionInput(
            venue: 'Hall A',
            capacity: 10,
            startAt: DateTime.utc(2026, 9, 1, 12),
            endAt: DateTime.utc(2026, 9, 1, 9),
          ),
        ],
      ),
    );
    expect(errors.map((e) => e.field), contains('sessions[0].endAt'));
  });

  test('capacity must be positive when present', () {
    final errors = validateForSubmit(
      valid(
        sessions: [
          SessionInput(
            venue: 'Hall A',
            capacity: 0,
            startAt: DateTime.utc(2026, 9, 1, 9),
            endAt: DateTime.utc(2026, 9, 1, 12),
          ),
        ],
      ),
    );
    expect(errors.map((e) => e.field), contains('sessions[0].capacity'));
  });

  // SoD is checked here as data, not policy: whether it is ENFORCED is a config
  // lookup in Task 9. This only reports that owner == approver.
  test('an approver equal to the owner is reported', () {
    final errors = validateForSubmit(
      CampaignDraftInput(
        name: 'X',
        type: 'ATTENDANCE',
        objective: 'o',
        territoryIds: const ['terr-1'],
        target: 1,
        budgetReference: 'B',
        approverId: 'user-1',
        ownerId: 'user-1',
        geofenceEnabled: false,
        sessions: [
          SessionInput(
            venue: 'Hall',
            capacity: 1,
            startAt: DateTime.utc(2026, 9, 1, 9),
            endAt: DateTime.utc(2026, 9, 1, 10),
          ),
        ],
      ),
    );
    expect(errors.map((e) => e.field), contains('approverId'));
  });
}
