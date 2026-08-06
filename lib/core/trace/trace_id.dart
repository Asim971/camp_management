import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// Identifies one user action end-to-end (Architecture §12, PRD FR-015).
///
/// A single id is minted per user action and shared by the audit row and every
/// HTTP request that action causes, so a support query can be traced from the
/// client through the server logs. Requests made outside an action scope get a
/// fresh per-request id from [CorrelationIdInterceptor], so nothing is
/// untraceable.
///
/// Deliberately a pure type: this library imports no Dio and no app code, so
/// both `core/network` and `core/audit` can depend on it without depending on
/// each other.
final class TraceId {
  const TraceId.of(this.value);

  factory TraceId.generate() => TraceId.of(_uuid.v4());

  final String value;

  @override
  bool operator ==(Object other) => other is TraceId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
