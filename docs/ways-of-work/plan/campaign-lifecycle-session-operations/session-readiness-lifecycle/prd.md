# 1. Feature Name

Session Readiness and Operational Lifecycle

## 2. Epic

- [Parent Epic: Campaign Lifecycle and Session Operations](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 5, 7 and 9

## 3. Goal

**Problem:** An approved campaign is not automatically executable. Missing assignments, venue/geofence or attendance windows discovered at event time can waste the session, while closure must not erase pending sync or verification work.

**Solution:** Provide session cards, readiness evaluation and controlled start, pause, close and campaign-completion transitions.

**Impact:** Sessions start prepared and operational backlog remains visible through closure.

## 4. User Personas

- Campaign admin, field organizer, authorized field user and management viewer.

## 5. User Stories

- As an organizer, I want blocking and optional readiness checks separated so that I know what must be fixed.
- As an authorized operator, I want to start or close only within policy so that attendance windows remain controlled.
- As management, I want session counts by lineage stage so that captured is not confused with approved.
- As support, I want backlog preserved after closure so that unresolved work is recoverable.

## 6. Requirements

### Functional Requirements

- Show session date, venue, capacity, registered, captured, pending sync, in-review and approved counts.
- Evaluate assignments, venue/geofence, attendance window, capacity, reference coverage and required service/config readiness.
- Label checks Blocking, Warning or Pass and link each failure to an authorized correction.
- Allow documented authorized override only for configured checks and reasons.
- Start/open capture only for approved campaigns passing all non-overridable blocks and time policy.
- Support pause/resume, capture close and completed states under permission.
- Prevent new captures after closure except configured authorized late-capture route.
- Allow campaign completion while retaining visible sync, verification and reconciliation backlog.
- Maintain session/campaign audit and counts that reconcile to underlying records.

### Non-Functional Requirements

- Evaluate authoritative server configuration/version and avoid stale client-only readiness.
- Use idempotent transitions and optimistic concurrency.
- Show delayed counts/freshness rather than false zero.
- Support accessible web cards and handoff to mobile readiness.

## 7. Acceptance Criteria

- **Given** no assigned field user and missing geofence, **when** readiness runs, **then** both are blocking and Start is unavailable.
- **Given** low reference coverage configured as warning, **when** all blocks pass, **then** Start remains available with the warning visible.
- **Given** an authorized override, **when** submitted, **then** reason, actor and governing rule are audited before transition.
- **Given** capture is closed, **when** a normal capture is attempted, **then** it is rejected without changing existing records.
- **Given** pending sync or CRM cases, **when** campaign completion occurs, **then** backlog remains visible and continues processing.

## 8. Out of Scope

- Device-local readiness checks owned by mobile field readiness.
- Attendance evidence capture or final verification.
