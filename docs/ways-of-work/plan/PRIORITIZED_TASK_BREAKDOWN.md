# Prioritized Task and Subtask Backlog

**Program:** ACSL Carpenter Campaign Management and Attendance Verification  
**Inputs:** [Feature PRD portfolio](README.md), [Flutter architecture](../../../ARCHITECTURE_Flutter.md), and [existing scaffold breakdown](../../../TASK_BREAKDOWN.md)  
**Planning date:** 2026-07-29

## 1. Purpose and Execution Rules

This is the canonical remaining-work backlog for the 32 feature PRDs. It prioritizes a trustworthy pilot path over screen count: shared contracts and controls first, then campaign setup, field capture, CRM decision, contribution reporting, and finally operational depth and governed optimization.

### Status Markers

- **BUILD:** No production feature exists or the route is still a placeholder.
- **HARDEN:** A scaffold exists but has known contract, security, state, accessibility, or test gaps.
- **VERIFY:** The primary UI exists; prove PRD acceptance criteria and repair discovered gaps.
- **BLOCKED:** An external API, legal, security, policy, or data decision is required.

### Priority Definitions

| Priority | Meaning | Exit expectation |
|---|---|---|
| **P0** | Pilot/release blocker | Required for the controlled end-to-end path and security/privacy baseline |
| **P1** | Operational scale and management depth | Required before broad rollout or material reporting reliance |
| **P2** | Governed optimization | Deliver after data maturity and governance gates are met |

### Global Definition of Done

Every feature task is done only when:

1. Domain rules and state transitions have unit tests.
2. Repository/DTO behavior has success, authorization, timeout, partial-data, conflict, and idempotency tests where applicable.
3. Riverpod state covers loading, empty, partial/delayed, failed, permission-denied, retry, and committed-with-downstream-failure states.
4. UI passes keyboard, screen-reader semantics, 200% web zoom, 320 px mobile layout, and English/Bangla expansion checks where applicable.
5. Server authorization is rechecked; client guards are not treated as security.
6. Material actions and sensitive views emit durable audit events with correlation IDs.
7. Feature acceptance criteria in its linked PRD pass through focused widget/integration tests.
8. `flutter analyze`, `flutter test`, web build, and affected Android build/test gates pass.

## 2. Delivery Order and Critical Path

| Order | Workstream | Priority | Depends on | Release gate |
|---|---|---|---|---|
| 1 | Platform contract and trust-control closure | P0 | Auth, audit, media, legal notice contracts | No protected-data flash; durable audit; approved notice model |
| 2 | Campaign, session, identity and import closure | P0 | Order 1; Campaign and Sales Eco APIs | Approved session with authoritative registrations |
| 3 | Offline capture and durable synchronization | P0 | Orders 1-2; media upload contract | Zero committed-capture loss and zero duplicate attendance |
| 4 | Human CRM verification | P0 | Order 3; CRM case/decision contract | One auditable final decision per case |
| 5 | Pilot contribution dashboard and reconciliation | P0 | Orders 2-4; canonical order facts | Lineage-defined funnel and non-causal contribution |
| 6 | Carpenter 360 and integrity operations | P1 | Orders 4-5 | Scoped history and explainable operational review |
| 7 | Policy administration and sensitive monitoring | P1 | Order 1; governance decisions | Versioned activation, retention, access review |
| 8 | Governed ROI and optimization | P2 | Mature costs, baselines, attribution and approval | No causal metric before governance gate |

## 3. P0 — Platform and Trust-Control Closure

### P0.1 Adaptive Shell and Scoped Access — HARDEN

**Feature:** [Adaptive shell and scoped access](shared-sales-ecosystem-experience/adaptive-shell-scoped-access/prd.md)  
**Dependencies:** Auth/RBAC contract; organization and territory claims.

- [ ] **P0.1.1 Complete authentication lifecycle.**
  - Replace the unimplemented refresh callback with the real auth endpoint.
  - Define expiry, refresh rotation, logout, revoked-session, and offline-expiry behavior.
  - Add tests for refresh success, refresh rejection, concurrent 401s, logout, and stale roles.
- [ ] **P0.1.2 Harden authorization and route re-evaluation.**
  - Map role plus organization/territory scope to typed permissions.
  - Re-evaluate open routes after session, role, or scope changes without protected-content flash.
  - Test direct URL, browser refresh, back/forward, out-of-scope IDs, and expired sessions.
