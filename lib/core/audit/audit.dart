import '../result/result.dart';
import '../trace/trace_id.dart';

/// Client-side audit event emission (Guideline §12, PRD FR-015). The server is
/// the authoritative audit store; the client emits structured events with a
/// correlation ID so a user action can be traced end-to-end. Sensitive views
/// (photo open, NID reveal) MUST emit an event before the value is shown - see
/// [AuditSink.revealAudited], which enforces that structurally.
enum AuditAction {
  campaignCreated,
  campaignSubmitted,
  campaignApproved,
  campaignReturned,
  campaignRejected,
  participantRegistered,
  bulkImportCommitted,
  attendanceCaptured,
  verificationDecided,
  sensitiveMediaViewed,
  nidRevealed,
  configChanged,
  exportPerformed,

  /// The evidence-encryption key could not be read and a new one was generated.
  /// Every piece of evidence encrypted under the previous key is now
  /// undecryptable, so this must never look like a normal first run.
  evidenceKeyRotated,
}

class AuditEvent {
  const AuditEvent({
    required this.action,
    required this.entity,
    required this.entityId,
    required this.correlationId,
    required this.actorId,
    this.remarks,
  });

  final AuditAction action;
  final String entity;
  final String entityId;
  final TraceId correlationId;

  /// Who performed the action, captured at emit time. Never inferred at flush
  /// time: field devices are shared, so an event captured offline by one user
  /// can flush after a different user has logged in.
  final String actorId;

  final String? remarks;
}

/// Emits [AuditEvent]s. The concrete implementation buffers durably and posts
/// to the audit endpoint; failures are retried and never block the user
/// workflow - with one deliberate exception, [revealAudited].
abstract interface class AuditSink {
  /// Records [event] durably and returns. Transport happens later, so an audit
  /// outage never blocks a user action.
  Future<void> emit(AuditEvent event);

  /// Records [event], waits for the server to acknowledge it, and only then
  /// invokes [reveal].
  ///
  /// The reveal is passed in rather than performed by the caller after checking
  /// a returned `Result`, because a `Result` the caller must remember to check
  /// fails OPEN the first time someone forgets - and "someone forgot" is the
  /// normal failure mode for a compliance control. Structuring it this way makes
  /// showing the value without a recorded access impossible.
  ///
  /// Returns `Err` without invoking [reveal] if the event cannot be recorded.
  Future<Result<T>> revealAudited<T>(
    AuditEvent event,
    Future<T> Function() reveal,
  );
}
