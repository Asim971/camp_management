# 1. Feature Name

Durable Offline Synchronization and Attendance Status

## 2. Epic

- [Parent Epic: Offline Field Attendance Capture](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 9, 10 and 14

## 3. Goal

**Problem:** Weak networks and app restarts can lose evidence or make users recapture unnecessarily. Capture, upload, processing and approval are distinct facts that a single success/failure label cannot represent.

**Solution:** Persist encrypted evidence and sync tasks durably, upload idempotently with bounded retry, and show the complete attendance lineage and actionable queue state.

**Impact:** Committed captures survive disruption, duplicates remain zero and users understand what needs action.

## 4. User Personas

- Field user, field supervisor and support operator.

## 5. User Stories

- As a field user, I want captures to survive restart so that field work is never lost.
- As a field user, I want capture success separated from upload success so that I do not recapture during delay.
- As a field user, I want retry/error detail so that I can act only when intervention is required.
- As support, I want idempotency and attempt history so that replay is safe and diagnosable.

## 6. Requirements

### Functional Requirements

- Persist attendance draft, encrypted media reference and sync task atomically before reporting capture success.
- Generate stable idempotency keys and deduplicate replay server-side.
- Schedule connectivity-aware upload with bounded exponential backoff and background continuation where supported.
- Request short-lived upload authorization, transfer with progress and confirm server receipt.
- Resume after process kill, device restart and network transition.
- Poll/subscribe to Pending sync, Match processing, CRM review, Approved, Rejected and Returned states.
- Show queue count, last successful sync, captured time, retry count, state and action.
- Support Retry, Pause, View error and permission-controlled Discard.
- Never offer recapture solely for upload delay; offer it only for an explicit Returned decision/policy.
- Retain attempt lineage and reconcile notification/status delivery gaps.

### Non-Functional Requirements

- Lose zero atomically committed captures in supported failure-injection tests.
- Create zero duplicate attendance records under retry, double tap or restart.
- Encrypt local evidence with platform-protected keys and remove it according to confirmed retention lifecycle.
- Keep queue usable offline and accessible on supported mobile sizes.
- Bound battery/network use and avoid unbounded retry loops.

## 7. Acceptance Criteria

- **Given** a committed offline capture, **when** the app is killed and reopened, **then** the queue contains the same task and encrypted evidence.
- **Given** upload succeeds but confirmation response is lost, **when** retry occurs, **then** server deduplication returns the same attendance record.
- **Given** synchronization is delayed, **when** the queue is viewed, **then** Pending sync and retry context are shown without a recapture prompt.
- **Given** connectivity returns, **when** scheduling resumes, **then** eligible tasks drain in order and status advances without user duplication.
- **Given** an explicit Returned decision, **when** status refreshes, **then** reason and permitted recapture path appear while prior attempt remains.

## 8. Out of Scope

- Verification decision logic and provider matching.
- Arbitrary user deletion of committed server evidence.
