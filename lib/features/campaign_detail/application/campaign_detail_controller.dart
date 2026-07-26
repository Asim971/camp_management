import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../domain/campaign/campaign.dart';
import '../../../domain/session/campaign_session.dart';

/// Campaign + its sessions, loaded together for the detail view (W-05).
class CampaignDetailData {
  const CampaignDetailData({required this.campaign, required this.sessions});
  final Campaign campaign;
  final List<CampaignSession> sessions;

  int get registered => sessions.fold(0, (s, x) => s + x.registeredCount);
  int get pendingSync => sessions.fold(0, (s, x) => s + x.pendingSyncCount);
  int get inReview => sessions.fold(0, (s, x) => s + x.reviewCount);
  int get approved => sessions.fold(0, (s, x) => s + x.approvedCount);
}

class CampaignDetailController
    extends AutoDisposeFamilyAsyncNotifier<CampaignDetailData, String> {
  @override
  Future<CampaignDetailData> build(String campaignId) async {
    final campaignRes =
        await ref.read(campaignRepositoryProvider).getById(campaignId);
    final campaign = campaignRes.fold((c) => c, (f) => throw f);

    final sessionsRes =
        await ref.read(sessionRepositoryProvider).listForCampaign(campaignId);
    final sessions = sessionsRes.fold((s) => s, (_) => <CampaignSession>[]);

    return CampaignDetailData(campaign: campaign, sessions: sessions);
  }

  Future<void> startSession(String id) async {
    await ref.read(sessionRepositoryProvider).start(id);
    ref.invalidateSelf(); // reload counts + statuses
  }

  Future<void> closeSession(String id) async {
    await ref.read(sessionRepositoryProvider).close(id);
    ref.invalidateSelf();
  }

  Future<void> pauseSession(String id) async {
    await ref.read(sessionRepositoryProvider).pause(id);
    ref.invalidateSelf();
  }
}

final campaignDetailProvider = AsyncNotifierProvider.autoDispose
    .family<CampaignDetailController, CampaignDetailData, String>(
  CampaignDetailController.new,
);
