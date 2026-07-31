# 1. Feature Name

Audit, Retention and Restricted Settings Administration

## 2. Epic

- [Parent Epic: Configuration, Audit and Policy Administration](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 10, 12 and 14

## 3. Goal

**Problem:** Audit and retention policies must prove who did what while minimizing sensitive data and preventing administrators from viewing secret values. Retention execution must be observable without enabling ad hoc deletion.

**Solution:** Provide scoped audit search/export, retention-policy status and restricted-setting metadata with dual-control actions where required.

**Impact:** Governance evidence is available and privacy/security controls remain enforceable.

## 4. User Personas

- Auditor, privacy/security admin, Org/BMD admin and authorized legal/operations reviewer.

## 5. User Stories

- As an auditor, I want correlated immutable events so that I can reconstruct a workflow.
- As a privacy admin, I want retention execution and holds visible so that lifecycle compliance is monitored.
- As an ordinary admin, I want restricted settings identified but masked so that privilege boundaries are clear.
- As an authorized exporter, I want governed exports so that audit evidence leaves the system safely.

## 6. Requirements

### Functional Requirements

- Search audit events by time, actor, subject/case, action, module, outcome, scope and correlation ID.
- Show event metadata, before/after references or masked diffs without storing secrets/media payloads.
- Provide tamper-evident retention and source/ingestion status for audit records.
- Show retention policies for evidence, queue data, audit, exports and derived analytics with effective versions.
- Display scheduled/last execution, eligible/held/deleted/failed counts and failure remediation.
- Support authorized legal hold/release and exceptional actions with reason and dual approval where configured.
- Show restricted integration/threshold setting metadata while masking values and credentials.
- Produce scoped, time-limited audit exports with purpose, approval, watermark and access logging.

### Non-Functional Requirements

- Enforce least privilege and audit all searches, reveals, holds and exports.
- Keep audit records append-only/tamper-evident under policy.
- Prevent credentials, signed URLs, biometric media and full identity values entering general audit/export.
- Support large result sets through async export and accessible virtualized tables.

## 7. Acceptance Criteria

- **Given** a correlation ID, **when** searched, **then** authorized cross-module events appear chronologically without secret payloads.
- **Given** an expired evidence item under no hold, **when** retention executes, **then** deletion outcome/count is recorded without exposing media.
- **Given** an active legal hold, **when** retention reaches the item, **then** deletion is skipped and hold authority is traceable.
- **Given** a user without restricted-value permission, **when** settings are viewed/exported, **then** values and credentials remain masked.
- **Given** an audit export, **when** generated, **then** scope, purpose, approver, expiry and download access are audited.

## 8. Out of Scope

- Defining statutory retention durations or acting as an enterprise records-management system.
- Revealing secrets/credentials or allowing arbitrary data deletion.