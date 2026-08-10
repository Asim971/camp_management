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

/// Bounded retries for the rare race where a concurrent loser's row
/// disappears (the owner's handler failed and deleted its reservation)
/// between our failed claim attempt and our follow-up SELECT — see the loop
/// in [idempotency] below. Never expected to exhaust in practice; it exists
/// so that vanishingly narrow window fails loudly (a [StateError]) instead of
/// silently returning the wrong thing.
const int _maxClaimAttempts = 5;

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
/// Replay restores `response_status` and `response_body` only — never
/// headers. `Location`/`ETag`/etc. on the original response are not stored
/// and will not appear on a replay, so a route relying on this middleware
/// for idempotency must carry everything the caller needs in the JSON body,
/// not in a header.
///
/// ## Reserve, then fulfil
///
/// A row in `idempotency_keys` with `response_status IS NULL` is a
/// *reservation*: some request claimed `(user_id, key)` and is executing the
/// handler right now, with no response yet to replay. This exists to close
/// a race that a plain "SELECT, miss, run handler, INSERT ... ON CONFLICT DO
/// NOTHING" shape cannot: two concurrent identical POSTs (exactly what the
/// client's `RetryInterceptor` sends on a send/receive timeout — the first
/// attempt may still be running when the retry fires) both miss the SELECT,
/// both run the handler, and `DO NOTHING` silently absorbs the resulting
/// primary-key collision. Every request instead starts by trying to claim
/// the row atomically:
///
/// ```sql
/// INSERT INTO idempotency_keys (user_id, key, request_hash, expires_at)
/// VALUES (@user, @key, @hash, @expires)
/// ON CONFLICT (user_id, key) DO UPDATE SET
///   request_hash = EXCLUDED.request_hash,
///   response_status = NULL,
///   response_body = NULL,
///   expires_at = EXCLUDED.expires_at
/// WHERE idempotency_keys.expires_at <= now()
/// RETURNING key
/// ```
///
/// A row comes back in exactly two cases: a fresh key (plain INSERT), or an
/// *expired* key being reclaimed as a brand-new reservation (the `DO UPDATE
/// ... WHERE` branch) — the same statement fixes the fossil-record problem
/// where a stale fulfilled row's PK blocked ever storing a fresh response
/// for that key again. Postgres's row lock on the conflicting row makes this
/// atomic the same way `tokens.dart`'s `UPDATE ... WHERE used_at IS NULL`
/// claim is atomic: a second, concurrent attempt against the same row blocks
/// until the first commits, then re-evaluates its own `WHERE` and gets
/// nothing back.
///
/// - **A row came back → we own it.** Run the handler.
///   - `2xx` → `UPDATE` the reservation with the real status/body (the
///     fulfilled state other requests will replay).
///   - Non-`2xx`, or the handler *throws* → `DELETE` the reservation before
///     the failure propagates, so a retry can claim the key fresh rather
///     than being stuck behind a reservation nobody will ever fulfil. This
///     is also what keeps "failed responses are not stored" true for the
///     thrown-exception path, not just the ordinary-error-response path.
/// - **No row came back → someone else owns it.** `SELECT` the current row:
///   - `request_hash` differs → `ApiException(idempotencyKeyReused)`, the
///     guard against a key collision returning someone else's answer,
///     checked ahead of the in-flight/fulfilled split below because a body
///     mismatch is a client error regardless of how far the original
///     request got.
///   - `response_status IS NULL` → still in flight →
///     `ApiException(idempotencyKeyInFlight)` (409 — the IETF Idempotency-
///     Key draft's answer for "come back after the in-flight attempt
///     resolves").
///   - Otherwise → fulfilled → replay `response_status`/`response_body`
///     verbatim.
///
///   That SELECT can, in a vanishingly narrow window, find nothing at all:
///   the owner's handler failed and deleted the reservation between our
///   failed claim attempt and this SELECT. The loop retries the claim from
///   the top rather than treating an empty SELECT as any of the three cases
///   above.
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

      for (var attempt = 0; attempt < _maxClaimAttempts; attempt++) {
        final claim = await db.execute(
          'INSERT INTO idempotency_keys '
          '(user_id, key, request_hash, expires_at) '
          'VALUES (@user, @key, @hash, @expires) '
          'ON CONFLICT (user_id, key) DO UPDATE SET '
          '  request_hash = EXCLUDED.request_hash, '
          '  response_status = NULL, '
          '  response_body = NULL, '
          '  expires_at = EXCLUDED.expires_at '
          'WHERE idempotency_keys.expires_at <= now() '
          'RETURNING key',
          params: {
            'user': userId,
            'key': key,
            'hash': requestHash,
            'expires': DateTime.now().toUtc().add(_ttl),
          },
        );

        if (claim.isNotEmpty) {
          return _runOwned(
            db: db,
            inner: inner,
            request: rehydrated,
            userId: userId,
            key: key,
          );
        }

        final existing = await db.execute(
          'SELECT request_hash, response_status, response_body '
          'FROM idempotency_keys WHERE user_id = @user AND key = @key',
          params: {'user': userId, 'key': key},
        );
        if (existing.isEmpty) {
          // The owner's reservation vanished between our failed claim and
          // this SELECT (it failed and cleaned up). Retry the claim.
          continue;
        }

        final stored = row(existing.single);
        if (stored['request_hash']! as String != requestHash) {
          throw ApiException(ApiErrorCode.idempotencyKeyReused);
        }
        final status = stored['response_status'] as int?;
        if (status == null) {
          throw ApiException(ApiErrorCode.idempotencyKeyInFlight);
        }
        return Response(
          status,
          body: stored['response_body']! as String,
          headers: {'content-type': 'application/json'},
        );
      }

      throw StateError(
        'idempotency: exhausted $_maxClaimAttempts claim attempts for '
        '(user=$userId, key=$key) — a reservation kept disappearing out '
        'from under every retry.',
      );
    };
  };
}

/// Runs [inner] having already won the claim on `(userId, key)`. Fulfils
/// the reservation on a `2xx`, deletes it otherwise — including when
/// [inner] throws, so the exception's own envelope handling still applies
/// after cleanup.
Future<Response> _runOwned({
  required Db db,
  required Handler inner,
  required Request request,
  required String userId,
  required String key,
}) async {
  Response response;
  try {
    response = await inner(request);
  } on Object {
    await _deleteReservation(db, userId: userId, key: key);
    rethrow;
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    await _deleteReservation(db, userId: userId, key: key);
    return response;
  }

  final responseBody = await response.readAsString();
  await db.execute(
    'UPDATE idempotency_keys SET response_status = @status, '
    '  response_body = @body '
    'WHERE user_id = @user AND key = @key',
    params: {
      'status': response.statusCode,
      'body': responseBody,
      'user': userId,
      'key': key,
    },
  );
  return response.change(body: responseBody);
}

Future<void> _deleteReservation(
  Db db, {
  required String userId,
  required String key,
}) => db.execute(
  'DELETE FROM idempotency_keys WHERE user_id = @user AND key = @key',
  params: {'user': userId, 'key': key},
);

String _hash(List<int> bytes) =>
    base64.encode(const DartSha256().hashSync(bytes).bytes);
