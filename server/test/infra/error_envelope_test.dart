import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:campaign_service/src/infra/correlation.dart';
import 'package:campaign_service/src/infra/error_envelope.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  Handler wrap(Handler inner) => const Pipeline()
      .addMiddleware(correlation())
      .addMiddleware(errorEnvelope())
      .addHandler(inner);

  Future<Map<String, Object?>> errorBody(Response res) async =>
      (jsonDecode(await res.readAsString()) as Map<String, Object?>)['error']!
          as Map<String, Object?>;

  test('an ApiException becomes the documented envelope', () async {
    final res = await wrap(
      (_) => throw ApiException(
        ApiErrorCode.campaignInvalidTransition,
        message: 'Cannot approve a DRAFT campaign.',
        details: {'currentStatus': 'DRAFT'},
      ),
    )(Request('POST', Uri.parse('http://localhost/x')));

    expect(res.statusCode, 409);
    final error = await errorBody(res);
    expect(error['code'], 'CAMPAIGN_INVALID_TRANSITION');
    expect(error['message'], 'Cannot approve a DRAFT campaign.');
    expect((error['details']! as Map)['currentStatus'], 'DRAFT');
    expect(error['traceId'], isA<String>());
  });

  test('status codes match the client mapDioError table', () async {
    Future<int> statusFor(ApiErrorCode code) async => (await wrap(
      (_) => throw ApiException(code),
    )(Request('POST', Uri.parse('http://localhost/x')))).statusCode;

    expect(await statusFor(ApiErrorCode.badRequest), 400);
    expect(await statusFor(ApiErrorCode.unauthorized), 401);
    expect(await statusFor(ApiErrorCode.forbidden), 403);
    expect(await statusFor(ApiErrorCode.notFound), 404);
    expect(await statusFor(ApiErrorCode.conflictStaleVersion), 409);
    expect(await statusFor(ApiErrorCode.campaignInvalidTransition), 409);
    // The least obvious entry in the table: a segregation-of-duties
    // violation is a permission problem (the same reviewer approving their
    // own submission), not a conflict, so it maps like `forbidden`.
    expect(await statusFor(ApiErrorCode.segregationOfDutiesViolation), 403);
    expect(await statusFor(ApiErrorCode.campaignValidationFailed), 422);
    expect(await statusFor(ApiErrorCode.decisionReasonRequired), 422);
    expect(await statusFor(ApiErrorCode.warningsUnacknowledged), 422);
    expect(await statusFor(ApiErrorCode.idempotencyKeyRequired), 400);
    expect(await statusFor(ApiErrorCode.idempotencyKeyReused), 422);
    // 409, not 422: this is "someone else's attempt for this key is still
    // running", the same family as a stale-version conflict, not a
    // validation failure of the request itself.
    expect(await statusFor(ApiErrorCode.idempotencyKeyInFlight), 409);
    expect(await statusFor(ApiErrorCode.unknownCarpenter), 422);
    expect(await statusFor(ApiErrorCode.importFileInvalid), 422);
    expect(await statusFor(ApiErrorCode.internal), 500);
  });

  // An unexpected exception must not leak its message: a SQL error naming a
  // column is reconnaissance. The trace id is the bridge to the server log.
  test(
    'an unexpected error is a generic 500 that still carries the trace id',
    () async {
      final res = await wrap(
        (_) => throw StateError('column "secret" not found'),
      )(Request('GET', Uri.parse('http://localhost/x')));

      expect(res.statusCode, 500);
      final error = await errorBody(res);
      expect(error['code'], 'INTERNAL');
      expect(error['message'], isNot(contains('secret')));
      expect(error['traceId'], isA<String>());
    },
  );

  test('the client correlation id is honoured and echoed', () async {
    final res = await wrap((req) => Response.ok(correlationOf(req)))(
      Request(
        'GET',
        Uri.parse('http://localhost/x'),
        headers: {'X-Correlation-Id': 'client-supplied-id'},
      ),
    );

    expect(await res.readAsString(), 'client-supplied-id');
    expect(res.headers['x-correlation-id'], 'client-supplied-id');
  });

  test('a missing correlation id is minted, not left empty', () async {
    final res = await wrap((req) => Response.ok(correlationOf(req)))(
      Request('GET', Uri.parse('http://localhost/x')),
    );
    expect((await res.readAsString()).length, greaterThan(8));
  });

  // Task 5's authenticate/requirePermission answer with bare
  // Response.unauthorized(null) / Response.forbidden(null) — responses, not
  // exceptions — so the catch clauses above never see them. Without this
  // rule the API would answer in two different error shapes.
  test('a bodyless 401 response is wrapped in the same envelope', () async {
    final res = await wrap((_) => Response.unauthorized(null))(
      Request('GET', Uri.parse('http://localhost/x')),
    );

    expect(res.statusCode, 401);
    final error = await errorBody(res);
    expect(error['code'], 'UNAUTHORIZED');
    expect(error['traceId'], isA<String>());
  });

  test('a bodyless 403 response is wrapped in the same envelope', () async {
    final res = await wrap((_) => Response.forbidden(null))(
      Request('GET', Uri.parse('http://localhost/x')),
    );

    expect(res.statusCode, 403);
    final error = await errorBody(res);
    expect(error['code'], 'FORBIDDEN');
  });

  // A route that already wrote its own envelope must not be double-wrapped —
  // wrapping it again would re-encode an already-JSON body as a string.
  test('a body-carrying 4xx response is passed through untouched', () async {
    final res = await wrap(
      (_) => Response(
        422,
        body: jsonEncode({
          'error': {'code': 'CAMPAIGN_VALIDATION_FAILED', 'message': 'bad'},
        }),
        headers: {'content-type': 'application/json'},
      ),
    )(Request('POST', Uri.parse('http://localhost/x')));

    expect(res.statusCode, 422);
    final error = await errorBody(res);
    expect(error['code'], 'CAMPAIGN_VALIDATION_FAILED');
    expect(error['message'], 'bad');
    expect(
      error.containsKey('traceId'),
      isFalse,
      reason: 'the original body must be untouched, not re-stamped',
    );
  });

  // The pass-through test is body SHAPE, not the content-type header: a
  // route can write `{"error": {...}}` without ever setting content-type
  // explicitly, and shelf then reports `mimeType == null` for it. A
  // content-type-based check would have wrapped this, destroying the
  // handler's real error code.
  test('an envelope-shaped body passes through even without a '
      'content-type header', () async {
    final res = await wrap(
      (_) => Response(
        409,
        body: jsonEncode({
          'error': {'code': 'CONFLICT_STALE_VERSION', 'message': 'stale'},
        }),
      ),
    )(Request('POST', Uri.parse('http://localhost/x')));

    expect(res.statusCode, 409);
    final error = await errorBody(res);
    expect(error['code'], 'CONFLICT_STALE_VERSION');
    expect(
      error.containsKey('traceId'),
      isFalse,
      reason: 'shape alone is the test; this must not be re-wrapped',
    );
  });

  // The other half of the shape test: a JSON body with an
  // application/json content-type that is NOT shaped like the envelope
  // (no Map `error` key) must still be wrapped — a content-type-based
  // check would have passed this through untouched, producing exactly the
  // second error format this rule exists to prevent. The original body is
  // preserved, not discarded.
  test('a JSON body that is not envelope-shaped is wrapped, '
      'not passed through', () async {
    final res = await wrap(
      (_) => Response(
        400,
        body: jsonEncode({'unexpected': 'shape'}),
        headers: {'content-type': 'application/json'},
      ),
    )(Request('POST', Uri.parse('http://localhost/x')));

    expect(res.statusCode, 400);
    final error = await errorBody(res);
    expect(error['code'], 'BAD_REQUEST');
    expect(error['traceId'], isA<String>());
    expect(
      (error['details']! as Map)['originalBody'],
      contains('unexpected'),
      reason: 'the original body is preserved, not discarded',
    );
  });

  // shelf_router's own 404 sentinel (`Router.routeNotFound`) is plain text
  // ("Route not found", content-type text/plain) — not JSON at all. The
  // reviewer flagged this as the case the shape rule must still handle
  // gracefully: it is neither bodyless nor envelope-shaped, and must still
  // become a normal NOT_FOUND envelope.
  test('a plain-text 404 (shelf_router\'s "Route not found") becomes '
      'a NOT_FOUND envelope', () async {
    final res = await wrap((_) => Response.notFound('Route not found'))(
      Request('GET', Uri.parse('http://localhost/x')),
    );

    expect(res.statusCode, 404);
    final error = await errorBody(res);
    expect(error['code'], 'NOT_FOUND');
    expect((error['details']! as Map)['originalBody'], 'Route not found');
  });
}