- [ ] **P0.1.3 Verify adaptive navigation.**
  - Confirm drawer, rail, and mobile navigation retain context, warnings, and primary action.
  - Enforce field session-focused navigation with no context switch during capture.
  - Test 320 px, tablet, desktop, 200% zoom, keyboard order, and Bangla expansion.
- [ ] **P0.1.4 Close route telemetry/privacy.**
  - Remove personal data and media tokens from URLs, analytics, breadcrumbs, and logs.
  - Emit access-denied and session-expiry diagnostics without record disclosure.

**Done gate:** Route/access acceptance criteria pass against real auth claims and server-denied responses.

### P0.2 Design System and Status Vocabulary — VERIFY

**Feature:** [Design system and status vocabulary](shared-sales-ecosystem-experience/design-system-status-vocabulary/prd.md)

- [ ] **P0.2.1 Reconcile typed states.** Compare campaign, registration, attendance, import, and integrity enums against every PRD and API status; reject unknown states safely.
- [ ] **P0.2.2 Audit component usage.** Replace raw status strings, one-off chips, and inconsistent buttons/fields in all implemented screens.
- [ ] **P0.2.3 Complete resilient component states.** Add loading, disabled, focus, error, empty, partial, delayed, and permission-denied specimens.
- [ ] **P0.2.4 Expand regression coverage.** Add golden and semantics tests for status chips, tables, dialogs, sheets, English/Bangla, and 200% zoom.

**Done gate:** One typed status renders identically across mobile, CRM, admin, notifications, and analytics fixtures.

### P0.3 Bilingual Localization and Versioned Notices — HARDEN / BLOCKED

**Feature:** [Bilingual localization and notices](shared-sales-ecosystem-experience/bilingual-localization-notices/prd.md)  
**Dependencies:** Legal-approved English/Bangla notice; notice version API.

- [ ] **P0.3.1 Finalize notice schema.** Define notice ID/version, language pair, effective dates, purpose, data use, retention, rights/contact, refusal consequence, and manual route.
- [ ] **P0.3.2 Implement notice retrieval/cache.** Fetch only approved active versions, cache session-required content for offline use, and retain historical rendering support.
- [ ] **P0.3.3 Persist presentation outcome.** Remove the capture-controller TODO by storing version, language, presented time, acceptance/refusal/manual-route outcome, and correlation ID.
- [ ] **P0.3.4 Validate language parity.** Block activation when either approved language is missing and test long Bangla text on small screens and screen readers.

**Done gate:** Every committed capture resolves to the exact approved notice version and language presented.

### P0.4 Sensitive Evidence and Audit Controls — HARDEN / BLOCKED

**Feature:** [Sensitive evidence and audit controls](shared-sales-ecosystem-experience/sensitive-evidence-audit-controls/prd.md)  
**Dependencies:** Durable audit endpoint; signed-media and retention contracts.

- [ ] **P0.4.1 Complete network observability.** Add correlation-ID propagation, bounded retry rules, redaction, and server error mapping to Dio.
- [ ] **P0.4.2 Complete durable audit emission.** Implement buffered delivery/reconciliation for capture, evidence open, reveal, decision, export, override, and settings actions.
- [ ] **P0.4.3 Enforce protected media sessions.** Add blur-until-open, short-lived signed viewer, expiration/reauthorization, no-download default, and cache cleanup.
- [ ] **P0.4.4 Enforce masking and purpose context.** Mask NID/phone, require case/purpose for reveal/export, and restrict raw vendor payloads.
- [ ] **P0.4.5 Test fail-closed paths.** Prove high-risk access fails when authorization or required audit commitment cannot be established.

**Done gate:** 100% of sampled sensitive views and material actions have durable correlated audit events; signed URLs never enter logs/history.

### P0.5 Accessibility and Resilient States — HARDEN

**Feature:** [Accessibility and resilient states](shared-sales-ecosystem-experience/accessibility-resilient-states/prd.md)

