import 'package:campaign_contracts/campaign_contracts.dart';

/// The three operations the client drives. `start` doubles as "resume" (from
/// PAUSED); there is no distinct resume verb.
enum SessionAction { start, pause, close }

/// The states from which [action] is legal. CAPTURE_CLOSED and COMPLETED are
/// terminal: no action leaves them (COMPLETED is only ever reached by the
/// campaign-completion cascade, sub-project 3a.D3).
Set<SessionStatus> allowedFrom(SessionAction action) => switch (action) {
  SessionAction.start => {SessionStatus.upcoming, SessionStatus.paused},
  SessionAction.pause => {SessionStatus.active},
  SessionAction.close => {SessionStatus.active, SessionStatus.paused},
};

/// The state [action] moves a session to.
SessionStatus targetOf(SessionAction action) => switch (action) {
  SessionAction.start => SessionStatus.active,
  SessionAction.pause => SessionStatus.paused,
  SessionAction.close => SessionStatus.captureClosed,
};

/// Whether a session may be started right now (3a.D4). True iff the campaign is
/// APPROVED or ACTIVE, the session has a non-empty venue, and it has a start
/// time. The `start` endpoint re-checks this server-side rather than trusting
/// the client's `readinessOk`.
bool isReady({
  required CampaignStatus campaignStatus,
  required String? venue,
  required DateTime? startAt,
}) {
  final campaignOk =
      campaignStatus == CampaignStatus.approved ||
      campaignStatus == CampaignStatus.active;
  final venueOk = venue != null && venue.trim().isNotEmpty;
  return campaignOk && venueOk && startAt != null;
}
