import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../network/dio_client.dart';
import '../result/result.dart';
import 'notice.dart';

/// Transport seam for newer notice versions.
///
/// 🔒 The notice contract (endpoint, payload shape, versioning semantics) is
/// unresolved. Keeping it behind one method means the resolution rule, the
/// cache and the consent record are all transport-agnostic when it lands.
abstract interface class NoticeSource {
  Future<Result<List<ConsentNotice>>> fetchLatest();
}

/// Dio-backed source. Endpoint and shape are placeholders pending the 🔒
/// contract, exactly as `DioAuthService` and `DioAuditTransport` are.
class DioNoticeSource implements NoticeSource {
  DioNoticeSource(this._dio);

  final Dio _dio;

  @override
  Future<Result<List<ConsentNotice>>> fetchLatest() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/consent/notices');
      final list = (res.data!['notices'] as List)
          .map(
            (e) => ConsentNotice.fromJson((e as Map).cast<String, Object?>()),
          )
          .toList();
      return Ok(list);
    } catch (e) {
      return Err(mapDioError(e));
    }
  }
}

/// Resolves which consent notice to show.
///
/// The rule: the highest version this device ACTUALLY HOLDS for the requested
/// language, cached or bundled. [resolve] never awaits the network — capture
/// happens offline in the field, and blocking it on a fetch would make the
/// bundled floor pointless. Fetching is [refreshInBackground]'s job and is
/// entirely off the capture path.
class NoticeRepository {
  /// Callers still write `source:`, `readCached:` and `writeCached:` — Dart
  /// strips the leading underscore from a private initialising formal's
  /// argument name, the same pattern `SyncEngineImpl` already uses here. Plain
  /// `_source = source` initialisers trip `prefer_initializing_formals`, which
  /// is fatal under `--fatal-infos`. `loadAsset` stays a manual initialiser
  /// because its value is a fallback expression, not a passthrough.
  NoticeRepository({
    required this._source,
    required this._readCached,
    required this._writeCached,
    Future<String> Function(String key)? loadAsset,
  }) : _loadAsset = loadAsset ?? rootBundle.loadString;

  static const String bundledAssetKey = 'assets/consent/notice_v1.json';

  final NoticeSource _source;
  final Future<List<ConsentNotice>> Function() _readCached;
  final Future<void> Function(List<ConsentNotice>) _writeCached;
  final Future<String> Function(String) _loadAsset;

  /// The notice to show for [language], or `Err` if none can be resolved.
  ///
  /// `Err` rather than a null notice on purpose: spec D7 has consent failing
  /// CLOSED, so a caller cannot accidentally render a blank notice and proceed.
  Future<Result<ConsentNotice>> resolve(String language) async {
    final candidates = <ConsentNotice>[];

    // BUNDLED FIRST, deliberately. Together with the strictly-greater
    // comparison below this makes the bundled copy win a version tie, and it
    // must win: the bundled text shipped inside this binary and is the copy
    // that went through review for version N. A cached row claiming version N
    // with different text means the server contradicted its own monotonic
    // versioning contract, and the locally reviewed copy is the safer one to
    // show. A genuine correction arrives as version N+1 — that is what
    // monotonic versioning is for.
    try {
      candidates.addAll(
        (await _bundled()).where((n) => n.language == language),
      );
    } catch (error) {
      debugPrint('Bundled notice unreadable ($error).');
    }

    try {
      candidates.addAll(
        (await _readCached()).where((n) => n.language == language),
      );
    } catch (error) {
      // A cache fault must not prevent the bundled floor from being used.
      debugPrint('Cached notices unreadable ($error); using the bundle.');
    }

    if (candidates.isEmpty) {
      return Err(
        Failure(
          FailureKind.unknown,
          message: 'No consent notice is available in "$language".',
        ),
      );
    }

    // A fold rather than `sort(...)..first`: List.sort is NOT stable and the
    // comparator returns 0 for two notices at the same version, so a sort
    // leaves the winner among equals to quicksort's partitioning — an artifact
    // of how many rows the cache happens to hold. Two copies at version N with
    // different text have different content hashes, and the consent record
    // stores that hash as proof of the exact wording shown, so an arbitrary
    // pick yields a record matching neither copy. `>` and not `>=` is what
    // keeps the first-added (bundled) candidate in place on a tie.
    ConsentNotice best = candidates.first;
    for (final candidate in candidates.skip(1)) {
      if (candidate.version > best.version) best = candidate;
    }
    return Ok(best);
  }

  /// Opportunistic. Never called from the capture path, never surfaced.
  Future<void> refreshInBackground() async {
    final result = await _source.fetchLatest();
    if (result case Ok(:final value) when value.isNotEmpty) {
      try {
        await _writeCached(value);
      } catch (error) {
        debugPrint('Fetched notices could not be cached ($error).');
      }
    }
  }

  Future<List<ConsentNotice>> _bundled() async {
    final json =
        jsonDecode(await _loadAsset(bundledAssetKey)) as Map<String, Object?>;
    return (json['notices']! as List)
        .map((e) => ConsentNotice.fromJson((e as Map).cast<String, Object?>()))
        .toList();
  }
}
