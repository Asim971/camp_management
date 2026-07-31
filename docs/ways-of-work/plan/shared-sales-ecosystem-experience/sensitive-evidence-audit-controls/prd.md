# 1. Feature Name

Sensitive Evidence Access and Audit Controls

## 2. Epic

- [Parent Epic: Shared Sales Ecosystem Experience and Trust Controls](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), especially sections 10 and 12

## 3. Goal

**Problem:** Face images, reference photos and identity fields are sensitive and can be exposed through thumbnails, URLs, exports or support tooling. Access without case context and immutable audit evidence creates material privacy risk. Ordinary users do not need raw vendor payloads or full NID values.

**Solution:** Apply least-privilege masking, blur-until-open evidence, short-lived signed viewers and correlation-aware audit events to every sensitive view, reveal and export.

**Impact:** Authorized work remains possible while sensitive-data exposure is minimized and reconstructable.

## 4. User Personas

- CRM reviewers and supervisors opening case evidence.
- Support/security users accessing restricted diagnostics.
- Auditors reviewing access history.
- Field and business users who must see only masked identity cues.

## 5. User Stories

- As a verifier, I want evidence available only inside my authorized case so that I can decide without creating a reusable public link.
- As a field user, I want masked identity cues so that nearby participants do not see sensitive data.
- As an auditor, I want every reveal and export tied to actor and case so that access is accountable.
- As support, I want restricted diagnostics under explicit permission so that ordinary roles never receive raw payloads.

## 6. Requirements

### Functional Requirements

- Blur or hide sensitive thumbnails until an authorized case/view is opened.
- Fetch evidence through short-lived signed sessions and disable download by default.
- Mask NID and phone values according to role and context; never place full values in URLs, notifications or general exports.
- Require case/purpose context for evidence open, reveal and controlled export.
- Emit audit events with actor, subject, action, case, scope, timestamp and correlation ID.
- Restrict raw vendor payloads and threshold details to explicitly authorized support/security roles.
- Expire viewer sessions and clear protected cached media according to policy.
- Show reference source without exposing unnecessary source document details.
- Fail closed when authorization or audit-event commitment cannot be established for high-risk access.

### Non-Functional Requirements

- Encrypt evidence and sensitive metadata at rest and in transit.
- Prevent signed URLs and media tokens from entering logs, history or analytics.
- Make audit events durable and server-authoritative; buffered client events must reconcile.
- Meet accessible-name and keyboard controls for reveal, close and zoom actions.

## 7. Acceptance Criteria

- **Given** an unauthorized user, **when** they request an evidence URL or cached thumbnail, **then** no image or identifying metadata is disclosed.
- **Given** an authorized verifier opens evidence, **when** the viewer is created, **then** an access event records actor, case, subject and correlation ID.
- **Given** a signed viewer expires, **when** the image is requested again, **then** reauthorization is required.
- **Given** a general export or notification, **when** identity data is included, **then** full NID and phone values are absent.
- **Given** a role without raw-payload permission, **when** diagnostics are viewed, **then** the restricted setting is identified without exposing its value.

## 8. Out of Scope

- Enterprise SIEM replacement or legal retention-policy definition.
- Public media sharing or routine evidence download.
- Vendor credential storage or display.
