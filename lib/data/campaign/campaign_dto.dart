import 'package:json_annotation/json_annotation.dart';

import '../../domain/campaign/campaign.dart';
import '../../domain/common/status.dart';

part 'campaign_dto.g.dart';

/// Wire model. Kept separate from the domain [Campaign] so an API shape change
/// never leaks past the data layer (Architecture §10).
@JsonSerializable()
class CampaignDto {
  CampaignDto({
    required this.id,
    required this.name,
    required this.type,
    required this.organizationId,
    required this.status,
    required this.ownerId,
    this.startAt,
    this.endAt,
    this.venue,
    this.objective,
    this.territoryIds = const [],
    this.targetAudience = 0,
    this.verifiedAttendance = 0,
  });

  factory CampaignDto.fromJson(Map<String, dynamic> json) =>
      _$CampaignDtoFromJson(json);
  Map<String, dynamic> toJson() => _$CampaignDtoToJson(this);

  final String id;
  final String name;
  final String type;
  final String organizationId;
  final String status; // wire value, e.g. "PENDING_APPROVAL"
  final String ownerId;
  final DateTime? startAt;
  final DateTime? endAt;
  final String? venue;
  final String? objective;
  final List<String> territoryIds;
  final int targetAudience;
  final int verifiedAttendance;

  Campaign toDomain() => Campaign(
    id: id,
    name: name,
    type: type,
    organizationId: organizationId,
    status: _statusFromWire(status),
    ownerId: ownerId,
    startAt: startAt,
    endAt: endAt,
    venue: venue,
    objective: objective,
    territoryIds: territoryIds,
    targetAudience: targetAudience,
    verifiedAttendance: verifiedAttendance,
  );

  static CampaignStatus _statusFromWire(String wire) =>
      CampaignStatus.values.firstWhere(
        (s) => s.wireValue == wire,
        orElse: () => CampaignStatus.draft,
      );
}
