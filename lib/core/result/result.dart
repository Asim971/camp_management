/// Lightweight Result type used across the data/domain boundary so failures
/// are values, not thrown exceptions. Keeps the domain layer pure.
sealed class Result<T> {
  const Result();

  R fold<R>(R Function(T value) onOk, R Function(Failure failure) onErr) =>
      switch (this) {
        Ok<T>(:final value) => onOk(value),
        Err<T>(:final failure) => onErr(failure),
      };

  bool get isOk => this is Ok<T>;
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}

/// Error taxonomy surfaced to the UI. Each maps to a specific, correction-first
/// message (Guideline §2.1) — never a generic "something went wrong".
enum FailureKind {
  network,
  timeout,
  unauthorized,
  forbidden, // RBAC scope
  notFound,
  conflict, // e.g. concurrent CRM decision / optimistic lock
  validation,
  offlineQueued, // work preserved locally, not an error to the user
  server,
  unknown,
}

class Failure {
  const Failure(this.kind, {this.message, this.code, this.correlationId});

  final FailureKind kind;
  final String? message;
  final String? code;
  final String? correlationId;

  @override
  String toString() => 'Failure($kind, code: $code, "$message")';
}
