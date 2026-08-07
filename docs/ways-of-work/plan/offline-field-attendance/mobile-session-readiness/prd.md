# 1. Feature Name

Mobile Session Readiness and Start Gate

## 2. Epic

- [Parent Epic: Offline Field Attendance Capture](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 7, 9 and 14

## 3. Goal

**Problem:** Field failures discovered at first capture waste event time and can produce unusable evidence. Users need to know whether login, assignment, camera, storage, time, location, app version, network and offline capacity are ready.

**Solution:** Run a session-focused readiness checklist with blocking, warning and offline-ready outcomes plus exact remediation and governed override.

**Impact:** Sessions begin with fewer preventable interruptions and overrides remain controlled.

## 4. User Personas

- Field attendance user, field organizer and support operator.

## 5. User Stories

- As a field user, I want readiness checked before capture so that failures do not surprise me with a participant waiting.
- As a field user, I want offline-ready distinguished from blocked so that weak connectivity does not stop valid work.
- As an organizer, I want authorized override with reason so that exceptional sessions remain auditable.
- As support, I want exact remediation and diagnostic reference so that issues are resolved quickly.

## 6. Requirements

### Functional Requirements

- Show assigned session, campaign, venue, capture window and sync summary.
- Check authenticated assignment, camera permission/function, secure storage, device time, location permission, app version, network and offline queue capacity.
- Combine server session readiness with device-local checks without treating network absence as automatic failure.
- Classify each check Pass, Warning or Blocking and identify who can fix it.
- Offer Retry, Open settings, View assignment/registration and support reference actions.
- Enable Start attendance only when all non-overridable blocks pass or a permitted override is committed.
- Require override permission, configured reason and audit record.
- Re-run volatile checks before start and after relevant settings change.

### Non-Functional Requirements

- Complete local checks within the agreed field startup target and remain usable offline.
- Use 48 px targets, screen-reader semantics and clear non-color status cues.
- Never expose sensitive registration/evidence data in diagnostics.
- Use authoritative server time/config when available and flag material device-time drift.

## 7. Acceptance Criteria

- **Given** camera permission denied, **when** readiness runs, **then** it is blocking with an Open settings action and Start is unavailable.
- **Given** no network but adequate encrypted queue capacity and cached assignment, **when** readiness runs, **then** the session is Offline-ready rather than blocked.
- **Given** an outdated mandatory app version, **when** readiness runs, **then** Start remains blocked with update guidance.
- **Given** an overridable warning and authorized organizer, **when** override commits with reason, **then** Start can proceed and the override is audited.
- **Given** device time outside tolerance, **when** detected, **then** the exact correction is shown and evidence capture cannot silently use the invalid time.

## 8. Out of Scope

- Web organizer readiness configuration and actual evidence capture.
- Device repair or app-store management.