- [ ] **P0.5.1 Build shared state renderers.** Standardize loading, empty, delayed, partial, failed, retry, permission-denied, conflict, and reconciliation states.
- [ ] **P0.5.2 Preserve committed outcomes.** Distinguish business commit from notification, refresh, or analytics-delivery failure in controllers and copy.
- [ ] **P0.5.3 Run accessibility matrix.** Cover keyboard-only, focus restoration, screen-reader announcements, chart alternatives, 200% zoom, and Android TalkBack.
- [ ] **P0.5.4 Add release automation.** Add semantics/widget checks to CI and document manual audit evidence for critical paths.

**Done gate:** Seven prototype journeys pass the accessibility matrix and no delayed/unavailable metric displays as zero.

## 4. P0 — Campaign, Session and Participant Readiness

### P0.6 Campaign Discovery and Permitted Actions — VERIFY

**Feature:** [Campaign discovery and actions](campaign-lifecycle-session-operations/campaign-discovery-actions/prd.md)

- [ ] Verify scoped server search/filter/sort and exception-first default ordering.
- [ ] Reconcile row actions with lifecycle, permission, version, and server rejection behavior.
- [ ] Preserve filters across detail navigation, refresh, and deep links.
- [ ] Add table/mobile-card tests for empty, delayed, out-of-scope, and Bangla states.

**Done gate:** Search cannot disclose out-of-scope existence and every action matches the lifecycle state machine.

### P0.7 Campaign Authoring and Validation — VERIFY

**Feature:** [Campaign authoring and validation](campaign-lifecycle-session-operations/campaign-authoring-validation/prd.md)

- [ ] Extract/verify domain validators for required fields, dates, timezone, overlap, capacity, budget reference, and approver.
- [ ] Persist draft version and step progress across refresh; protect against concurrent overwrite.
- [ ] Implement server validation summary with links to invalid steps and controlled-field source labels.
- [ ] Test returned-campaign correction, double submit, lost response, and preserved comments/history.

**Done gate:** A valid draft submits exactly once; invalid or stale drafts cannot enter approval.

### P0.8 Campaign Approval and Correction — VERIFY

**Feature:** [Campaign approval and correction](campaign-lifecycle-session-operations/campaign-approval-correction/prd.md)

- [ ] Enforce segregation of duties and scoped decision permissions server-side.
- [ ] Complete warning acknowledgement and configured return/reject reason validation.
- [ ] Verify changed-field diff against the last reviewed version.
- [ ] Add optimistic concurrency, idempotency, audit, and committed-decision/notification-failure tests.

**Done gate:** One authorized decision is committed per version and returned values/comments remain intact.

### P0.9 Session Readiness and Lifecycle — HARDEN

**Feature:** [Session readiness and lifecycle](campaign-lifecycle-session-operations/session-readiness-lifecycle/prd.md)

- [ ] Define server readiness contract for assignments, venue/geofence, window, capacity, reference coverage, services, and configuration version.
- [ ] Implement Blocking/Warning/Pass evaluation and authorized override with reason.
- [ ] Verify start, pause, resume, close, late-capture, and completion state transitions with concurrency tests.
- [ ] Preserve and display pending sync, CRM, and reconciliation backlog after capture/session closure.

**Done gate:** Sessions cannot start with non-overridable blocks, and closure never hides unresolved records.

### P0.10 Authoritative Search and Registration — VERIFY / BLOCKED

**Feature:** [Authoritative search and registration](participant-identity-registration-import/authoritative-search-registration/prd.md)  
**Dependencies:** Sales Eco carpenter master and eligibility APIs.

- [ ] Replace mock/placeholder endpoints and verify result-level role/territory scope.
- [ ] Add stale/inactive/already-registered/ineligible states and second-cue confirmation.
- [ ] Commit only authoritative Sales Eco IDs with idempotent duplicate handling.
- [ ] Test source outage, ambiguous matches, capacity/waitlist, and removal/cancellation audit.

**Done gate:** No local shadow master is created and repeated registration returns the same campaign registration.

### P0.11 Profile Request and Reconciliation — HARDEN / BLOCKED

**Feature:** [Profile request and reconciliation](participant-identity-registration-import/profile-request-reconciliation/prd.md)  
**Dependencies:** Sales Eco profile-request and callback/status contracts.

- [ ] Define minimum-data request, stable request ID, idempotency key, and `Pending profile sync` model.
- [ ] Implement durable request submission/retry without creating a local participant master.
- [ ] Handle linked, clarification, rejected, and duplicate-candidate outcomes.
- [ ] Replace pending linkage only after authoritative reconciliation and retain full lineage/audit.

