import 'package:freezed_annotation/freezed_annotation.dart';

part 'campaign_draft.freezed.dart';

/// The in-progress campaign captured by the 5-step wizard (W-03, FR-001/002).
/// Kept separate from the persisted [Campaign] so the form can hold partial,
/// not-yet-valid data while still saving as a draft.
@freezed
class CampaignDraft with _$CampaignDraft {
  const factory CampaignDraft({
    @Default('') String name,
    @Default('') String type,
    @Default('') String objective,
    @Default(<String>[]) List<String> audienceTypes,
    @Default(<String>[]) List<String> territoryIds,
    @Default(<CampaignSessionDraft>[]) List<CampaignSessionDraft> sessions,
    @Default(0) int target,
    @Default(false) bool geofenceEnabled,
    String? budgetReference,
    String? approverId,
  }) = _CampaignDraft;

  const CampaignDraft._();

  /// Per-step validation (step index 0–4). Empty list == step is valid.
  /// The wizard shows these inline and blocks submit until all steps pass
  /// (§8.3 "prevent incomplete schedule, audience, target, budget config").
  List<String> validate(int step) => switch (step) {
    0 => [
      if (name.trim().isEmpty) 'Campaign name is required',
      if (type.trim().isEmpty) 'Select a campaign type',
    ],
    1 => [
      if (audienceTypes.isEmpty) 'Select at least one audience type',
      if (territoryIds.isEmpty) 'Select at least one territory',
    ],
    2 => [
      if (sessions.isEmpty) 'Add at least one session',
      for (final s in sessions)
        if (!s.isValid) 'Every session needs a venue and start/end time',
      if (_hasSessionConflict) 'Session time windows overlap',
    ],
    3 => [
      if (target <= 0) 'Set a positive target',
      if (approverId == null) 'Select an approver',
    ],
    _ => const [],
  };

  bool get isValid =>
      List.generate(4, validate).every((errors) => errors.isEmpty);

  bool get _hasSessionConflict {
    final windows = sessions
        .where((s) => s.startAt != null && s.endAt != null)
        .toList();
    for (var i = 0; i < windows.length; i++) {
      for (var j = i + 1; j < windows.length; j++) {
        final a = windows[i], b = windows[j];
        if (a.startAt!.isBefore(b.endAt!) && b.startAt!.isBefore(a.endAt!)) {
          return true;
        }
      }
    }
    return false;
  }
}

@freezed
class CampaignSessionDraft with _$CampaignSessionDraft {
  const factory CampaignSessionDraft({
    required String id,
    DateTime? startAt,
    DateTime? endAt,
    @Default('') String venue,
    @Default(0) int capacity,
  }) = _CampaignSessionDraft;

  const CampaignSessionDraft._();

  bool get isValid =>
      venue.trim().isNotEmpty &&
      startAt != null &&
      endAt != null &&
      endAt!.isAfter(startAt!);
}
