# 1. Feature Name

Registered Carpenter Search and Selection

## 2. Epic

- [Parent Epic: Offline Field Attendance Capture](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 5, 9 and 12

## 3. Goal

**Problem:** Similar names and rushed field conditions can cause evidence to be attached to the wrong registered person. Full phone or NID display is inappropriate in public event settings.

**Solution:** Search only the active session's authoritative registrations and require a second masked identity cue before capture.

**Impact:** Wrong-person captures decline without slowing field work or exposing sensitive identity data.

## 4. User Personas

- Field attendance user and campaign participant.

## 5. User Stories

- As a field user, I want fast search by name, ID or phone suffix so that I find the registered carpenter.
- As a field user, I want similar names flagged so that I confirm using another cue.
- As a field user, I want prior attendance status so that I do not duplicate a capture.
- As a participant, I want full NID and phone hidden during selection.

## 6. Requirements

### Functional Requirements

- Search cached/server session registrations by name, carpenter ID and approved phone suffix.
- Show thumbnail where allowed, name, ID, masked suffix, territory/dealer context and controlled attendance state.
- Work from an authorized offline registration snapshot and show its freshness.
- Flag similar names and require explicit confirmation using a second cue.
- Distinguish Eligible, Already captured, Pending sync, Returned, Ineligible and Out of session.
- Block new normal capture for already captured/pending records and direct users to status.
- Allow returned records into configured recapture flow without overwriting prior attempts.
- Record selected authoritative registration ID, not copied free text.

### Non-Functional Requirements

- Return local search results quickly under offline field conditions.
- Never expose full NID/phone or unrestricted profile data.
- Keep targets at least 48 px and support screen-reader result summaries.
- Prevent stale snapshots from authorizing a capture outside server reconciliation rules.

## 7. Acceptance Criteria

- **Given** two similar names, **when** one is selected, **then** capture remains blocked until a second cue is confirmed.
- **Given** a Pending sync record, **when** selected, **then** status is shown and recapture is not offered merely due to delay.
- **Given** a Returned record with attempts remaining, **when** selected, **then** the return reason and recapture path are available.
- **Given** offline mode, **when** searching, **then** authorized cached registrations and freshness are shown.
- **Given** any result, **when** viewed publicly, **then** full NID and phone are absent.

## 8. Out of Scope

- Registering a new master profile or unapproved walk-in.
- QR scanning, reserved for a future approved release.
