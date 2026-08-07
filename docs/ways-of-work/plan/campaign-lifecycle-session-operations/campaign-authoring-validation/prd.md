# 1. Feature Name

Campaign Authoring and Submission Validation

## 2. Epic

- [Parent Epic: Campaign Lifecycle and Session Operations](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 4-6 and 10

## 3. Goal

**Problem:** Campaign plans are incomplete when objective, audience, sessions, targets, budget and approver are collected inconsistently. Users need to save work safely while invalid plans must never enter approval.

**Solution:** Provide a persistent five-step wizard with local/server validation, schedule checks and a read-only review before idempotent submission.

**Impact:** Submission quality rises and approval rework falls without sacrificing draft flexibility.

## 4. User Personas

- Campaign creator/requester and campaign admin.

## 5. User Stories

- As a creator, I want to save an incomplete draft so that I can finish later.
- As a creator, I want specific validation and conflict guidance so that I can correct the plan.
- As a submitter, I want a final summary so that I know exactly what approvers receive.
- As a returned-plan owner, I want prior values and comments preserved so that correction is efficient.

## 6. Requirements

### Functional Requirements

- Implement steps for basics/objective, audience/territory, sessions/venue/geofence, targets/budget/approver and review.
- Create a unique Draft campaign and persist step progress and unsaved-state handling.
- Validate mandatory fields, configured options, dates/timezone, overlapping sessions, capacity, ownership, budget reference and approver.
- Identify organization-controlled/read-only fields and explain their source.
- Permit multiple sessions with field assignments and venue/geofence data.
- Show inline field errors plus a submission summary when multiple errors remain.
- Provide a read-only review with every submitted value and warning.
- Submit idempotently and transition only from Draft/Returned to Pending approval.
- Preserve returned comments and revised-field history.

### Non-Functional Requirements

- Preserve draft input across refresh and recoverable failures.
- Use domain-level validation independent of Flutter UI and server revalidation on submit.
- Meet keyboard, screen-reader and 200% zoom requirements.
- Prevent double submission and concurrent overwrite through version checks.

## 7. Acceptance Criteria

- **Given** an incomplete valid partial plan, **when** Save draft is selected, **then** progress persists without entering approval.
- **Given** overlapping sessions, **when** validation runs, **then** the conflict and affected windows are identified and submission is blocked.
- **Given** missing approver or budget required by configuration, **when** review opens, **then** the missing requirement is listed with a correction link.
- **Given** a valid reviewed draft, **when** submit is double-tapped or retried, **then** one Pending approval transition and audit event result.
- **Given** a returned campaign, **when** reopened, **then** approver comments and prior values remain available.

## 8. Out of Scope

- Approval decisions, participant registration and budget accounting.
- Full campaign creation on phone in MVP.
