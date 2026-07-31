import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../../core/result/result.dart';
import '../../core/storage/app_database.dart';
import '../../domain/common/status.dart';
import '../../domain/registration/registration.dart';
import '../../domain/registration/registration_repository.dart';

/// Offline-first registration repository. The roster is cached as JSON in the
/// Drift `cached_references` table so field search runs with no network; the
/// server is only touched to (re)warm the cache.
class RegistrationRepositoryImpl implements RegistrationRepository {
  RegistrationRepositoryImpl(this._dio, this._db);

  final Dio _dio;
  final AppDatabase _db;

  String _cacheKey(String sessionId) => 'session:$sessionId:registrations';

  @override
  Future<Result<void>> cacheSessionRegistrations(String sessionId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/sessions/$sessionId/registrations',
      );
      final items = res.data!['items'] as List;
      await _db.into(_db.cachedReferences).insertOnConflictUpdate(
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
    final row = await (_db.select(_db.cachedReferences)
          ..where((t) => t.key.equals(_cacheKey(sessionId))))
        .getSingleOrNull();
    if (row == null) return const [];

    final q = query.trim().toLowerCase();
    final all = (jsonDecode(row.valueJson) as List)
        .map((e) => _fromJson(e as Map<String, dynamic>));

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
    List<String> carpenterIds,
  ) async {
    try {
      await _dio.post<void>(
        '/campaigns/$campaignId/registrations',
        data: {'carpenterIds': carpenterIds},
        options: Options(headers: {'Idempotency-Key': carpenterIds.join(',')}),
      );
      return const Ok(null);
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  @override
  Future<Result<void>> requestNewProfile(
    String campaignId,
    String name,
    String phone,
  ) async {
    try {
      await _dio.post<void>(
        '/campaigns/$campaignId/profile-requests',
        data: {'name': name, 'phone': phone},
      );
      return const Ok(null);
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
        attendanceState: _attendance(j['attendanceState'] as String?),
      );

  AttendanceStatus _attendance(String? s) => AttendanceStatus.values.firstWhere(
        (a) => a.name == s,
        orElse: () => AttendanceStatus.notCaptured,
      );
}
