# 1. Feature Name

Secure Verification Evidence Review

## 2. Epic

- [Parent Epic: Human-Led Attendance Verification](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 10-12

## 3. Goal

**Problem:** Reviewers need comparable images and context without exposing evidence broadly or treating advisory outputs as decisions. Missing references and provider failures must still support a controlled manual review route.

**Solution:** Provide a three-zone case view for protected evidence, contextual facts and clearly separated advisory results, with consistent crop/zoom and audited access.

**Impact:** Review quality and privacy improve while no-reference cases remain actionable.

## 4. User Personas

- CRM verifier/supervisor, quality auditor and restricted support/security user.

## 5. User Stories

- As a verifier, I want captured and reference images at the same crop/scale so that comparison is fair.
- As a verifier, I want advisory quality/PAD/match separated from human decision so that I retain authority.
- As a verifier, I want no-reference context so that I can use the approved manual route.
- As an auditor, I want evidence opens recorded so that sensitive access is accountable.

## 6. Requirements

### Functional Requirements

- Authorize and audit case/evidence access before revealing protected media.
- Show captured attempt and approved reference at consistent crop/scale with linked accessible zoom.
- Identify reference source or Unavailable explicitly.
- Show participant, registration, campaign/session, capture user/time/device/location and notice context with masking.
- Present quality, PAD/liveness and 1:1 recommendation as separate advisory facts.
- Never preselect or visually merge advisory output with final decision.
- Support no-reference/provider-unavailable manual review guidance using surrounding evidence.
- Show attendance lineage and prior attempt/return history without overwriting records.
- Handle image loading, expired viewer, unavailable media and restricted fields explicitly.

### Non-Functional Requirements

- Use short-lived signed media viewers, blur-until-open and download disabled by default.
- Meet desktop/tablet landscape, keyboard, screen-reader and 200% zoom requirements.
- Log every evidence open/reveal with actor, case and correlation ID.
- Restrict raw vendor data to explicitly authorized roles.

## 7. Acceptance Criteria

- **Given** an authorized case, **when** evidence opens, **then** both images use comparable framing and an access event is recorded.
- **Given** no approved reference, **when** the case loads, **then** comparison is marked Not performed and manual-route guidance appears.
- **Given** an advisory High result, **when** the case loads, **then** no human decision is preselected.
- **Given** an expired viewer session, **when** media is requested, **then** protected content remains hidden until reauthorization.
- **Given** keyboard-only use, **when** zoom/comparison controls are operated, **then** all functions and labels remain accessible.

## 8. Out of Scope

- Final decision submission and automated identity determination.
- Permanent/public evidence URLs or ordinary download.
