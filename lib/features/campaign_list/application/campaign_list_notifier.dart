import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../domain/campaign/campaign.dart';
import '../../../domain/campaign/campaign_repository.dart';

/// Feature-scoped state for the Campaign List (W-02). Demonstrates the standard
/// pattern used across every feature: an AsyncNotifier that loads through a
/// repository and exposes AsyncValue so the UI renders the mandated
/// loading/data/error/empty states (Guideline §8.2).
class CampaignListNotifier extends AsyncNotifier<Paged<Campaign>> {
  CampaignQuery _query = const CampaignQuery();

  @override
  Future<Paged<Campaign>> build() => _fetch(_query);

  Future<Paged<Campaign>> _fetch(CampaignQuery query) async {
    final repo = ref.read(campaignRepositoryProvider);
    final result = await repo.list(query);
    return result.fold(
      (paged) => paged,
      (failure) => throw failure, // surfaced as AsyncError → typed UI state
    );
  }

  Future<void> applyQuery(CampaignQuery query) async {
    _query = query;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(query));
  }

  Future<void> refresh() => applyQuery(_query);
}

final campaignListProvider =
    AsyncNotifierProvider<CampaignListNotifier, Paged<Campaign>>(
  CampaignListNotifier.new,
);
