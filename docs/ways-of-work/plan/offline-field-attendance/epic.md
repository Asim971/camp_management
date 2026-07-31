# 1. Epic Name

Offline Field Attendance Capture

## 2. Goal

**Problem:** Field users must identify the correct carpenter and capture valid attendance evidence in bright light, weak connectivity and time-constrained sessions. Network failure, app restart or ambiguous sync state can cause lost work and duplicate recapture. Participants also need a clear, bilingual purpose notice and a non-coercive route when biometric processing is unavailable or inappropriate.

**Solution:** Deliver a session-focused, camera-only mobile workflow with readiness checks, authoritative carpenter selection, versioned purpose notice, immediate quality guidance, encrypted offline persistence and transparent synchronization lineage.

**Impact:** Field teams capture complete, reviewable attendance evidence without losing work or exposing sensitive identity details, and CRM receives consistent cases even when connectivity is delayed.

## 3. User Personas

- **Field Attendance User/Event Executor:** Selects participants and captures evidence quickly.
- **Field Organizer/Supervisor:** Confirms readiness and monitors queue health.
- **Campaign Participant/Carpenter:** Receives notice and participates in capture or approved manual route.
- **Support Operator:** Diagnoses device, media and synchronization failures without unnecessary evidence exposure.

## 4. High-Level User Journeys

1. A field user opens an assigned active session and runs login, camera, storage, time, location, app-version, network and offline-capacity checks.
2. The user searches registered carpenters, confirms the correct profile using a second cue and sees prior attendance state.
3. The participant selects Bangla or English, reviews the purpose notice and records acceptance/refusal outcome and notice version.
4. The app captures from the live camera only and gives actionable guidance for face count, blur, lighting and orientation.
5. Evidence is encrypted locally, committed as captured, and uploaded immediately or queued durably with an idempotency key.
6. After restart or reconnection, synchronization resumes; the user sees queued, uploading, processing, CRM review, returned, approved or failed state without unnecessary recapture.
7. A returned record opens the reason and permitted recapture path while retaining previous attempts.

## 5. Business Requirements

### Functional Requirements

- Show only assigned/relevant sessions and prioritize the active session in the mobile shell.
- Run readiness checks and distinguish blocking failures, warnings and offline-ready conditions.
- Allow authorized override only with policy, permission and recorded reason.
- Search registered participants by name, carpenter ID and phone suffix within the active session.
- Display masked, minimum-necessary identity cues and attendance state; flag already captured, pending sync, returned, ineligible and out-of-session records.
- Require explicit confirmation for similar-name results before camera access.
- Present the purpose notice before capture with language selection, purpose, data use, provider category, retention, rights/contact and refusal consequence.
- Record notice version, language, timestamp and outcome; separate optional marketing communication consent.
- Provide a policy-approved manual route when capture/biometric processing is unavailable, inappropriate or declined.
- Use live camera capture only; disable gallery/file substitution for normal attendance.
- Provide framing and actionable quality checks for no face, multiple faces, blur, poor light and orientation without exposing raw scores.
- Capture participant/session/user/device/time/location, notice and attempt metadata with the evidence record.
- Encrypt evidence before local persistence and upload through short-lived authorized media flows.
- Persist a durable queue with idempotency keys, retry count, state, captured time and last successful sync.
- Resume after process kill, restart or connectivity change and use bounded exponential backoff.
- Make capture success explicit and separate from upload, processing and approval success.
- Never recommend recapture solely because synchronization is delayed.
- Support retry, pause, error detail and controlled discard under permission; retain auditable attempt lineage.
- Receive final/returned statuses and route permitted recapture without overwriting earlier evidence.

### Non-Functional Requirements

- Lose zero committed captures during app restart, network transition or retry in supported failure tests.
- Prevent duplicate server attendance from replayed uploads through idempotency.
- Encrypt evidence and sensitive metadata at rest and in transit; protect keys using platform facilities.
- Keep the capture path usable on common corporate Android devices and supported 320 px+ screens.
- Use minimum 48 px targets and 52-56 px capture/confirmation actions with Android accessibility semantics.
- Avoid displaying full NID, phone, raw match score or sensitive reference image to field users.
- Preserve user work and provide exact remediation for storage, permission, version and service failures.
- Record time basis and timezone and detect material device-time drift.
- Meet agreed upload/retry performance without blocking additional offline captures within configured capacity.

## 6. Success Metrics

| KPI | Target |
|---|---|
| Captured attendance mapped to a registered participant and live evidence | At least 95% in pilot |
| Committed offline captures lost across restart/interruption | 0 |
| Duplicate attendance created by upload replay | 0 |
| Capture attempts passing quality without recapture | Establish pilot baseline; improve through guidance |
| Users recapturing solely because upload is delayed | 0 in usability testing |
| Purpose-notice records with version, language, timestamp and outcome | 100% |
| Blocking readiness failures with actionable remediation | 100% |

## 7. Out of Scope

- Final identity approval/rejection by the field user.
- Gallery upload as ordinary attendance evidence.
- Exposing raw biometric/match scores or full NID details.
- Autonomous fraud conclusions.
- General participant master editing.
- Final incentive or reward settlement.

## 8. Business Value

**High.** This epic creates the trustworthy evidence on which verification and campaign measurement depend, while directly addressing the highest operational risk: preserving field work under poor connectivity.

## Source Traceability and Dependencies

- **Requirements:** Original PRD G3, F9, FR-009; guideline CM-FR-040 to CM-FR-058 and NFR-04, NFR-09, NFR-13.
- **Design ownership:** M-01 Readiness, M-02 Search, M-03 Notice/capture and M-04 Offline queue.
- **Depends on:** Approved campaigns/sessions, authoritative registrations, legal notice/retention policy, secure media and idempotent upload APIs.
- **Hands off to:** Human-led verification, integrity operations and analytics after final decision.
