import '../../core/result/result.dart';
import '../../core/trace/trace_id.dart';
import 'registration.dart';

/// Reads the session's registered participants. Field search is offline-first:
/// [searchCached] filters a locally-cached list so it works with no network,
/// while [cacheSessionRegistrations] refreshes that cache when online (called
/// during session readiness — M-01).
abstract interface class RegistrationRepository {
  /// Fetches the session roster from the server and stores it locally.
  Future<Result<void>> cacheSessionRegistrations(String sessionId);

  /// Filters the locally-cached roster. Returns an empty list when nothing
  /// matches or the cache is empty — the UI distinguishes those cases.
  Future<List<RegisteredCarpenter>> searchCached(
    String sessionId,
    String query,
  );

  // ---- Web registration workspace (W-06) ----------------------------------

  /// Searches the Sales Eco carpenter master (read-only; never a local shadow
  /// master — §8.6). Used by the web registration workspace.
  Future<Result<List<RegisteredCarpenter>>> searchMaster(String query);

  /// Registers the selected carpenters to a campaign. Idempotent on the server.
  ///
  /// [trace] is the per-action correlation id; pass the same one to the audit
  /// event for this action so the two can be joined (Architecture §12).
  Future<Result<void>> register(
    String campaignId,
    List<String> carpenterIds, {
    TraceId? trace,
  });

  /// Submits a Sales Eco new-profile request; the participant shows as
  /// "Pending profile sync" until reconciliation (§9.2, §9.4).
  Future<Result<void>> requestNewProfile(
    String campaignId,
    String name,
    String phone,
  );
}
