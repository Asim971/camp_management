# 1. Feature Name

Authoritative Carpenter Search and Registration

## 2. Epic

- [Parent Epic: Participant Identity, Registration and Bulk Import](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 4, 5 and 10

## 3. Goal

**Problem:** Selecting the wrong or a locally invented participant breaks attendance verification and longitudinal reporting. Search must respect scope and provide enough identity cues without exposing full sensitive values.

**Solution:** Search the Sales Eco-backed master, confirm identity with multiple cues, evaluate eligibility and register the authoritative ID.

**Impact:** Registrations become trustworthy and duplicate campaign participation declines.

## 4. User Personas

- Campaign admin/creator and authorized field user.

## 5. User Stories

- As an admin, I want scoped search by name, ID or phone suffix so that I find the intended carpenter.
- As a user facing similar names, I want a second identity cue so that I avoid the wrong profile.
- As an admin, I want eligibility and duplicate warnings before commit so that invalid registrations do not enter the campaign.
- As a participant, I want only minimum necessary details exposed during selection.

## 6. Requirements

### Functional Requirements

- Search authoritative master records within role and territory scope by supported identity terms.
- Show profile thumbnail where allowed, carpenter ID, masked phone suffix, territory/dealer, status and last sync.
- Indicate stale, inactive, out-of-scope, already registered and otherwise ineligible results.
- Require a second identity cue for similar/ambiguous results.
- Evaluate campaign eligibility and configured capacity/waitlist rules before registration.
- Commit the authoritative Sales Eco ID only and apply controlled registration status.
- Detect duplicate registration idempotently and return the existing registration.
- Support pre-start removal/cancellation under permission with audit.
- Route source-data corrections to Sales Eco rather than local editing.

### Non-Functional Requirements

- Enforce result-level scope server-side and avoid disclosing excluded matches/counts.
- Never expose full NID/phone in UI, URLs, logs or exports.
- Debounce search and meet agreed response time with clear degraded-source state.
- Meet accessible search, result and confirmation behavior.

## 7. Acceptance Criteria

- **Given** two similar names, **when** one is selected, **then** confirmation requires an additional ID/territory/dealer cue.
- **Given** an already registered carpenter, **when** registration is retried, **then** no duplicate is created and existing state is shown.
- **Given** an out-of-scope identity, **when** searched, **then** identifying data is not disclosed.
- **Given** a stale profile, **when** shown, **then** source and last-sync warning are visible before commit.
- **Given** a valid eligible identity, **when** registered, **then** campaign linkage and audit reference the authoritative ID.

## 8. Out of Scope

- Creating or editing authoritative master profiles.
- Bulk import and field attendance selection after registration.