**Done gate:** API outage/replay loses no request and creates no duplicate profile request or local identity.

### P0.12 Dry-Run Bulk Import — VERIFY / BLOCKED

**Feature:** [Dry-run bulk import](participant-identity-registration-import/dry-run-bulk-import/prd.md)  
**Dependencies:** Malware scanning and asynchronous import-job APIs.

- [ ] Version the CSV template and validate file type, size, schema, stable row ID, and scan result.
- [ ] Verify dry run is non-mutating and every row receives one controlled outcome with masked detail.
- [ ] Commit only confirmed eligible rows using job and row idempotency.
- [ ] Add partial failure, cancellation, retry-eligible rows, replay, result expiry, and reconciliation tests.

**Done gate:** Mixed files produce deterministic row outcomes; replay creates zero duplicate registrations.

## 5. P0 — Offline Field Attendance

### P0.13 Mobile Session Readiness — BUILD

**Feature:** [Mobile session readiness](offline-field-attendance/mobile-session-readiness/prd.md)

- [ ] Build the M-01 screen and controller from cached assignment plus server readiness.
- [ ] Implement camera, secure storage, time drift, location, app version, network, queue-capacity, and assignment checks.
- [ ] Distinguish Offline-ready from Blocking and add exact Retry/Open settings/support actions.
- [ ] Add authorized override, volatile-check rerun, audit, and device/emulator tests.

**Done gate:** A field user cannot start with a non-overridable block; valid cached sessions can start offline.

### P0.14 Registered Carpenter Selection — VERIFY

**Feature:** [Registered carpenter selection](offline-field-attendance/registered-carpenter-selection/prd.md)

- [ ] Restrict search to the active session's authorized registration snapshot and show freshness.
- [ ] Require a second cue for ambiguous names while masking full NID/phone.
- [ ] Prevent normal recapture for Captured/Pending sync; route Returned records to attempt-aware recapture.
- [ ] Test offline search performance, stale snapshots, similar names, and controlled statuses.

**Done gate:** Selection stores the authoritative registration ID and cannot create duplicate capture due solely to delay.

### P0.15 Purpose Notice and Camera Capture — HARDEN

**Feature:** [Purpose notice and camera capture](offline-field-attendance/purpose-notice-camera-capture/prd.md)

- [ ] Integrate approved notice outcome persistence before camera activation.
- [ ] Replace `PassthroughQualityChecker` with supported face-count, blur, light, and orientation checks.
- [ ] Verify camera-only input, corrective guidance, preview/recapture-before-commit, and manual route.
- [ ] Commit encrypted evidence and complete participant/session/user/device/time/location metadata atomically.
- [ ] Emit attendance-captured audit and add bright-light/weak-network/real-device tests.

**Done gate:** Every accepted capture is live-camera evidence, encrypted before persistence, notice-linked, and locally durable offline.

### P0.16 Durable Offline Sync and Status — HARDEN / BLOCKED

**Feature:** [Durable offline sync and status](offline-field-attendance/durable-offline-sync-status/prd.md)  
**Dependencies:** Pre-signed upload, confirm, status, and server idempotency contracts.

- [ ] Replace placeholder upload endpoints and implement authorization, transfer progress, confirmation, and status retrieval.
- [ ] Complete restart/background resume and persist real last-successful-sync timestamp.
- [ ] Verify bounded exponential backoff, pause/retry, terminal failure, and controlled discard.
- [ ] Add failure-injection tests: kill before/after commit, lost confirmation, duplicate tap, URL expiry, provider outage, and reconnect.
- [ ] Confirm local evidence cleanup occurs only after server confirmation and retention policy.

**Done gate:** Zero atomically committed captures are lost and zero duplicate attendance records result under the failure matrix.

## 6. P0 — Human-Led Verification

### P0.17 Prioritized Verification Queue — BUILD / BLOCKED

**Feature:** [Prioritized verification queue](human-led-attendance-verification/prioritized-verification-queue/prd.md)  
**Dependencies:** CRM queue, assignment, saved-view, SLA, and real-time update contracts.

- [ ] Implement C-01 queue domain/repository/controller and replace placeholder route.
- [ ] Build My queue, Unassigned, SLA breach, Returned, Completed, and Quality audit views.
- [ ] Apply transparent SLA/risk/business-priority ordering, scoped filters, saved views, and freshness.
- [ ] Implement claim/assign/reassign/escalate/mark-for-audit; allow bulk assignment only.
- [ ] Add concurrent claim, stale row, out-of-scope, delayed evidence, and virtualization/a11y tests.

