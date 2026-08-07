# 1. Feature Name

Prioritized CRM Verification Queue

## 2. Epic

- [Parent Epic: Human-Led Attendance Verification](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 5, 10 and 11

## 3. Goal

**Problem:** Large campaigns create more cases than reviewers can treat as an unordered list. SLA breaches, no-reference and high-consequence cases need priority, while bulk approval would undermine individual human decisions.

**Solution:** Provide scoped saved views, SLA/risk/business-priority sorting, claim/assignment and quality-audit routing with individual decision enforcement.

**Impact:** Review backlog is allocated consistently and SLA compliance improves.

## 4. User Personas

- CRM verifier, CRM supervisor and quality auditor.

## 5. User Stories

- As a verifier, I want My queue sorted by urgency so that I decide the right case next.
- As a supervisor, I want bulk assignment so that workload is balanced without bulk decision.
- As a quality auditor, I want marked samples and advisory divergence views so that review quality is visible.
- As a verifier, I want queue freshness and concurrent ownership so that I avoid duplicated work.

## 6. Requirements

### Functional Requirements

- Provide My queue, Unassigned, SLA breach, Returned, Completed and Quality audit views.
- Sort by configured SLA state, quality/integrity signal and business consequence with transparent sort context.
- Show preview thumbnail under policy, campaign/session, carpenter, age, advisory band, reference source, quality/PAD flags, reward impact and assignee.
- Support scoped search, filters, saved views and active-filter removal.
- Allow claim, assign, reassign, escalate and mark-for-audit under permission.
- Support bulk assignment only; prohibit bulk approve/reject/return.
- Update ownership/status via polling/SSE and surface stale rows before opening.
- Explain empty, delayed, unavailable-evidence and permission-limited states.

### Non-Functional Requirements

- Use virtualized accessible table behavior and keyboard navigation.
- Enforce organization/territory/team scope server-side.
- Avoid loading full sensitive evidence in queue payloads.
- Meet agreed freshness/response target and show last update.

## 7. Acceptance Criteria

- **Given** breached and ordinary cases, **when** default queue loads, **then** configured urgent cases sort first.
- **Given** selected cases, **when** supervisor bulk actions open, **then** assignment is available and final-decision actions are absent.
- **Given** a verifier claims an unassigned case, **when** another user refreshes, **then** the new owner is visible and conflicting claim is rejected.
- **Given** an out-of-scope case, **when** searched, **then** no identifying row/count is disclosed.
- **Given** a quality-audit mark, **when** committed, **then** it is traceable without changing the final attendance decision.

## 8. Out of Scope

- Evidence comparison and final decision controls.
- Automated case approval or phone final review.
