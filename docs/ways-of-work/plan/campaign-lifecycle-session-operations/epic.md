# 1. Epic Name

Campaign Lifecycle and Session Operations

## 2. Goal

**Problem:** Campaign planning and execution currently depend on fragmented lists, informal approvals and unclear readiness criteria. Business users cannot reliably determine what is approved, what changed, whether a session can start, or which action is required next. This weakens segregation of duties and leaves campaign outcomes without a trustworthy operational history.

**Solution:** Provide a governed web workflow for campaign creation, validation, approval, session readiness, activation, pause, closure and completion. Keep lifecycle status, ownership, warnings and audit history visible, and preserve correction cycles without losing prior submissions or decisions.

**Impact:** Campaigns move through a consistent controlled process, approvers make informed decisions, and field execution begins only when required business and operational conditions are satisfied.

## 3. User Personas

- **Campaign Creator/Requester:** Creates and revises campaign plans.
- **Campaign Admin/Marketing:** Manages campaign lists, sessions, registrations and exceptions.
- **Campaign Approver:** Reviews scope, targets, budget reference and warnings under segregation of duties.
- **Field Organizer:** Prepares assigned sessions and resolves readiness issues.
- **Management Viewer:** Monitors lifecycle progress and execution status.

## 4. High-Level User Journeys

1. A creator saves a five-step draft covering basics, audience/territory, sessions/venue, targets/budget and review.
2. The system validates required fields, schedule conflicts, ownership, capacity, approver and organization configuration.
3. The creator submits a read-only summary; an eligible approver approves, returns or rejects it with traceable context.
4. A returned campaign highlights changed fields on resubmission while retaining the approval history.
5. An approved campaign opens registration and session readiness; blocking checks must pass before activation.
6. Authorized operators start, pause, close and complete sessions/campaigns while verification backlog remains intact.

## 5. Business Requirements

### Functional Requirements

- Create campaigns with unique ID, type, title, organization, owner, objective, audience segment, territory, product focus, dates and status.
- Save incomplete work as Draft and preserve it across sessions without allowing invalid submission.
- Configure one or more sessions with timezone-aware date/window, venue, capacity, field assignments and geofence.
- Capture targets, budget reference, approval route and configured campaign controls.
- Validate mandatory fields, overlapping schedules, territory/ownership conflicts, capacity and missing approvers.
- Present a final read-only summary before submission and identify organization-controlled fields.
- Enforce lifecycle transitions using the controlled campaign vocabulary: Draft, Pending approval, Returned, Approved, Active, Paused, Completed and Cancelled.
- Provide campaign list search, filters, action-priority sorting and permission-aware row actions.
- Enforce segregation of duties; the campaign creator cannot approve where policy prohibits self-approval.
- Support Approve, Return for correction and Reject; require reason for return/reject and acknowledgement of critical warnings before approval.
- Highlight fields changed since the prior reviewed version and retain every submission and decision.
- Open registration and readiness after approval; do not make approval itself equivalent to an active capture session.
- Evaluate session readiness for assignment, venue/geofence, attendance window, capacity, reference coverage and relevant service/device conditions.
- Distinguish blocking failures from optional warnings and provide a corrective action or authorized override.
- Show campaign detail tabs for Overview, Sessions, Registrations, Attendance, Analytics and Audit.
- Start, pause, close and complete sessions/campaigns only under role, time-window and readiness rules.
- Allow campaign completion while preserving unresolved verification, sync and reconciliation work as visible backlog.

### Non-Functional Requirements

- Record actor, time, old/new state, reason, acknowledgements and correlation ID for every material transition.
- Prevent duplicate submissions and transitions through idempotency and optimistic concurrency.
- Keep status, owner, SLA/age and next action visible in dense lists and responsive card variants.
- Preserve drafts and user-entered data through validation and recoverable service failures.
- Use locale-aware date/time controls and always show timezone for session windows.
- Meet WCAG 2.2 AA, keyboard and 200% zoom requirements for supported web flows.
- Enforce role plus organization/territory scope server-side as well as in the client.
- Show delayed or partial dependent data explicitly rather than as zero or complete.

## 6. Success Metrics

| KPI | Target |
|---|---|
| Campaigns using only valid controlled lifecycle transitions | 100% |
| Submitted campaigns with complete required scope, session and approval data | 100% |
| Approval decisions with required reason/acknowledgement evidence | 100% |
| Sessions activated with unresolved blocking readiness checks | 0 |
| Median submission-to-decision cycle time | Baseline in pilot; improve by 20% after stabilization |
| Approved campaigns reaching execution or documented cancellation | At least 95% |
| Lost campaign draft data after recoverable errors | 0 |

## 7. Out of Scope

- Participant master creation, bulk row resolution and profile synchronization.
- Attendance photo capture, media upload and offline queue behavior.
- Final identity verification decisions.
- Incentive payout, gift settlement, accounting ledger or procurement.
- Automated campaign recommendations or autonomous approval.
- Logistics, truck hiring or inbound logistics workflows.

## 8. Business Value

**High.** This epic replaces informal campaign governance with a traceable operating process and is the entry point for every downstream registration, attendance, verification and analytics outcome.

## Source Traceability and Dependencies

- **Requirements:** Original PRD G1, F1, F7-F8, FR-001, FR-002, FR-006-FR-008, FR-012; guideline CM-FR-001 to CM-FR-014.
- **Design ownership:** W-02 Campaign list, W-03 Create/edit wizard, W-04 Approval, W-05 Campaign detail and sessions.
- **Depends on:** Shared experience controls, organization/RBAC, campaign configuration and audit contracts.
- **Hands off to:** Participant registration, field attendance and campaign analytics.
