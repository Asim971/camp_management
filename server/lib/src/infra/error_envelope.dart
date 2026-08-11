import 'dart:convert';
import 'dart:io';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:shelf/shelf.dart';

import 'correlation.dart';

/// A domain failure that carries its own wire [code] and HTTP [status].
///
/// Thrown from handlers; [errorEnvelope] is the single place that turns it
/// (or anything else that escapes a handler) into the documented JSON body.
class ApiException implements Exception {
  ApiException(this.code, {this.message, this.details});

  final ApiErrorCode code;
  final String? message;
  final Map<String, Object?>? details;

  /// Must agree with the client's own `mapDioError` table
  /// (`lib/core/network/dio_client.dart:67-86`): 401→unauthorized,
  /// 403→forbidden, 404→notFound, 409→conflict, 422→validation, ≥500→server.
  /// A mismatch here makes a typed `Failure` reach the UI as the wrong kind.
  int get status => switch (code) {
    ApiErrorCode.badRequest => 400,
    ApiErrorCode.unauthorized => 401,
    ApiErrorCode.forbidden => 403,
    ApiErrorCode.notFound => 404,
    ApiErrorCode.conflictStaleVersion => 409,
    ApiErrorCode.campaignInvalidTransition => 409,
    ApiErrorCode.segregationOfDutiesViolation => 403,
    ApiErrorCode.campaignValidationFailed => 422,
    ApiErrorCode.decisionReasonRequired => 422,
    ApiErrorCode.warningsUnacknowledged => 422,
    ApiErrorCode.idempotencyKeyRequired => 400,
    ApiErrorCode.idempotencyKeyReused => 422,
    // The IETF Idempotency-Key draft's answer for "this key's first request
    // is still being processed": 409, the same family conflictStaleVersion
    // and campaignInvalidTransition use, and the code the client's
    // mapDioError maps to FailureKind.conflict — the right shape for "come
    // back after the in-flight attempt resolves".
    ApiErrorCode.idempotencyKeyInFlight => 409,
    ApiErrorCode.internal => 500,
  };

  @override
  String toString() => 'ApiException(${code.wireValue}: $message)';
}

/// The fixed message an unexpected exception is reported with. The real
/// error is logged server-side (see [errorEnvelope]) and never leaves the
/// process: a raw exception message can name a column, a table, a file path
/// — reconnaissance a client has no legitimate use for. The trace id is the
/// bridge an operator uses to find the real error in the log.
const String _genericServerErrorMessage = 'An unexpected error occurred.';