**Done gate:** Reviewers receive scoped prioritized work and no bulk final-decision path exists.

### P0.18 Secure Evidence Review — HARDEN / BLOCKED

**Feature:** [Secure evidence review](human-led-attendance-verification/secure-evidence-review/prd.md)

- [ ] Replace verification repository placeholders with real case/evidence contracts.
- [ ] Emit durable audit-on-case/evidence-open and require case authorization before reveal.
- [ ] Verify same crop/scale, linked zoom, reference-source label, masking, and full context metadata.
- [ ] Separate quality, PAD/liveness, and match advice from human decision with no preselection.
- [ ] Add no-reference, provider-unavailable, expired-viewer, missing-media, keyboard, and 200% zoom tests.

**Done gate:** Authorized reviewers can complete manual review without raw payload exposure or machine-to-decision coupling.

### P0.19 Decision, Return and Recapture — VERIFY / BLOCKED

**Feature:** [Decision, return and recapture](human-led-attendance-verification/decision-return-recapture/prd.md)

- [ ] Verify approve/reject/return/escalate permissions, configured reasons, notes, and downstream-effect preview.
- [ ] Complete server idempotency and optimistic-lock conflict handling for lost/stale responses.
- [ ] Preserve immutable decision/advisory context and separate notification failure from decision commit.
- [ ] Implement returned-attempt notification, remaining-attempt count, new-attempt lineage, and supervisor override.
- [ ] Add concurrent reviewer, attempt-limit, return/recapture, and advisory-divergence tests.

**Done gate:** CRM remains final authority and exactly one final decision exists per case version.

## 7. P0 — Pilot Reporting and Control Minimum

### P0.20 Exception-First Campaign Dashboard — BUILD

**Feature:** [Exception-first campaign dashboard](campaign-performance-attribution-roi/exception-first-campaign-dashboard/prd.md)

- [ ] Define governed KPI contracts for Registered, Captured, Uploaded, Processed, Reviewed, Approved, Rejected, Returned, and backlog.
- [ ] Build W-01 exception cards, KPI band, trend, campaign table, filters, and drill-down.
- [ ] Display denominator, lineage stage, source, as-of time, exclusions, and delayed/partial state for every metric.
- [ ] Reconcile aggregate drill-down and enforce territory/role scope in API and UI tests.

**Done gate:** Pilot operators can identify and drill into sync/verification exceptions without false zeros.

### P0.21 Funnel and Verification Analytics — BUILD

**Feature:** [Funnel and verification analytics](campaign-performance-attribution-roi/funnel-verification-analytics/prd.md)

- [ ] Build lineage event model and stable cohort/time/exclusion definitions.
- [ ] Implement funnel conversion, backlog age, turnaround percentiles, quality/PAD/no-reference/provider/reason analysis.
- [ ] Distinguish attempts from final registration outcome and machine-human divergence from reviewer error.
- [ ] Add aggregate reconciliation, incomplete-cohort, privacy-threshold, and accessible chart-table tests.

**Done gate:** Stage totals reconcile to immutable lineage and one registration with multiple attempts is represented correctly.

### P0.22 Canonical Contribution Attribution — BUILD / BLOCKED

**Feature:** [Canonical contribution and attribution](campaign-performance-attribution-roi/canonical-contribution-attribution/prd.md)  
**Dependencies:** Canonical order, approved-attendance, attribution-window, and overlap-policy contracts.

- [ ] Define canonical order keys, duplicate quarantine, unresolved mapping, late-event, and correction contracts.
- [ ] Implement deterministic eligibility, attribution window, and approved overlap rule.
- [ ] Persist source-event lineage, canonical ID, rule/version, campaign allocation, and processing time.
- [ ] Add replay, duplicate event, ambiguous ID, overlapping campaign, late event, and recomputation tests.
- [ ] Enforce contribution/association wording in UI and export.

**Done gate:** One canonical order counts once per governed metric and all excluded/unresolved populations are visible.

### P0.23 Service Health and Reconciliation — BUILD

**Feature:** [Service health and reconciliation](integrity-operational-control/service-health-reconciliation/prd.md)

