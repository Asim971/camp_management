import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/dio_client.dart';
import '../../core/network/trace_options.dart';
import '../../core/result/result.dart';
import '../../core/storage/app_database.dart';
import '../../core/trace/trace_id.dart';
import '../../domain/common/status.dart';
import '../../domain/registration/registration.dart';
import '../../domain/registration/registration_repository.dart';

const Uuid _uuid = Uuid();

/// Offline-first registration repository. The roster is cached as JSON in the
/// Drift `cached_references` table so field search runs with no network; the
/// server is only touched to (re)warm the cache.
class RegistrationRepositoryImpl implements RegistrationRepository {
  RegistrationRepositoryImpl(this._dio, this._db);

  final Dio _dio;
  final AppDatabase _db;

  /// [headers] carry the request's own concerns (e.g. an idempotency key);
  /// [trace] is layered in via `extra` alongside them. `null` trace lets
  /// CorrelationIdInterceptor mint a per-request id.
  Options _options(Map<String, String> headers, TraceId? trace) => Options(
    headers: headers,
    extra: trace == null ? null : {traceIdExtraKey: trace},
  );

  String _cacheKey(String sessionId) => 'session:$sessionId:registrations';

  @override
  Future<Result<void>> cacheSessionRegistrations(String sessionId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/sessions/$sessionId/registrations',
      );
      final items = res.data!['items'] as List;
      await _db
          .into(_db.cachedReferences)
          .insertOnConflictUpdate(
            CachedReferencesCompanion.insert(
              key: _cacheKey(sessionId),
              valueJson: jsonEncode(items),
              fetchedAt: DateTime.now(),
            ),
          );
      return const Ok(null);
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  @override
  Future<List<RegisteredCarpenter>> searchCached(
    String sessionId,
    String query,
  ) async {
    final row = await (_db.select(
      _db.cachedReferences,
    )..where((t) => t.key.equals(_cacheKey(sessionId)))).getSingleOrNull();
    if (row == null) return const [];

    final q = query.trim().toLowerCase();
    final all = (jsonDecode(row.valueJson) as List).map(
      (e) => _fromJson(e as Map<String, dynamic>),
    );

    return all.where((c) {
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          c.displayId.toLowerCase().contains(q) ||
          c.phoneSuffix.endsWith(q);
    }).toList();
  }

  @override
  Future<Result<List<RegisteredCarpenter>>> searchMaster(String query) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/carpenters',
        queryParameters: {'q': query},
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
  Future<Result<void>> register(
    String campaignId,
    List<String> carpenterIds, {
    TraceId? trace,
  }) async {
    try {
      await _dio.post<void>(
        '/campaigns/$campaignId/registrations',
        data: {'carpenterIds': carpenterIds},
        options: _options({'Idempotency-Key': _uuid.v4()}, trace),
      );
      return const Ok(null);
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  @override
  Future<Result<RegisteredCarpenter>> requestNewProfile(
    String campaignId,
    String name,
    String phone,
  ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/campaigns/$campaignId/profile-requests',
        data: {'name': name, 'phone': phone},
        options: _options({'Idempotency-Key': _uuid.v4()}, null),
      );
      return Ok(_fromJson(res.data!['carpenter'] as Map<String, dynamic>));
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  RegisteredCarpenter _fromJson(Map<String, dynamic> j) => RegisteredCarpenter(
    id: j['id'] as String,
    name: j['name'] as String,
    displayId: j['displayId'] as String,
    phoneSuffix: j['phoneSuffix'] as String,
    territory: j['territory'] as String,
    dealerContext: j['dealerContext'] as String?,
    thumbnailUrl: j['thumbnailUrl'] as String?,
    eligible: (j['eligible'] as bool?) ?? true,
    attendanceState: _attendanceFromWire(j['attendanceState'] as String?),
  );

  /// `attendanceState` is OPTIONAL on the wire: the real service omits it
  /// until sub-project 4 defines the vocabulary; the mock still sends it.
  /// Absent → notCaptured is the deliberate, visible fallback for a
  /// display-only field (the shared-contract rule allows a fallback that is
  /// CHOSEN, not silently inherited from firstWhere's orElse). An
  /// unrecognised non-null value also lands on notCaptured — for this field
  /// that under-claims (shows "not captured" instead of a state we don't
  /// know), which is the safe direction.
  AttendanceStatus _attendanceFromWire(String? wire) {
    if (wire == null) return AttendanceStatus.notCaptured;
    for (final s in AttendanceStatus.values) {
      if (s.name == wire) return s;
    }
    return AttendanceStatus.notCaptured;
  }
}
