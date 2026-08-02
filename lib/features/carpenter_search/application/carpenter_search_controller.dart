import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../domain/registration/registration.dart';

/// Field carpenter search (M-02), keyed by session. Offline-first: results come
/// from the locally-cached roster, so search is instant with no network.
class CarpenterSearchController
    extends AutoDisposeFamilyAsyncNotifier<List<RegisteredCarpenter>, String> {
  @override
  Future<List<RegisteredCarpenter>> build(String sessionId) async => const [];

  Future<void> search(String query) async {
    // Require a minimum query so the field operator gets deliberate matches.
    if (query.trim().length < 2) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(registrationRepositoryProvider).searchCached(arg, query),
    );
  }
}

final carpenterSearchProvider = AsyncNotifierProvider.autoDispose
    .family<CarpenterSearchController, List<RegisteredCarpenter>, String>(
      CarpenterSearchController.new,
    );
