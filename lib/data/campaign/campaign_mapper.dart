import 'package:campaign_contracts/campaign_contracts.dart';

import '../../domain/campaign/campaign.dart';
import '../../domain/campaign/campaign_draft.dart';
import '../../domain/campaign/campaign_repository.dart';

// Re-exported so a call site that only needs the mapper (e.g. the decision
// panel, this file's own tests) doesn't need a second import to name the
// decision it is mapping to the wire.
export '../../domain/campaign/campaign_repository.dart' show CampaignDecision;

/// Wire → domain. Throws [FormatException] on anything it cannot map.
///
/// Deliberately strict about status. The previous generated DTO used
/// `orElse: () => CampaignStatus.draft`, so an unrecognised value rendered a
/// cancelled or completed campaign as an EDITABLE DRAFT. Failing loudly turns a
/// client/server version mismatch into a visible error instead of a permission
/// escalation on the most consequential field of the record.
Campaign campaignFromWire(Map<String, Object?> json) {
  final rawStatus = json['status'];
  if (rawStatus is! String) {
    throw FormatException('Campaign is missing a status.', json.toString());
  }
  final status = CampaignStatus.tryParseWire(rawStatus);
  if (status == null) {
    throw FormatException(
      'Unrecognised campaign status "$rawStatus". This app version cannot '
      'safely display this campaign.',
      rawStatus,
    );
  }
  return Campaign(
    id: json['id']! as String,
    name: json['name']! as String,
    type: json['type']! as String,
    organizationId: json['organizationId']! as String,
    status: status,
    ownerId: json['ownerId']! as String,
    startAt: _utcOrNull(json['startAt']),
    endAt: _utcOrNull(json['endAt']),
    venue: json['venue'] as String?,
    objective: json['objective'] as String?,
    territoryIds: (json['territoryIds'] as List?)?.cast<String>() ?? const [],
    targetAudience: (json['targetAudience'] as num?)?.toInt() ?? 0,
    verifiedAttendance: (json['verifiedAttendance'] as num?)?.toInt() ?? 0,
    version: (json['version'] as num?)?.toInt() ?? 0,
  );
}

DateTime? _utcOrNull(Object? value) =>
    value is String ? DateTime.parse(value).toUtc() : null;

/// Domain → wire for the create/update payload the wizard sends. `PUT
/// /campaigns/{id}` additionally requires a `version` in the body — that is
/// added by the caller, not here, since a create (`POST /campaigns`) has no
/// prior version to send.
Map<String, Object?> draftToWire(CampaignDraft draft) => {
  'name': draft.name,
  'type': draft.type,
  'objective': draft.objective,
  'audienceTypes': draft.audienceTypes,
  'territoryIds': draft.territoryIds,
  'target': draft.target,
  'budgetReference': draft.budgetReference,
  'approverId': draft.approverId,
  'geofenceEnabled': draft.geofenceEnabled,
  'sessions': [
    for (final s in draft.sessions)
      {
        'venue': s.venue,
        'capacity': s.capacity,
        'startAt': s.startAt?.toIso8601String(),
        'endAt': s.endAt?.toIso8601String(),
      },
  ],
};

/// Domain decision → the SCREAMING_SNAKE wire value. Delegates to
/// [CampaignDecisionInput.wireValue] so that string has exactly one
/// definition on the client, in the shared contracts package, instead of a
/// second copy drifting here.
String draftDecisionWire(CampaignDecision decision) => switch (decision) {
  CampaignDecision.approve => CampaignDecisionInput.approve.wireValue,
  CampaignDecision.returnForCorrection =>
    CampaignDecisionInput.returnForCorrection.wireValue,
  CampaignDecision.reject => CampaignDecisionInput.reject.wireValue,
};
