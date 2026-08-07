# 1. Feature Name

Campaign Approval, Return and Correction

## 2. Epic

- [Parent Epic: Campaign Lifecycle and Session Operations](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 7, 10 and 12

## 3. Goal

**Problem:** Approvers need complete scope and risk context, while self-approval, unacknowledged warnings and lost correction history weaken governance. Full document diffs can also hide the few material changes in a resubmission.

**Solution:** Provide a decision workspace with segregation-of-duties enforcement, warning acknowledgement, inline changed-field markers and reasoned approve/return/reject outcomes.

**Impact:** Decisions become faster, deliberate and auditable.

## 4. User Personas

- Campaign approver, configured Org/BMD admin and campaign submitter receiving corrections.

## 5. User Stories

- As an approver, I want the submitted plan and risk warnings together so that I can decide confidently.
- As an approver, I want changed fields highlighted on resubmission so that I can focus review.
- As a submitter, I want actionable return comments so that I can correct without losing work.
- As an auditor, I want acknowledgements and decisions preserved so that governance is provable.

## 6. Requirements

### Functional Requirements

- Show submitted objective, scope, sessions, targets, budget reference and approval history read-only.
- Enforce role, scope and segregation of duties before decision controls are available.
- Display critical warnings and require explicit acknowledgement before Approve.
- Support Approve, Return for correction and Reject with mandatory configured reason for return/reject.
- Record optional/required note according to reason policy and show downstream effect.
- Mark fields changed since the prior reviewed version and offer a changed-only view.
- Return a correctable campaign without deleting draft data; reject closes it under policy.
- Apply decisions idempotently with optimistic concurrency.
- Notify the submitter after commit and retain notification failure separately.

### Non-Functional Requirements

- Record reviewer, decision, reason, warning acknowledgements, version, time and correlation ID.
- Prevent campaign data from changing inside the decision view.
- Meet keyboard/focus and responsive stacked-decision requirements.
- Never allow a stale reviewer to overwrite a completed decision.

## 7. Acceptance Criteria

- **Given** the campaign creator is also the current user under SoD policy, **when** approval opens, **then** decision controls are unavailable and the reason is shown.
- **Given** unacknowledged critical warnings, **when** Approve is selected, **then** approval remains blocked while return/reject stay available.
- **Given** a return decision, **when** submitted without reason, **then** no transition occurs and a specific error is shown.
- **Given** a resubmission, **when** changed-only is selected, **then** every changed submitted field and no unchanged field is shown.
- **Given** another reviewer has decided, **when** a stale decision is submitted, **then** it is rejected and the completed decision is refreshed.

## 8. Out of Scope

- Participant-by-participant approval unless separately configured later.
- Editing campaign content in the approval view.
