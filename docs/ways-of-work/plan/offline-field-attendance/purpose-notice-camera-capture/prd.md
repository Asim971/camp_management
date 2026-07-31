# 1. Feature Name

Purpose Notice and Camera-Only Evidence Capture

## 2. Epic

- [Parent Epic: Offline Field Attendance Capture](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 9, 12 and 13

## 3. Goal

**Problem:** Attendance evidence must be live, understandable and reviewable, but poor lighting, multiple faces or unclear purpose can invalidate it. Raw scores and coercive language are inappropriate for participants and field staff.

**Solution:** Provide a bilingual notice followed by camera-only framing, on-device quality guidance, encrypted commit and an approved manual route.

**Impact:** More captures are reviewable on first attempt and each has traceable purpose-notice evidence.

## 4. User Personas

- Field user, campaign participant and privacy/support reviewer.

## 5. User Stories

- As a participant, I want the purpose notice in my language so that I can make an informed choice.
- As a field user, I want actionable camera guidance so that I capture acceptable evidence.
- As a participant, I want a policy-approved alternative where available so that refusal is not coercively handled.
- As a verifier, I want capture/session/device metadata so that evidence context is complete.

## 6. Requirements

### Functional Requirements

- Present the approved notice and explicit language choice before camera activation.
- Record version, language, timestamp and acceptance/refusal/manual-route outcome.
- Separate optional marketing consent from attendance verification.
- Open live camera only; disable gallery/file substitution.
- Provide framing guidance and detect no face, multiple faces, blur, poor light and orientation.
- Express failures as corrective guidance without raw scores or accusations.
- Allow recapture before final commit and show a controlled preview/quality result.
- Commit evidence with participant, registration, session, attempt, user, device, time and location metadata.
- Encrypt evidence before local persistence and create a stable attendance/idempotency record.
- Offer configured manual route when processing is unavailable, inappropriate or declined.

### Non-Functional Requirements

- Keep evidence encrypted at rest and never place media bytes in ordinary JSON/logs.
- Support common corporate Android devices, bright-light testing and accessible camera controls.
- Commit capture locally without requiring network.
- Do not expose raw match/PAD scores or sensitive reference images to field users.

## 7. Acceptance Criteria

- **Given** no accepted notice outcome, **when** capture is attempted, **then** camera activation is blocked.
- **Given** multiple faces or poor light, **when** capture occurs, **then** specific guidance is shown and invalid evidence cannot silently submit.
- **Given** an accepted quality result offline, **when** Submit is selected, **then** encrypted evidence and metadata commit locally with Pending sync.
- **Given** gallery selection is attempted, **when** using normal attendance capture, **then** no gallery route is available.
- **Given** a policy-supported refusal/manual route, **when** selected, **then** outcome and reason are recorded without coercive wording.

## 8. Out of Scope

- Identity matching or final attendance decision on device.
- General media upload and unrestricted manual attendance.
