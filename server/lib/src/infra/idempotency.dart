import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
// `Sha256`'s hash implementation, narrowed with `show` for the same reason
// tokens.dart narrows it: `package:crypto` is not a declared dependency, and
// `cryptography`'s own `SecretKey`/etc. would otherwise be pulled in wholesale.
import 'package:cryptography/dart.dart' show DartSha256;
import 'package:shelf/shelf.dart';

import '../auth/middleware.dart';
import '../db/pool.dart';
import 'error_envelope.dart';

const String _headerName = 'Idempotency-Key';
const Duration _ttl = Duration(hours: 24);

/// Makes a POST safe to retry: the same `(user, key)` pair replays the first
/// response verbatim instead of re-running the handler.
///
/// Applies to `POST` only — every other method passes straight through.
/// Callers MUST NOT mount this on `/auth/*` (spec §5): `/auth/refresh`
/// rotates the refresh token on every call, and replaying a cached response
/// would hand back an already-superseded token pair. This middleware has no
/// path awareness of its own; keeping `/auth/*` unwrapped is the router's
/// job, done by simply never composing this middleware onto that sub-router.
///
/// Must run *after* `authenticate` in the pipeline — it reads [authOf] to
/// scope the key per user, per `idempotency_keys`'s `PRIMARY KEY (user_id,
/// key)`. Without that scope, one user's key could replay another user's
/// response.
///
/// Rules:
/// - Missing/empty header on a POST → `ApiException(idempotencyKeyRequired)`.
/// - A first-seen key runs the handler; only a `2xx` response is stored
///   (`expires_at = now() + 24h`) — a stored failure would make a transient
///   500 permanent for that key, since the client would then be stuck
///   replaying it forever instead of retrying.
/// - A previously-seen key with a matching request hash replays the stored
///   `response_status`/`response_body` without touching the handler.
/// - A previously-seen key with a *different* body →
///   `ApiException(idempotencyKeyReused)` — the guard against a key
///   collision silently returning someone else's answer.
Middleware idempotency({required Db db}) {
  return (Handler inner) {
    return (Request request) async {
      if (request.method != 'POST') return inner(request);

      final key = request.headers[_headerName];
      if (key == null || key.isEmpty) {
        throw ApiException(ApiErrorCode.idempotencyKeyRequired);
      }

      // A shelf request body is a single-subscription stream: read it once
      // here for hashing, then re-attach the same bytes so the downstream
      // handler does not see an already-drained, empty stream.
      final bodyBytes = <int>[];
      await for (final chunk in request.read()) {
        bodyBytes.addAll(chunk);
      }
      final rehydrated = request.change(body: bodyBytes);
      final requestHash = _hash(bodyBytes);
      final userId = authOf(rehydrated).userId;

      final existing = await db.execute(
        'SELECT request_hash, response_status, response_body '
        'FROM idempotency_keys '
        'WHERE user_id = @user AND key = @key AND expires_at > now()',
        params: {'user': userId, 'key': key},
      );

      if (existing.isNotEmpty) {
        final stored = row(existing.single);
        if (stored['request_hash']! as String != requestHash) {
          throw ApiException(ApiErrorCode.idempotencyKeyReused);
        }
        return Response(
          stored['response_status']! as int,
          body: stored['response_body']! as String,
          headers: {'content-type': 'application/json'},
        );
      }

      final response = await inner(rehydrated);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final responseBody = await response.readAsString();
        await db.execute(
          'INSERT INTO idempotency_keys '
          '(key, user_id, request_hash, response_status, response_body, '
          ' expires_at) '
          'VALUES (@key, @user, @hash, @status, @body, @expires) '
          'ON CONFLICT (user_id, key) DO NOTHING',
          params: {
            'key': key,
            'user': userId,
            'hash': requestHash,
            'status': response.statusCode,
            'body': responseBody,
            'expires': DateTime.now().toUtc().add(_ttl),
          },
        );
        return response.change(body: responseBody);
      }
      return response;
    };
  };
}

String _hash(List<int> bytes) =>
    base64.encode(const DartSha256().hashSync(bytes).bytes);
