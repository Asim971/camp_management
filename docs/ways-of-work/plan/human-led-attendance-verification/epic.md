# 1. Epic Name

Human-Led Attendance Verification

## 2. Goal

**Problem:** Captured attendance does not prove that the registered person attended, while image quality, missing references and possible spoof signals make automated conclusions unsafe. CRM/CLM reviewers need a prioritized, low-distraction console that protects sensitive evidence and records consistent decisions. Large campaigns can otherwise create an unmanaged review backlog and delayed downstream reporting.

**Solution:** Provide an SLA- and risk-prioritized queue plus a structured evidence review case in which machine outputs are advisory, CRM makes the final decision, every outcome requires a reason, and downstream consequences are explicit before submission.

**Impact:** Attendance becomes a defensible business fact, review workload is manageable, overrides remain visible, and only approved records flow into reward eligibility and verified analytics.

## 3. User Personas

- **CRM/CLM Verifier:** Reviews evidence and makes individual final decisions.
- **CRM Supervisor:** Assigns/escalates work, handles overrides and monitors SLA/quality.
- **Quality Auditor:** Samples decisions and advisory/human divergence.
- **Security/Support:** Investigates provider, media or sensitive-access issues under restricted permission.
- **Field User:** Receives clear return-for-recapture reasons and downstream status.

## 4. High-Level User Journeys

1. A verifier opens My queue, Unassigned, SLA breach, Returned or Quality audit views sorted by action priority.
2. A supervisor bulk-assigns cases; approval remains an individual decision.
3. A verifier opens a case and compares captured/reference evidence at consistent crop and linked zoom.
4. The verifier reviews identity/session/device/location/consent context separately from quality, PAD and match advisory output.
5. The verifier approves, rejects, returns for recapture or escalates with mandatory reason and sees the downstream effect before confirmation.
6. Concurrent or already-decided cases refresh safely without creating a second decision.
7. Supervisors review SLA, overrides, no-reference cases and quality-audit samples with complete evidence-access history.

## 5. Business Requirements

### Functional Requirements

- Create a verification case only after required evidence/upload processing reaches a reviewable state.
- Prioritize queue rows by configured SLA, risk/quality signal and business consequence, not creation time alone.
- Show campaign/session, carpenter, age, advisory band, reference source, quality/PAD flags, reward impact and assignee.
- Support saved views, filters, claim, assign, escalate and quality-audit marking.
- Allow bulk assignment but prohibit bulk final approval/rejection.
- Render captured and reference images at comparable crop/scale with accessible zoom and linked comparison.
- Display reference source as Verified Profile Photo, Authorized NID Photo, Approved Baseline Photo or Unavailable.
- Keep machine recommendation, quality result, PAD/liveness result and human decision as separate objects.
- Do not present advisory output as a final decision or hide disagreement with the reviewer.
- Support no-reference and provider-unavailable manual review routes using surrounding evidence.
- Provide Approve, Reject, Return for recapture and Escalate; require a configured reason and appropriate note for every submitted outcome.
- Explain effects on attendance status, reward eligibility, field notification and analytics before confirmation.
- Preserve every attempt, prior return and decision in lineage and audit; recapture never overwrites prior evidence.
- Enforce configured attempt limits and supervisor override policy.
- Use optimistic locking/version checks so only one final decision commits.
- Notify relevant users after commit without making notification delivery part of transaction authority.
- Log evidence open, sensitive reveal, decision, override, export and escalation with case and correlation context.

### Non-Functional Requirements

- CRM remains final decision authority in MVP; automated approval/rejection is prohibited.
- Blur/hide evidence until an authorized case is opened; use short-lived viewers and disable download by default.
- Mask NID and phone details and limit raw vendor outputs to explicitly authorized roles.
- Meet WCAG 2.2 AA, keyboard navigation, focus order, screen-reader naming and 200% zoom requirements.
- Optimize for desktop and tablet landscape; final phone-based image comparison is unsupported.
- Load thumbnails before full evidence and provide explicit image-loading/failure states.
- Record complete immutable audit history and preserve reason-code versions.
- Prevent duplicate decisions under concurrent review and recover safely from transient submit failures.
- Display factual, non-accusatory integrity language and never an opaque composite fraud score.

## 6. Success Metrics

| KPI | Target |
|---|---|
| Captured records decided within agreed SLA | At least 90% in pilot |
| Final decisions with required reason, actor and timestamp | 100% |
| Duplicate final decisions caused by concurrency/retry | 0 |
| Sensitive evidence opens with access audit | 100% |
| Machine recommendation shown as distinct from human decision | 100% of assisted cases |
| Bulk final approvals | 0 |
| Returned cases with actionable field-facing reason | 100% |

## 7. Out of Scope

- Fully automated or machine-authoritative face recognition decisions.
- Public or permanent media URLs and ordinary evidence downloads.
- Final review on phone-sized screens.
- Reward payment execution.
- Composite fraud scoring or punitive action based solely on a signal.
- Editing authoritative carpenter identity data from the case.

## 8. Business Value

**High.** Verification is the trust boundary between field activity and business-recognized attendance. It protects analytics, reward eligibility and audit defensibility while allowing future machine assistance without surrendering human control.

## Source Traceability and Dependencies

- **Requirements:** Original PRD G4, F10, FR-010-FR-011; guideline CM-FR-060 to CM-FR-067.
- **Design ownership:** C-01 Verification queue and C-02 Verification case.
- **Depends on:** Uploaded attendance evidence, approved reference resolution, secure media, reason/SLA configuration and CRM role scope.
- **Hands off to:** Field recapture, Carpenter 360, campaign analytics, integrity review and rewards eligibility facts.