import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/dio_client.dart';
import '../../core/result/result.dart';
import '../../domain/session/campaign_session.dart';
import '../../domain/session/session_repository.dart';

class SessionRepositoryImpl implements SessionRepository {
  SessionRepositoryImpl(this._dio);
  final Dio _dio;

  @override
  Future<Result<List<CampaignSession>>> listForCampaign(
    String campaignId,
  ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/campaigns/$campaignId/sessions',
      );
      final items = (res.data!['items'] as List)
          .map((e) => _fromJson(e as Map<String, dynamic>))
          .toList();
      return Ok(items);
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  @override
  Future<Result<CampaignSession>> start(String id) => _action(id, 'start');
  @override
  Future<Result<CampaignSession>> close(String id) => _action(id, 'close');
  @override
  Future<Result<CampaignSession>> pause(String id) => _action(id, 'pause');

  Future<Result<CampaignSession>> _action(String id, String action) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/sessions/$id/$action',
      );
      return Ok(_fromJson(res.data!));
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  CampaignSession _fromJson(Map<String, dynamic> j) => CampaignSession(
    id: j['id'] as String,
    campaignId: j['campaignId'] as String,
    venue: j['venue'] as String,
    status: _parseStatus(j['status'] as String?),
    startAt: j['startAt'] == null
        ? null
        : DateTime.parse(j['startAt'] as String),
    endAt: j['endAt'] == null ? null : DateTime.parse(j['endAt'] as String),
    capacity: (j['capacity'] as int?) ?? 0,
    registeredCount: (j['registeredCount'] as int?) ?? 0,
    pendingSyncCount: (j['pendingSyncCount'] as int?) ?? 0,
    reviewCount: (j['reviewCount'] as int?) ?? 0,
    approvedCount: (j['approvedCount'] as int?) ?? 0,
    readinessOk: (j['readinessOk'] as bool?) ?? true,
  );

  /// An unrecognised wire status is surfaced as a visible, action-disabling
  /// fallback — never `upcoming`, which would enable Start on a session in an
  /// unknown state. Same policy as ImportStatus parsing.
  SessionStatus _parseStatus(String? wire) {
    final parsed = wire == null ? null : SessionStatus.tryParseWire(wire);
    if (parsed == null) {
      debugPrint(
        'SessionRepositoryImpl: unrecognised session status "$wire"; '
        'treating it as captureClosed (non-operational).',
      );
      return SessionStatus.captureClosed;
    }
    return parsed;
  }
}