- [ ] Define stage reconciliation across profile request, upload, provider, CRM, notification, and analytics correlation IDs.
- [ ] Build dependency health, latency, last success, backlog count/age, error class, and affected-record views.
- [ ] Implement authorized idempotent re-query/replay/quarantine/release/mark-reconciled controls.
- [ ] Add masking, reason/audit, rate limit, duplicate-replay, orphan, and partial-commit tests.

**Done gate:** Operators can locate a stopped stage and remediate it without editing data or duplicating business outcomes.

## 8. P1 — Carpenter 360 and Operational Depth

### P1.1 Authoritative Identity Overview — BUILD / BLOCKED

**Feature:** [Authoritative identity overview](carpenter-360-engagement-history/authoritative-identity-overview/prd.md)

- [ ] Build Sales Eco-ID-based profile repository, field-level scope, masking, source, and freshness model.
- [ ] Build A-01 overview header and governed summary counts with partial-source states.
- [ ] Route corrections to Sales Eco stewardship; prohibit local master mutation.
- [ ] Add sensitive-access audit, unavailable-source, stale-field, and 200% zoom tests.

**Done gate:** The overview is read-only, source-labeled, and never becomes a shadow master.

### P1.2 Campaign and Attendance Timeline — BUILD

**Feature:** [Campaign and attendance timeline](carpenter-360-engagement-history/campaign-attendance-timeline/prd.md)

- [ ] Define timeline event adapter for registration, notice, attempt, sync, advisory, CRM, reward, and correction events.
- [ ] Implement deterministic chronological grouping while retaining each attempt and source timestamp.
- [ ] Build filters and permission-aware drill-down without loading protected evidence by default.
- [ ] Test return/recapture, corrections, delayed rewards, missing events, and restricted evidence.

**Done gate:** Original and corrective events remain visible, and CRM outcome is clearly authoritative.

### P1.3 Commercial History and Attribution — BUILD / BLOCKED

**Feature:** [Commercial history and attribution](carpenter-360-engagement-history/commercial-history-attribution/prd.md)

- [ ] Build canonical-order history repository with source freshness and reconciliation state.
- [ ] Render attribution method/window/version and attributed, unattributed, excluded, delayed, and unavailable states.
- [ ] Apply overlap policy consistently with the canonical contribution service.
- [ ] Add duplicate order, delayed feed, recomputation, scope, and accessible-table tests.

**Done gate:** Carpenter history reconciles to canonical orders and never labels P0 contribution as causal ROI.

### P1.4 Explainable Signals and Investigations — BUILD

**Feature:** [Explainable signals and investigations](integrity-operational-control/explainable-signals-investigations/prd.md)

- [ ] Define approved duplicate, velocity, geofence, device, advisory, and access signal rules with versions/limitations.
- [ ] Build scoped investigation queue, grouping, assignment, notes, evidence links, escalation, and status.
- [ ] Implement mandatory human disposition and separately authorized downstream action.
- [ ] Add deterministic replay, false-positive, corrected-source, masking, and no-auto-rejection tests.

**Done gate:** Every signal is explainable and advisory; no signal directly changes attendance or sanctions a person.

## 9. P1 — Policy and Sensitive-Access Governance

### P1.5 Configuration Catalog and Versioning — BUILD

**Feature:** [Configuration catalog and versioning](configuration-audit-policy-administration/configuration-catalog-versioning/prd.md)

- [ ] Define typed schemas for lifecycle, windows, reasons, thresholds, notices, retention, and integrations.
- [ ] Build AD-01 catalog, inheritance/override source, immutable drafts, effective periods, dependencies, and impact preview.
- [ ] Add field/range/reference/language/effective-date validation and restricted-value masking.
- [ ] Persist effective configuration version on governed business events and test historical resolution.

**Done gate:** Drafts are valid, immutable, permission-scoped, and reproducible without exposing secrets.

### P1.6 Approval, Activation and Rollback — BUILD

**Feature:** [Approval, activation and rollback](configuration-audit-policy-administration/approval-activation-rollback/prd.md)

- [ ] Implement submit/approve/return/reject with segregation of duties, reasons, warnings, and optimistic concurrency.
- [ ] Implement server-time immediate/scheduled activation and incompatible-version checks.
- [ ] Pin in-flight sessions/events according to approved version policy and monitor propagation.
- [ ] Implement rollback as a newly approved version based on a prior version; never rewrite history.
- [ ] Test stale approval, duplicate activation, failed propagation, rollback, and notification separation.

