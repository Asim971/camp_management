import 'package:campaign_contracts/campaign_contracts.dart';

/// One campaign row as read from Postgres.
///
/// Carries a few write-only fields ([budgetReference], [approverId]) that
/// Task 8's read routes never put on the wire, so Task 9's write slice does
/// not need to widen this shape just to reach a value it already needed to
/// select.
class CampaignRow {
  const CampaignRow({
    required this.id,
    required this.name,
    required this.type,
    required this.organizationId,
    required this.status,
    required this.ownerId,
    required this.targetAudience,
    required this.version,
    required this.territoryIds,
    this.objective,
    this.venue,
    this.budgetReference,
    this.approverId,
    this.startAt,
    this.endAt,
  });

  final String id;
  final String name;
  final String type;
  final String organizationId;
  final CampaignStatus status;
  final String ownerId;
  final String? objective;
  final String? venue;
  final String? budgetReference;
  final String? approverId;
  final DateTime? startAt;
  final DateTime? endAt;
  final int targetAudience;
  final int version;
  final List<String> territoryIds;

  /// The wire shape fixed by the client's `CampaignDto`
  /// (`lib/data/campaign/campaign_dto.dart`).
  ///
  /// `verifiedAttendance` is always `0` here: it is derived from attendance
  /// records that do not exist until sub-project 4, never a stored column, so
  /// there is nothing to select — this literal `0` is the whole
  /// implementation.
  Map<String, Object?> toWireJson() => {
    'id': id,
    'name': name,
    'type': type,
    'organizationId': organizationId,
    'status': status.wireValue,
    'ownerId': ownerId,
    'startAt': startAt?.toUtc().toIso8601String(),
    'endAt': endAt?.toUtc().toIso8601String(),
    'venue': venue,
    'objective': objective,
    'territoryIds': territoryIds,
    'targetAudience': targetAudience,
    'verifiedAttendance': 0,
    'version': version,
  };
}
