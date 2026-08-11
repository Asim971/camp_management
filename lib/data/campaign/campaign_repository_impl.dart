import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/dio_client.dart';
import '../../core/network/trace_options.dart';
import '../../core/result/result.dart';
import '../../core/trace/trace_id.dart';
import '../../domain/campaign/campaign.dart';
import '../../domain/campaign/campaign_draft.dart';
import '../../domain/campaign/campaign_repository.dart';
import 'campaign_mapper.dart';

/// Dio-backed [CampaignRepository]. Translates wire JSON → domain (via
/// [campaignFromWire]) and Dio errors → [Failure].
class CampaignRepositoryImpl implements CampaignRepository {
  CampaignRepositoryImpl(this._dio);

  final Dio _dio;
  static const _uuid = Uuid();

  @override
  Future<Result<Paged<Campaign>>> list(CampaignQuery query) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/campaigns',
        queryParameters: {
          if (query.search != null) 'q': query.search,
          if (query.statuses.isNotEmpty)
            'status': query.statuses.map((s) => s.wireValue).toList(),
          'page': query.page,
          'pageSize': query.pageSize,
        },
      );
      final data = res.data!;
      final items = (data['items'] as List)
          .map((e) => campaignFromWire(e as Map<String, dynamic>))
          .toList();
      return Ok(Paged(items: items, total: data['total'] as int));
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  @override
  Future<Result<Campaign>> getById(String id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/campaigns/$id');
      return Ok(campaignFromWire(res.data!));
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  @override
  Future<Result<Campaign>> createDraft(
    CampaignDraft draft, {
    TraceId? trace,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/campaigns',
        data: draftToWire(draft),
        // A fresh key per call. User-level double-submit is already
        // prevented by disabling the action while the request is in flight
        // (WizardState.saving/.submitting); this key only has to cover a
        // transport-level retry of the SAME request, which reuses it.
        options: traceOptions(
          trace ?? TraceId.generate(),
          idempotencyKey: 'create:${_uuid.v4()}',
        ),
      );
      return Ok(campaignFromWire(res.data!));
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  @override
  Future<Result<Campaign>> updateDraft(
    String id,
    CampaignDraft draft, {
    required int version,
  }) async {
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        '/campaigns/$id',
        // No idempotency key: PUT is already idempotent by HTTP semantics,
        // and the version guard below is what makes a stale write 409 rather
        // than silently overwriting a concurrent change.
        data: {...draftToWire(draft), 'version': version},
      );
      return Ok(campaignFromWire(res.data!));
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  @override
  Future<Result<Campaign>> submitForApproval(
    String id, {
    required int version,
    TraceId? trace,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/campaigns/$id/submit',
        data: {'version': version},
        // A key derived from the action, so a double-tap or a transport retry
        // replays the first response instead of transitioning twice. It
        // embeds the version so a legitimate second submit after a real
        // change is not mistaken for a replay of the first.
        options: traceOptions(
          trace ?? TraceId.generate(),
          idempotencyKey: 'submit:$id:$version',
        ),
      );
      return Ok(campaignFromWire(res.data!));
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  @override
  Future<Result<Campaign>> decide(
    String id, {
    required CampaignDecision decision,
    String? reason,
    required int version,
    required List<String> acknowledgedWarnings,
    TraceId? trace,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/campaigns/$id/decision',
        data: {
          'decision': draftDecisionWire(decision),
          'reason': reason,
          'version': version,
          'acknowledgedWarnings': acknowledgedWarnings,
        },
        options: traceOptions(
          trace ?? TraceId.generate(),
          idempotencyKey: 'decide:$id:$version',
        ),
      );
      return Ok(campaignFromWire(res.data!));
    } catch (e) {
      return Err(mapDioError(e));
    }
  }
}
