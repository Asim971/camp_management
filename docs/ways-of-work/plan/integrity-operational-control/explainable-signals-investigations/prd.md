# 1. Feature Name

Explainable Integrity Signals and Investigations

## 2. Epic

- [Parent Epic: Integrity and Operational Control](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 10, 12 and 14

## 3. Goal

**Problem:** Duplicate, velocity, geofence and advisory anomalies require review, but opaque scores and automatic fraud labels can create unfair or punitive outcomes. Investigators need evidence, rule context and documented resolution.

**Solution:** Generate versioned explainable signals, group them into scoped investigations and require human dispositions without changing attendance automatically.

**Impact:** Risk is reviewed consistently while false positives and ungoverned punitive action are reduced.

## 4. User Personas

- Integrity analyst, supervisor, quality auditor and restricted support user.

## 5. User Stories

- As an analyst, I want facts and rule/version behind a signal so that I can assess it.
- As a supervisor, I want prioritized investigations and ownership so that high-consequence work is controlled.
- As a participant-impact reviewer, I want human disposition before adverse action so that automation is not punitive.
- As an auditor, I want immutable signal and resolution history so that decisions are reconstructable.

## 6. Requirements

### Functional Requirements

- Create signals for configured duplicate, velocity, geofence, device, identity/advisory and access patterns.
- Show rule ID/version, triggering facts, source freshness, severity band and known limitations.
- Group related signals into investigations without merging source records.
- Provide scoped queue, assignment, notes, evidence links, escalation and status.
- Require disposition reason: explained, false positive, monitor, corrective action or escalate.
- Keep signals advisory; do not auto-reject attendance, suspend users or label fraud.
- Record any separately authorized downstream action and its approving authority.
- Support rule-version comparison and mark signals affected by later correction.

### Non-Functional Requirements

- Enforce least privilege, sensitive-access audit and masked identity presentation.
- Make rule evaluation deterministic/reproducible for a given version and input.
- Protect small cohorts and avoid proxy attributes not approved for integrity use.
- Provide accessible tables and non-color severity cues.

## 7. Acceptance Criteria

- **Given** a signal, **when** opened, **then** triggering facts, rule/version and limitations are visible.
- **Given** a high-severity signal, **when** generated, **then** attendance remains unchanged until an authorized business decision occurs elsewhere.
- **Given** related signals, **when** grouped, **then** original signal/source records remain independently traceable.
- **Given** a disposition without reason, **when** submitted, **then** no investigation transition occurs.
- **Given** a corrected source fact, **when** reevaluation runs, **then** the prior signal remains and affected/corrected state is appended.

## 8. Out of Scope

- Automated fraud determination, employee discipline or participant sanction.
- Final CRM attendance decision and law-enforcement workflows.
