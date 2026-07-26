import '../../core/result/result.dart';
import 'campaign_session.dart';

/// Session operations for a campaign (W-05). State transitions are enforced
/// server-side; the client mirrors allowed actions per session status.
abstract interface class SessionRepository {
  Future<Result<List<CampaignSession>>> listForCampaign(String campaignId);
  Future<Result<CampaignSession>> start(String sessionId);
  Future<Result<CampaignSession>> close(String sessionId);
  Future<Result<CampaignSession>> pause(String sessionId);
}