/// Converts [ApiException] and any other exception escaping a handler into
/// the documented `{"error": {...}}` envelope, and additionally wraps any
/// response with status >= 400 that is not *already* shaped like that
/// envelope.
///
/// That third rule exists because Task 5's `authenticate`/`requirePermission`
/// answer with bare `Response.unauthorized(null)` / `Response.forbidden(null)`
/// — responses, not exceptions — so the catch clauses below never see them.
/// Without this rule those two routes would be the only ones in the API
/// answering in a different error shape than everything else. A handler that
/// already wrote its own envelope (a body-carrying 4xx) is passed through
/// untouched — wrapping it again would double-encode the body.
///
/// The pass-through test is *shape*, not content-type: a route can write
/// `{"error": {...}}` without ever setting `content-type` explicitly (shelf
/// then reports `mimeType == null`), and conversely a JSON body that happens
/// to have a `content-type: application/json` header but isn't shaped like
/// the envelope (no `error` object) must still be wrapped, or that route
/// becomes the second error format this rule exists to prevent. So the body
/// is read, decoded, and checked for `{"error": {...}}` shape; a body that
/// fails to decode as JSON, or doesn't have a Map `error` key, is wrapped,
/// with its original text preserved in `details.originalBody` rather than
/// discarded — shelf_router's 404 sentinel (`Route not found`, plain text)
/// takes exactly this path and becomes a normal `NOT_FOUND` envelope. A
/// shelf response body is a single-subscription stream, so once read it is
/// re-attached via `response.change(body: bytes)` for the pass-through case
/// — returning the original, now-drained response would leave shelf_io
/// nothing to send.
///
/// Must run *inside* [correlation] (i.e. `correlation().addMiddleware
/// (errorEnvelope())` composition-wise, added second) so [correlationOf] can
/// already resolve an id when a handler throws.
///
/// Mount this at the *top level only* — never inside a sub-router that gets
/// `Router.mount`ed into another. `shelf_router`'s nested-router fall-through
/// depends on `Router.routeNotFound`'s sentinel *object identity*
/// (`router.dart:185`: `if (response != routeNotFound)`); wrapping it here
/// would replace that sentinel with an ordinary `Response` and silently
/// break fall-through to the next mounted router.
Middleware errorEnvelope() {
  return (Handler inner) {
    return (Request request) async {
      final traceId = correlationOf(request);
      try {
        final response = await inner(request);
        if (response.statusCode < 400) return response;

        final bodyBytes = <int>[];
        await for (final chunk in response.read()) {
          bodyBytes.addAll(chunk);
        }

        if (_isEnvelopeShaped(bodyBytes)) {
          return response.change(body: bodyBytes);
        }

        return _envelopeResponse(
          status: response.statusCode,
          code: _codeForStatus(response.statusCode),
          message: _messageForStatus(response.statusCode),
          details: bodyBytes.isEmpty
              ? null
              : {'originalBody': _truncated(bodyBytes)},
          traceId: traceId,
        );
      } on ApiException catch (e) {
        return _envelopeResponse(
          status: e.status,
          code: e.code,
          message: e.message ?? _messageForStatus(e.status),
          details: e.details,
          traceId: traceId,
        );
      } on Object catch (error, stackTrace) {
        // The real error, with its stack trace, goes to the server log —
        // never to the client. See _genericServerErrorMessage above.
        stderr.writeln(
          'Unhandled error (traceId=$traceId): $error\n$stackTrace',
        );
        return _envelopeResponse(
          status: 500,
          code: ApiErrorCode.internal,
          message: _genericServerErrorMessage,
          traceId: traceId,
        );
      }
    };
  };
}

/// True iff [bytes] decode as JSON shaped like this file's own envelope:
/// a top-level object with a Map `error` key. Anything else — not JSON at
/// all, JSON that isn't an object, an `error` key that isn't a Map, or no
/// `error` key — is not "already an envelope" and must be wrapped.
bool _isEnvelopeShaped(List<int> bytes) {
  if (bytes.isEmpty) return false;
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    return false;
  }
  return decoded is Map && decoded['error'] is Map;
}

/// [bytes] decoded permissively and capped, for `details.originalBody`. A
/// handler's non-envelope error body is not secret the way an unhandled
/// exception's message is (see [_genericServerErrorMessage]) — it is that
/// handler's own deliberate output — but it is still capped so a handler
/// that (mis)behaves and returns something huge can't bloat every wrapped
/// response.
String _truncated(List<int> bytes) {
  const maxLength = 500;
  final text = utf8.decode(bytes, allowMalformed: true);
  return text.length > maxLength ? '${text.substring(0, maxLength)}…' : text;
}

Response _envelopeResponse({
  required int status,
  required ApiErrorCode code,
  required String message,
  required String traceId,
  Map<String, Object?>? details,
}) => Response(
  status,
  body: jsonEncode({
    'error': {
      'code': code.wireValue,
      'message': message,
      if (details != null) 'details': details,
      'traceId': traceId,
    },
  }),
  headers: {'content-type': 'application/json'},
);

ApiErrorCode _codeForStatus(int status) => switch (status) {
  401 => ApiErrorCode.unauthorized,
  403 => ApiErrorCode.forbidden,
  404 => ApiErrorCode.notFound,
  >= 400 && < 500 => ApiErrorCode.badRequest,
  _ => ApiErrorCode.internal,
};

String _messageForStatus(int status) => switch (status) {
  401 => 'Authentication is required.',
  403 => 'You do not have permission to perform this action.',
  404 => 'The requested resource was not found.',
  >= 400 && < 500 => 'The request could not be processed.',
  _ => _genericServerErrorMessage,
};
