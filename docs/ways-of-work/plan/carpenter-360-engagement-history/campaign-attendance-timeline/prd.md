# 1. Feature Name

Campaign and Attendance Timeline

## 2. Epic

- [Parent Epic: Carpenter 360 Engagement and Commercial History](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 5, 6 and 10

## 3. Goal

**Problem:** Registration, capture, verification and reward facts are spread across systems and can be mistaken for one another. Users need chronology without exposing sensitive evidence or rewriting immutable history.

**Solution:** Present a source-linked timeline that distinguishes campaign registration, attendance attempts, final CRM decisions, rewards and corrections.

**Impact:** Support and business users can explain participation history without conflating workflow stages.

## 4. User Personas

- CRM reviewer/supervisor, campaign admin, manager and support user.

## 5. User Stories

- As a support user, I want ordered events and lineage so that I can explain what happened.
- As a manager, I want registration, capture and approval distinguished so that counts are not misread.
- As a reviewer, I want prior attempts and reasons so that repeat cases have context.
- As a user, I want corrections appended rather than hidden so that history remains trustworthy.

## 6. Requirements

### Functional Requirements

- Show campaign/session registration, notice outcome, capture attempts, sync, provider advice, CRM decisions, returns/recaptures, rewards and authorized corrections.
- Use controlled labels and source timestamps with source system/correlation references.
- Group related attempts under one registration while preserving each immutable attempt.
- Mark final CRM decision as authoritative and machine outcomes as advisory.
- Support date, campaign and event-type filters plus drill-down under permission.
- Hide evidence thumbnails/raw details unless opened through authorized case controls.
- Show missing/delayed source events and reconciliation status explicitly.
- Append correction/reversal events instead of mutating prior history.

### Non-Functional Requirements

- Use deterministic chronological ordering with source-time tie handling.
- Enforce scoped field/evidence access and audit sensitive drill-down.
- Support long histories through pagination/virtualization and accessible semantics.
- Do not infer events that have not been received.

## 7. Acceptance Criteria

- **Given** capture, provider and CRM events, **when** timeline renders, **then** each stage is separate and CRM decision is identified as final.
- **Given** a returned recapture, **when** expanded, **then** old and new attempts plus return reason remain visible.
- **Given** a correction, **when** history renders, **then** original and correction events both remain.
- **Given** delayed reward data, **when** viewed, **then** reward is marked delayed/unavailable rather than zero.
- **Given** a user without evidence permission, **when** timeline loads, **then** event context appears without protected media access.

## 8. Out of Scope

- Editing event history or making verification decisions.
- Cross-person analytics and causal campaign measurement.
