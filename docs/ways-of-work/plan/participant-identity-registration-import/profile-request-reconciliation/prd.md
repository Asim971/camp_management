# 1. Feature Name

Sales Eco Profile Request and Reconciliation

## 2. Epic

- [Parent Epic: Participant Identity, Registration and Bulk Import](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 9 and 10

## 3. Goal

**Problem:** A missing carpenter profile cannot justify a local shadow master, but abandoning the registration request loses campaign intent. Integration outages and delayed stewardship need visible, recoverable state.

**Solution:** Submit a minimal Sales Eco profile request, track `Pending profile sync`, and reconcile the request to the authoritative identity when available.

**Impact:** Campaign work continues without corrupting master-data ownership.

## 4. User Personas

- Campaign admin, Sales Eco data steward, integration operator and support.

## 5. User Stories

- As an admin, I want to request a missing profile so that the participant can be resolved properly.
- As a steward, I want source context and possible duplicate hints so that I can resolve the request.
- As an operator, I want retry/reconciliation visibility so that outages do not lose requests.
- As an auditor, I want the temporary request linked to the eventual identity.

## 6. Requirements

### Functional Requirements

- Create a scoped profile request using approved minimum fields and campaign context.
- Assign stable request and idempotency IDs and show `Pending profile sync` without creating a participant master.
- Preserve requests through source API outage and retry safely.
- Receive callback/poll reconciliation outcomes: linked, needs clarification, rejected or duplicate candidate.
- Replace pending campaign linkage with the authoritative ID only after successful reconciliation.
- Retain the request-to-profile lineage and all attempts for audit.
- Notify the requester of actionable outcomes; notification failure does not change reconciliation.
- Route source corrections and duplicate resolution to the steward workflow.

### Non-Functional Requirements

- Minimize personal data and encrypt request payloads at rest/in transit.
- Prevent replay from creating multiple source requests.
- Enforce scope and mask request details for support roles.
- Expose age, last attempt and exact remediation for delayed requests.

## 7. Acceptance Criteria

- **Given** no master match, **when** a valid request is submitted twice, **then** one stable pending request results.
- **Given** the Sales Eco API is unavailable, **when** submission occurs, **then** the request is preserved and visibly retryable without a local master.
- **Given** a callback with authoritative ID, **when** reconciliation commits, **then** the campaign linkage points to that ID and the request history remains.
- **Given** a duplicate candidate, **when** returned, **then** no automatic merge occurs and steward action is required.
- **Given** notification fails after reconciliation, **when** viewed, **then** linked state remains committed and notification failure is separate.

## 8. Out of Scope

- Master-profile approval UI inside this module.
- Automatic fuzzy merge or authoritative source mutation.
