# 1. Feature Name

Verification Decision, Return and Recapture

## 2. Epic

- [Parent Epic: Human-Led Attendance Verification](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 6, 10 and 12

## 3. Goal

**Problem:** A human review has no business value until its outcome, reason and downstream consequences are committed consistently. Concurrent decisions and recapture can otherwise overwrite history or produce duplicate final outcomes.

**Solution:** Provide reasoned approve, reject, return and escalate actions with effect preview, optimistic locking, attempt limits and immutable recapture lineage.

**Impact:** Final attendance facts are defensible and field correction remains traceable.

## 4. User Personas

- CRM verifier, CRM supervisor, field user receiving a return and auditor.

## 5. User Stories

- As a verifier, I want to see the effect of my outcome so that I understand attendance, reward and analytics consequences.
- As a verifier, I want mandatory reasons so that decisions are consistent and actionable.
- As a field user, I want a clear return reason and attempts remaining so that I recapture correctly.
- As a supervisor, I want controlled override/escalation so that exceptional cases are governed.

## 6. Requirements

### Functional Requirements

- Support Approve, Reject, Return for recapture and Escalate according to role/configuration.
- Require configured reason for every submitted outcome and note where policy requires.
- Preview resulting attendance status, reward eligibility, analytics inclusion and field notification.
- Commit one final decision using case version/optimistic locking and idempotency.
- Preserve reviewer, reason-code version, note, time, advisory context and correlation ID.
- For Return, preserve the attempt and notify field user with actionable reason and remaining attempts.
- Create each recapture as a new attempt linked to prior attempts/decisions.
- Enforce attempt limits and supervisor override with reason.
- Keep notification delivery separate from committed decision state.
- Expose advisory/human divergence for quality audit without treating it as automatic error.

### Non-Functional Requirements

- CRM remains final MVP decision authority; no bulk or automated final decisions.
- Prevent stale/concurrent duplicate decisions and recover safely from response loss.
- Maintain immutable decision/attempt lineage and least-privilege access.
- Meet keyboard, focus and screen-reader requirements for decision controls/confirmation.

## 7. Acceptance Criteria

- **Given** no reason, **when** any final outcome is submitted, **then** commit is blocked with a specific validation error.
- **Given** Approve, **when** confirmation is shown, **then** verified attendance, reward and analytics effects are stated before commit.
- **Given** Return, **when** committed, **then** prior evidence remains, attendance becomes Returned and field receives the actionable reason.
- **Given** another reviewer commits first, **when** a stale submission occurs, **then** no second decision is created and current outcome refreshes.
- **Given** attempt limit reached, **when** ordinary recapture is requested, **then** it is blocked unless an authorized supervisor override with reason commits.

## 8. Out of Scope

- Reward payment execution and punitive/fraud conclusions.
- Automated or bulk final approval.