/// Server-side revalidation of a campaign draft on submit. Pure, no IO: the
/// authoring PRD requires this to run again on the server even though the
/// wizard already validated client-side, because the wizard renders errors
/// inline per field (spec D6) — a single opaque message satisfies the
/// endpoint contract but fails the screen. Every error below therefore names
/// the field it belongs to.
library;

/// One field-scoped validation failure. `field` is a dotted/indexed path
/// (e.g. `sessions[0].endAt`) the client can map straight back onto a form
/// control.
class FieldError {
  const FieldError(this.field, this.message);

  final String field;
  final String message;
}

/// One session window in a submitted draft, mirroring the client's wizard
/// step. All fields are nullable because "missing" is itself a validation
/// error this file reports, not a precondition the caller must enforce.
class SessionInput {
  const SessionInput({this.venue, this.capacity, this.startAt, this.endAt});

  final String? venue;
  final int? capacity;
  final DateTime? startAt;
  final DateTime? endAt;
}

/// The submitted draft, mirroring the client's wizard state. Plain data: no
/// behaviour, no defaults beyond what the constructor requires — the caller
/// (the submit endpoint, Task 8) is responsible for turning a stored
/// campaign row into this shape.
class CampaignDraftInput {
  const CampaignDraftInput({
    required this.name,
    required this.type,
    required this.objective,
    required this.territoryIds,
    required this.target,
    required this.budgetReference,
    required this.approverId,
    required this.ownerId,
    required this.geofenceEnabled,
    required this.sessions,
  });

  final String name;
  final String type;
  final String? objective;
  final List<String> territoryIds;
  final int target;
  final String? budgetReference;
  final String? approverId;
  final String ownerId;
  final bool geofenceEnabled;
  final List<SessionInput> sessions;
}

/// Validates [input] for the DRAFT/RETURNED → PENDING_APPROVAL submit
/// transition. Returns an empty list when the draft is complete.
///
/// Deliberately collects every error rather than stopping at the first: the
/// wizard can be many steps back from the field that's wrong, and a client
/// that fixes one error only to be told about the next on a second round
/// trip is the exact opaque-single-message failure mode D6 rules out.
List<FieldError> validateForSubmit(CampaignDraftInput input) {
  final errors = <FieldError>[];

  if (input.name.trim().isEmpty) {
    errors.add(const FieldError('name', 'Name is required.'));
  }
  if (input.type.trim().isEmpty) {
    errors.add(const FieldError('type', 'Type is required.'));
  }
  if (input.territoryIds.isEmpty) {
    errors.add(
      const FieldError('territoryIds', 'At least one territory is required.'),
    );
  }
  if (input.target <= 0) {
    errors.add(const FieldError('target', 'Target must be greater than zero.'));
  }

  // SoD is checked here as DATA only — this reports that owner == approver.
  // Whether that fact is ENFORCED (blocking the transition) is a config
  // lookup made by the caller in Task 9, not a decision made in this file.
  if (input.approverId == null || input.approverId!.trim().isEmpty) {
    errors.add(const FieldError('approverId', 'An approver is required.'));
  } else if (input.approverId == input.ownerId) {
    errors.add(
      const FieldError(
        'approverId',
        'The approver must be different from the owner.',
      ),
    );
  }

  if (input.sessions.isEmpty) {
    errors.add(
      const FieldError('sessions', 'At least one session is required.'),
    );
  } else {
    for (var i = 0; i < input.sessions.length; i++) {
      errors.addAll(_validateSession(i, input.sessions[i]));
    }
    errors.addAll(_validateOverlaps(input.sessions));
  }

  return errors;
}

List<FieldError> _validateSession(int index, SessionInput session) {
  final errors = <FieldError>[];
  final prefix = 'sessions[$index]';

  if (session.startAt == null) {
    errors.add(FieldError('$prefix.startAt', 'Start time is required.'));
  }
  if (session.endAt == null) {
    errors.add(FieldError('$prefix.endAt', 'End time is required.'));
  }
  if (session.startAt != null &&
      session.endAt != null &&
      !session.endAt!.isAfter(session.startAt!)) {
    errors.add(
      FieldError('$prefix.endAt', 'End time must be after start time.'),
    );
  }
  if (session.capacity != null && session.capacity! <= 0) {
    errors.add(
      FieldError('$prefix.capacity', 'Capacity must be greater than zero.'),
    );
  }

  return errors;
}

/// Pairwise overlap check across sessions that each have both endpoints
/// present — a session already reported as missing start/end is skipped
/// here rather than compared, since it has nothing well-formed to overlap
/// with. Overlap is strict: `endA > startB && endB > startA`. Sessions that
/// merely touch (one ends exactly when the next starts) are back-to-back
/// scheduling, not a conflict — a venue can be booked 9-12 and 12-15 without
/// contradiction.
List<FieldError> _validateOverlaps(List<SessionInput> sessions) {
  final errors = <FieldError>[];

  for (var i = 0; i < sessions.length; i++) {
    final a = sessions[i];
    if (a.startAt == null || a.endAt == null) continue;

    for (var j = i + 1; j < sessions.length; j++) {
      final b = sessions[j];
      if (b.startAt == null || b.endAt == null) continue;

      final overlaps =
          a.endAt!.isAfter(b.startAt!) && b.endAt!.isAfter(a.startAt!);
      if (overlaps) {
        errors.add(
          FieldError('sessions[$i]', 'Session $i overlaps with session $j.'),
        );
      }
    }
  }

  return errors;
}
