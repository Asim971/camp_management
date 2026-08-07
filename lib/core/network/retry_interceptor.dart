import 'package:dio/dio.dart';

import '../sync/backoff.dart';
import '../trace/trace_id.dart';
import 'trace_options.dart';

/// Retry budget for foreground API calls.
///
/// Deliberately NOT the sync engine's policy. Sync tolerates `maxRetries: 8`
/// over up to five minutes because a field upload can wait; a foreground call
/// blocking the UI that long is a bug. Worst case here is under ~7s added.
const BackoffPolicy foregroundRetryPolicy = BackoffPolicy(
  base: Duration(milliseconds: 300),
  maxDelay: Duration(seconds: 3),
  maxRetries: 2,
);

const String _attemptExtraKey = 'retryAttempt';

Future<void> _wait(Duration d) => Future<void>.delayed(d);

/// Retries transient transport and overload failures.
///
/// Registered LAST so [AuthInterceptor] gets first refusal on a 401 - reversed,
/// this would spend its budget re-sending a request with a stale token.
///
/// Retries are re-dispatched through the same [Dio], so the full interceptor
/// chain (including auth) runs again. Recursion is bounded by an attempt
/// counter carried in `RequestOptions.extra`.
class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    required this._dio,
    this._policy = foregroundRetryPolicy,
    this._delay = _wait,
  });

  final Dio _dio;
  final BackoffPolicy _policy;
  final Future<void> Function(Duration) _delay;

  /// Transient by nature: worth another attempt.
  ///
  /// 500 and 501 are excluded on purpose - a 500 may have committed a write and
  /// no server contract says otherwise, so a blind retry risks a duplicate.
  static const Set<int> _retryableStatus = {429, 502, 503, 504};

  static const Set<DioExceptionType> _retryableTypes = {
    DioExceptionType.connectionError,
    DioExceptionType.connectionTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.sendTimeout,
  };

  static const Set<String> _safeMethods = {'GET', 'HEAD'};

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final attemptValue = options.extra[_attemptExtraKey];
    final attempt = attemptValue is int ? attemptValue : 0;

    if (!_isRetryable(err) ||
        !_isSafeToRetry(options) ||
        _policy.shouldGiveUp(attempt)) {
      return handler.next(err);
    }

    await _delay(_retryAfter(err) ?? _backoff(options, attempt));

    options.extra[_attemptExtraKey] = attempt + 1;
    try {
      final response = await _dio.fetch<dynamic>(options);
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  bool _isRetryable(DioException err) {
    final status = err.response?.statusCode;
    if (status != null) return _retryableStatus.contains(status);
    return _retryableTypes.contains(err.type);
  }

  /// Safe methods retry freely. Everything else retries ONLY with an explicit
  /// idempotency key: HTTP method semantics alone are not a guarantee this
  /// server honours, and a duplicate write is worse than a surfaced error.
  bool _isSafeToRetry(RequestOptions options) {
    if (_safeMethods.contains(options.method.toUpperCase())) return true;
    final key = options.extra[idempotencyKeyExtraKey];
    return key is String && key.isNotEmpty;
  }

  /// `Retry-After` in delta-seconds form. The HTTP-date form is not honoured:
  /// it requires trusting the client clock, which on field devices is exactly
  /// what we avoid elsewhere. An unparseable value falls back to backoff.
  Duration? _retryAfter(DioException err) {
    final raw = err.response?.headers.value('retry-after');
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    return seconds == null ? null : Duration(seconds: seconds);
  }

  /// Seeds jitter from the trace id so a given call jitters reproducibly in
  /// tests while different calls still de-synchronise across devices.
  Duration _backoff(RequestOptions options, int attempt) {
    final trace = options.extra[traceIdExtraKey];
    final seed = jitterSeedFor(trace is TraceId ? trace.value : options.path);
    return _policy.delayFor(attempt, jitterSeed: seed);
  }
}