**Done gate:** Exactly one effective version governs a scope/time, with complete approval and rollback lineage.

### P1.7 Audit, Retention and Restricted Settings — BUILD / BLOCKED

**Feature:** [Audit, retention and restricted settings](configuration-audit-policy-administration/audit-retention-restricted-settings/prd.md)  
**Dependencies:** Approved retention schedule, legal-hold process, export approval policy.

- [ ] Build scoped audit search by actor, subject/case, action, module, outcome, scope, time, and correlation ID.
- [ ] Implement masked diffs, tamper-evident ingestion status, and restricted setting metadata.
- [ ] Build retention execution status, holds/releases, eligible/held/deleted/failed counts, and remediation.
- [ ] Implement async governed exports with purpose, approval, watermark, expiry, and access audit.
- [ ] Add secret/media redaction, self-audit, hold, expiry, and export authorization tests.

**Done gate:** Audit history is reconstructable, retention is observable, and secrets/media never enter general audit or export.

### P1.8 Sensitive Access Monitoring — BUILD

**Feature:** [Sensitive access monitoring](integrity-operational-control/sensitive-access-monitoring/prd.md)

- [ ] Ingest evidence-open, reveal, export, and restricted-setting audit events with completeness status.
- [ ] Implement versioned volume, off-hours, broad-scope, repeated-subject, and missing-case-context detections.
- [ ] Build restricted review queue with minimized identity, assignment, explanation, disposition, and escalation.
- [ ] Audit monitoring-tool access and link, but do not directly change, user roles.
- [ ] Add incomplete-ingestion, no-auto-revocation, retention, and false-positive tests.

**Done gate:** Unusual access is reviewable without embedding evidence or triggering automatic punitive action.

## 10. P2 — Governed Optimization

### P2.1 Governed ROI, Comparison and Drill-Down — BUILD / BLOCKED

**Feature:** [Governed ROI, comparison and drill-down](campaign-performance-attribution-roi/governed-roi-comparison-drilldown/prd.md)  
**Dependencies:** Approved causal method, complete cost basis, mature attribution window, cohort comparability rules, governance approval.

- [ ] Define versioned metric formula, numerator, denominator, currency, cost inclusions, exclusions, maturity, and comparability thresholds.
- [ ] Build campaign selection, normalized comparison, contribution/cost panels, and accessible chart/table views.
- [ ] Gate causal ROI/ranking until methodology, cost, maturity, and governance requirements all pass.
- [ ] Preserve definitions, filters, maturity labels, sources, and as-of time in drill-down/export.
- [ ] Add missing-cost, immature-window, incompatible-cohort, delayed-source, aggregate-reconciliation, and authorization tests.

**Done gate:** The product cannot display causal ROI or rankings before every governance gate is satisfied.

## 11. Cross-Cutting Test and Release Tasks

### P0.R1 Contract Test Suite

- [ ] Publish fixtures for auth/RBAC, campaign, Sales Eco identity, profile request, import, media, CRM, audit, order, and configuration APIs.
- [ ] Add consumer contract tests for field names, status vocabulary, idempotency, concurrency/version, error taxonomy, and pagination.
- [ ] Fail CI when a fixture introduces an unknown status or removes a required privacy/audit field.

### P0.R2 Critical End-to-End Journeys

- [ ] Campaign create -> validate -> submit -> return -> correct -> approve -> session start.
- [ ] Authoritative registration and profile-request reconciliation.
- [ ] Bulk dry run -> partial commit -> safe retry.
- [ ] Online and offline capture -> restart -> sync -> CRM review -> approve.
- [ ] CRM return -> field recapture -> second decision with immutable attempt history.
- [ ] Dashboard exception -> case drill-down -> reconciled aggregate.
- [ ] Configuration draft -> independent approval -> activation -> historical version audit.

### P0.R3 Security, Privacy and Accessibility Release Gate

- [ ] Threat-model auth refresh, route guarding, local evidence, signed URLs, audit buffering, exports, and support tooling.
- [ ] Verify NID/phone/media/token redaction from UI, logs, URLs, analytics, notifications, and exports.
- [ ] Complete WCAG 2.2 AA web checks and Android TalkBack checks on critical journeys.
- [ ] Obtain legal/security sign-off for notice, manual route, retention, evidence access, and audit behavior.

