# 1. Feature Name

Service Health and Cross-System Reconciliation

## 2. Epic

- [Parent Epic: Integrity and Operational Control](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 9, 10 and 14

## 3. Goal

**Problem:** Sales Eco, media, identity, CRM and analytics failures can leave records committed in one system but missing in another. Generic green/red health does not identify affected records or safe remediation.

**Solution:** Provide dependency health, backlog age, stage-level reconciliation and idempotent replay/quarantine controls with correlation tracing.

**Impact:** Operators restore service without duplicating business records and can quantify affected workflows.

## 4. User Personas

- Operations/support engineer, integration operator, service owner and auditor.

## 5. User Stories

- As an operator, I want dependency and backlog health so that I know where processing stopped.
- As support, I want a correlation trail so that I can follow one record across systems.
- As an operator, I want safe replay/quarantine so that remediation cannot duplicate business outcomes.
- As a manager, I want affected counts and age so that incident impact is clear.

## 6. Requirements

### Functional Requirements

- Show health, latency, last success, backlog count/age and error class for required integrations.
- Reconcile profile requests, media uploads, provider jobs, CRM cases/decisions, notifications and analytics events by correlation/idempotency key.
- Classify records Processing, Delayed, Failed, Orphaned, Duplicate candidate, Reconciled or Quarantined.
- Provide scoped detail with masked payload summary and chronological attempts.
- Support authorized idempotent replay, re-query, quarantine, release and mark-reconciled actions.
- Require reason/confirmation for high-risk actions and audit all operator activity.
- Separate committed business outcomes from downstream notification/reporting failures.
- Surface incident/banner data to affected user journeys where appropriate.

### Non-Functional Requirements

- Avoid exposing credentials, signed URLs or raw sensitive payloads.
- Make replay bounded, idempotent and rate-limited.
- Keep health metrics time-stamped and identify monitoring gaps.
- Support accessible dense tables and large backlogs.

## 7. Acceptance Criteria

- **Given** upload succeeded but CRM case is absent, **when** reconciliation runs, **then** the missing stage and affected record are identified.
- **Given** replay is submitted twice, **when** the same idempotency key is used, **then** no duplicate attendance/case results.
- **Given** notification failed after approval, **when** health is viewed, **then** approval remains committed and notification is the only failed stage.
- **Given** an operator without restricted permission, **when** record detail opens, **then** sensitive payload and credentials remain unavailable.
- **Given** a quarantined record, **when** release is attempted, **then** reason, permission and current-version checks are required.

## 8. Out of Scope

- General enterprise observability replacement or arbitrary database editing.
- Manual creation of missing business decisions.
