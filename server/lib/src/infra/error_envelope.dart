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
/// *bodyless* response with status >= 400 in the same envelope.
///
/// That third rule exists because Task 5's `authenticate`/`requirePermission`
/// answer with bare `Response.unauthorized(null)` / `Response.forbidden(null)`
/// — responses, not exceptions — so the catch clauses below never see them.
/// Without this rule those two routes would be the only ones in the API
/// answering in a different error shape than everything else. A handler that
/// already wrote its own envelope (a body-carrying 4xx) is passed through
/// untouched — wrapping it again would double-encode the body.
///
/// Must run *inside* [correlation] (i.e. `correlation().addMiddleware
/// (errorEnvelope())` composition-wise, added second) so [correlationOf] can
/// already resolve an id when a handler throws.
Middleware errorEnvelope() {
  return (Handler inner) {
    return (Request request) async {
      final traceId = correlationOf(request);
      try {
        final response = await inner(request);
        if (response.statusCode < 400) return response;

        // A route that already wrote its own JSON envelope is recognised by
        // its content-type and passed through untouched — wrapping it again
        // would double-encode an already-JSON body. Everything else (shelf's
        // bare `Response.unauthorized(null)`/`forbidden(null)`, whose default
        // body is a plain-text reason phrase like "Unauthorized", or a truly
        // empty response) gets wrapped. The original body is never read: a
        // shelf response body is a single-subscription stream, so reading it
        // just to inspect it would leave nothing for shelf_io to send.
        if (response.mimeType == 'application/json') return response;

        return _envelopeResponse(
          status: response.statusCode,
          code: _codeForStatus(response.statusCode),
          message: _messageForStatus(response.statusCode),
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
