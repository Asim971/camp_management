import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../../core/result/result.dart';
import '../../domain/campaign/campaign.dart';
import '../../domain/campaign/campaign_draft.dart';
import '../../domain/campaign/campaign_repository.dart';
import 'campaign_dto.dart';

/// Dio-backed [CampaignRepository]. Translates DTOs → domain and Dio errors →
/// [Failure]. Endpoints are placeholders pending the Sales Eco/campaign-service
/// contract (🔒 dependency; Task T-1.1.2).
class CampaignRepositoryImpl implements CampaignRepository {
  CampaignRepositoryImpl(this._dio);

  final Dio _dio;

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
          .map(
            (e) => CampaignDto.fromJson(e as Map<String, dynamic>).toDomain(),
          )
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
      return Ok(CampaignDto.fromJson(res.data!).toDomain());
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  @override
  Future<Result<Campaign>> createDraft(CampaignDraft draft) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/campaigns',
        data: _draftToJson(draft),
      );
      return Ok(CampaignDto.fromJson(res.data!).toDomain());
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  @override
  Future<Result<Campaign>> updateDraft(String id, CampaignDraft draft) async {
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        '/campaigns/$id',
        data: _draftToJson(draft),
      );
      return Ok(CampaignDto.fromJson(res.data!).toDomain());
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  Map<String, dynamic> _draftToJson(CampaignDraft d) => {
        'name': d.name,
        'type': d.type,
        'objective': d.objective,
        'audienceTypes': d.audienceTypes,
        'territoryIds': d.territoryIds,
        'target': d.target,
        'budgetReference': d.budgetReference,
        'approverId': d.approverId,
        'geofenceEnabled': d.geofenceEnabled,
        'sessions': [
          for (final s in d.sessions)
            {
              'venue': s.venue,
              'capacity': s.capacity,
              'startAt': s.startAt?.toIso8601String(),
              'endAt': s.endAt?.toIso8601String(),
            },
        ],
      };

  @override
  Future<Result<Campaign>> submitForApproval(String id) async {
    try {
      final res =
          await _dio.post<Map<String, dynamic>>('/campaigns/$id/submit');
      return Ok(CampaignDto.fromJson(res.data!).toDomain());
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  @override
  Future<Result<Campaign>> decide(
    String id, {
    required CampaignDecision decision,
    String? reason,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/campaigns/$id/decision',
        data: {'decision': decision.name, 'reason': reason},
      );
      return Ok(CampaignDto.fromJson(res.data!).toDomain());
    } catch (e) {
      return Err(mapDioError(e));
    }
  }
}
