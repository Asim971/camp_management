# 1. Epic Name

Integrity and Operational Control

## 2. Goal

**Problem:** Duplicate attendance, reused media, unusual device activity, geofence exceptions, quality failures, sync backlog and integration gaps can undermine trust in campaign results. A composite fraud score would be difficult to explain, audit or contest, while hidden service failures can leave teams acting on incomplete data. Operations teams need facts, ownership and recovery paths.

**Solution:** Provide an explainable integrity and service-health control center with raw observable signals, investigation workflow, reconciliation queues, sensitive-access monitoring and retry/escalation actions. Treat false positive as a first-class resolution and keep operational degradation separate from accusations about a person.

**Impact:** Supervisors can resolve integrity and data-quality issues before they distort verification or analytics, while security and audit teams retain defensible evidence and access history.

## 3. User Personas

- **CRM Supervisor:** Reviews verification-quality and override signals.
- **Security/Integrity Analyst:** Investigates suspicious but non-conclusive facts.
- **Support/Operations User:** Resolves sync, media and integration failures.
- **Data/Reconciliation Operator:** Resolves profile and canonical-order gaps.
- **Auditor:** Reviews evidence, access and resolution history.

## 4. High-Level User Journeys

1. A supervisor opens an exception-first view of reused photo hash, duplicate attendance, device burst, geofence and quality/PAD signals.
2. The user opens an investigation that states exactly what was observed, scope, age, owner and linked records.
3. The user assigns, acknowledges, resolves or marks false positive with reason and retained evidence.
4. Operations reviews Sales Eco, order, verification and media service health and retries eligible failures.
5. Reconciliation users resolve pending profile requests, expired uploads and orders without canonical IDs.
6. Auditors review sensitive evidence access, reveals and exports by actor, case and correlation ID.

## 5. Business Requirements

### Functional Requirements

- Surface explainable signals for reused photo/hash, duplicate attendance, device burst, geofence exception, poor quality/PAD, manual override and manual route.
- State observed facts, thresholds/config version, affected records, session/device scope and time window; do not infer guilt.
- Provide investigation states Open, Under review, Resolved and False positive with owner, reason and audit history.
- Support case opening, assignment, escalation, acknowledgement and controlled evidence export.
- Link signals to attendance, verification and audit facts without exposing evidence to unauthorized roles.
- Track machine-advisory/human-decision divergence as a quality-audit signal rather than automatically an error.
- Show integration health for carpenter master, order facts, verification provider and media store with last success and degradation detail.
- Show captures awaiting upload, failures requiring help, pending profile requests and orders lacking canonical ID.
- Distinguish delayed/recovering work from lost work; only failures needing intervention should demand human action.
- Retry/reconcile eligible integration jobs idempotently and retain all attempts.
- Exclude unresolved canonical-order gaps from affected totals and expose the reconciliation effect.
- Provide a sensitive-access log with actor, action, subject, case, time and correlation ID.
- Feed resolved/false-positive outcomes back into governed threshold review without silently rewriting historical decisions.
- Notify owners of assigned or breached work while keeping notification failure non-authoritative.

### Non-Functional Requirements

- Prohibit composite fraud scores unless a separately approved explainability and governance policy exists.
- Use factual, neutral and non-accusatory labels throughout.
- Enforce least-privilege evidence, export and raw-payload access and audit every access.
- Preserve immutable investigation and reconciliation history, including false positives and failed retries.
- Make service freshness and degraded state visible and avoid false healthy/zero states.
- Ensure retries are idempotent and cannot duplicate attendance, profile or order outcomes.
- Support high-volume exception lists with action-priority sorting and accessible table behavior.
- Restrict phone views to monitoring; sensitive evidence review remains web/tablet under permission.

## 6. Success Metrics

| KPI | Target |
|---|---|
| Integrity signals with explicit observed fact and source/config context | 100% |
| Composite opaque fraud scores used | 0 |
| Sensitive access/export actions logged | 100% |
| Replay/retry operations creating duplicate business outcomes | 0 |
| Open operational exceptions with owner and next action | 100% |
| Unresolved canonical-order gaps included in executive totals | 0 |
| False positives preserved as explicit outcomes | 100% |

## 7. Out of Scope

- Automated accusation, disciplinary action or legal conclusion.
- Replacing enterprise SIEM, observability or incident-management platforms.
- Silent mutation of verification decisions or historical facts.
- General infrastructure monitoring unrelated to the campaign value chain.
- Phone-based sensitive image investigation.
- Autonomous threshold tuning.

## 8. Business Value

**High.** The epic protects confidence in verified attendance and commercial reporting, shortens recovery from operational failures and provides defensible handling of integrity concerns without unsafe automated accusations.

## Source Traceability and Dependencies

- **Requirements:** Guideline CM-FR-087 and CM-FR-090 to CM-FR-095; original PRD duplicate, media, security and audit risks.
- **Design ownership:** A-03 Integrity and operations dashboard.
- **Depends on:** Audit/event stream, attendance/verification lineage, sync/media telemetry, integration jobs and canonical-order reconciliation.
- **Hands off to:** Verification quality audit, analytics exclusions and configuration change proposals.