### P0.R4 Reliability and Performance Gate

- [ ] Run offline failure matrix on supported Android devices under weak/intermittent network and process restart.
- [ ] Load-test campaign/CRM tables, import jobs, audit search, and analytics drill-down at pilot volumes.
- [ ] Measure app startup, local search, capture commit, queue drain, dashboard freshness, and evidence-view latency.
- [ ] Document operational alerts, reconciliation runbook, rollback path, and known pilot limits.

### P0.R5 Schema Migration Retry Safety

**Defect:** `from2To3` (the schema-v3 step added by P0.5) uses `addColumn`, which is not idempotent. Drift does not wrap migration steps in a transaction, and `user_version` is bumped only after `onUpgrade` returns, so a device killed mid-migration re-runs the step, raises `duplicate column name`, and that throws out of `beforeOpen` — the database then fails to open on that launch and on every launch after, because the version never advances. Queued attendance evidence becomes unreachable with no in-app recovery path.  
**Widened by P0.6:** a v2 device's `onUpgrade` used to be `from2To3` alone before its version bump; it is now `from2To3` and then `from3To4`'s three statements before a single bump. `from3To4`'s `INSERT OR REPLACE` cannot help such a device, because the retry dies inside `from2To3` before v4 is ever reached.  
**Priority:** blocking before the first pilot device, not backlog. It is latent only because v2 existed solely between P0.3 and P0.5 and the app is pre-pilot.

- [ ] Wrap `runMigrationSteps` in a transaction instead of adding another per-step idempotency idiom. Transactions are supported inside `beforeOpen` (`_BeforeOpeningExecutor.beginTransactionInContext` delegates to the base executor) and let SQLite roll DDL back cleanly, which removes the whole category rather than one instance of it.
- [ ] Add a v2 -> v4 retry-safety test in the style of the v3 -> v4 one added in P0.6 (`test/core/storage/migration_test.dart`, "v3 to v4 survives being re-run after a half-applied migration").

## 12. External Decisions and Owners

| Decision/contract | Required by | Suggested owner | Target priority |
|---|---|---|---|
| Authentication, refresh, RBAC and org/territory claims | P0.1 | Identity/Platform | P0 first |
| Durable audit ingestion and correlation schema | P0.4, P1.7-P1.8 | Security/Platform | P0 first |
| Legal-approved bilingual notice and manual route | P0.3, P0.15 | Legal/Privacy/Product | P0 first |
| Signed media upload/view, encryption and retention | P0.4, P0.16, P0.18 | Media/Security | P0 first |
| Campaign/session/import APIs and idempotency | P0.6-P0.12 | Campaign service | P0 |
| Sales Eco master/profile-request contracts | P0.10-P0.11, P1.1 | Sales Eco/Data | P0 |
| CRM queue/case/decision and concurrency | P0.17-P0.19 | CRM team | P0 |
| Canonical order and overlap policy | P0.22, P1.3 | Data/Commercial | P0/P1 |
| Retention, hold and governed export policy | P1.7 | Legal/Security | P1 |
| Causal method, cost basis and ROI gate | P2.1 | Analytics/Finance/Governance | P2 |

## 13. Recommended First Three Iterations

### Iteration 1 — Trust and Contract Closure

- P0.1 authentication/RBAC lifecycle.
- P0.3 notice schema and persistence.
- P0.4 correlation, audit emission, and signed-media contract.
- P0.R1 contract fixtures and CI validation.
- Start P0.13 mobile readiness and P0.17 CRM queue domain scaffolds behind interfaces.

### Iteration 2 — Controlled Capture Path

- P0.9 server/session readiness closure.
- P0.10-P0.11 authoritative registration/profile reconciliation.
- P0.13-P0.16 mobile readiness, quality checks, capture audit, and sync failure matrix.
- P0.R3 field privacy/accessibility checks.

### Iteration 3 — Final Decision and Pilot Visibility

- P0.17-P0.19 CRM queue, secure evidence, and one-decision enforcement.
- P0.20-P0.21 exception dashboard and lineage funnel.
- P0.23 service reconciliation.
- P0.R2 end-to-end online/offline/return-recapture journeys.
