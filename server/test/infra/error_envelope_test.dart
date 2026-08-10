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

    expect(await statusFor(ApiErrorCode.unauthorized), 401);
    expect(await statusFor(ApiErrorCode.forbidden), 403);
    expect(await statusFor(ApiErrorCode.notFound), 404);
    expect(await statusFor(ApiErrorCode.conflictStaleVersion), 409);
    expect(await statusFor(ApiErrorCode.campaignInvalidTransition), 409);
    expect(await statusFor(ApiErrorCode.campaignValidationFailed), 422);
    expect(await statusFor(ApiErrorCode.decisionReasonRequired), 422);
    expect(await statusFor(ApiErrorCode.warningsUnacknowledged), 422);
    expect(await statusFor(ApiErrorCode.idempotencyKeyReused), 422);
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
}
