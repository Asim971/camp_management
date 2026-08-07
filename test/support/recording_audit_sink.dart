import 'package:acsl_campaign/core/audit/audit.dart';
import 'package:acsl_campaign/core/result/result.dart';

/// [AuditSink] that only records, for tests asserting *that* something was
/// audited rather than how it was transported.
class RecordingAuditSink implements AuditSink {
  final List<AuditEvent> events = [];

  @override
  Future<void> emit(AuditEvent event) async => events.add(event);

  @override
  Future<Result<T>> revealAudited<T>(
    AuditEvent event,
    Future<T> Function() reveal,
  ) async {
    events.add(event);
    return Ok(await reveal());
  }
}
