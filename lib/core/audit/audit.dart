/// Client-side audit event emission (Guideline §12, PRD FR-015). The server is
/// the authoritative audit store; the client emits structured events with a
/// correlation ID so a user action can be traced end-to-end. Sensitive views
/// (photo open, NID reveal) MUST emit an event before the value is shown.
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
}

class AuditEvent {
  const AuditEvent({
    required this.action,
    required this.entity,
    required this.entityId,
    required this.correlationId,
    this.remarks,
  });

  final AuditAction action;
  final String entity;
  final String entityId;
  final String correlationId;
  final String? remarks;
}

/// Emits [AuditEvent]s. The concrete implementation batches and posts to the
/// audit endpoint; failures are retried and never block the user workflow.
abstract interface class AuditSink {
  Future<void> emit(AuditEvent event);
}
