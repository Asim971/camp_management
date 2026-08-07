# Campaign Management Epic Portfolio

This portfolio decomposes the Sales Ecosystem Campaign Management and Carpenter Attendance Verification program into outcome-oriented epics. It is based on:

- `Campaign_Management_Carpenter_Attendance_Verification_PRD.md`
- `ACSL_Carpenter_Campaign_Management_UI_UX_Design_Guideline_v1_0.md`
- The 33 design-system specimens under `design/src/`
- `ARCHITECTURE_Flutter.md` and `TASK_BREAKDOWN.md` as feasibility and dependency inputs

## Portfolio Goal

Deliver a controlled campaign lifecycle in which every participant resolves to one authoritative Sales Eco identity, every attendance record preserves its evidence lineage, CRM makes the final MVP verification decision, and management can distinguish campaign activity from verified commercial contribution.

## Epic Map

| Sequence | Epic | Primary outcome | Design ownership | Release position |
|---|---|---|---|---|
| 1 | [Shared Sales Ecosystem Experience and Trust Controls](shared-sales-ecosystem-experience/epic.md) | One secure, accessible and consistent product foundation | Foundations and shared components | Enabler / P0 |
| 2 | [Campaign Lifecycle and Session Operations](campaign-lifecycle-session-operations/epic.md) | Govern campaigns from draft through completion | W-02, W-03, W-04, W-05 | MVP / P0 |
| 3 | [Participant Identity, Registration and Bulk Import](participant-identity-registration-import/epic.md) | Register eligible participants without creating a shadow master | W-06, W-07 | MVP / P0 |
| 4 | [Offline Field Attendance Capture](offline-field-attendance/epic.md) | Capture trustworthy attendance under field conditions | M-01, M-02, M-03, M-04 | MVP / P0 |
| 5 | [Human-Led Attendance Verification](human-led-attendance-verification/epic.md) | Produce auditable final attendance decisions | C-01, C-02 | MVP / P0 |
| 6 | [Carpenter 360 Engagement History](carpenter-360-engagement-history/epic.md) | Connect identity, campaign, attendance and order history | A-01 | MVP-lite / P1 depth |
| 7 | [Campaign Performance, Attribution and ROI](campaign-performance-attribution-roi/epic.md) | Measure funnel and verified commercial contribution without double counting | W-01, A-02 | P0 contribution / P1 ROI |
| 8 | [Integrity and Operational Control](integrity-operational-control/epic.md) | Resolve explainable integrity, sync and reconciliation exceptions | A-03 | P1 |
| 9 | [Configuration, Audit and Policy Administration](configuration-audit-policy-administration/epic.md) | Govern behavior through versioned configuration and complete audit | AD-01 | MVP controls / P1 UI |

## Governing Product Decisions

1. **Human decision authority:** CRM/CLM is the final MVP decision-maker. Quality, liveness/PAD and 1:1 comparison outputs are advisory and remain separate from the human decision.
2. **Authoritative identity:** Carpenter is the configured MVP audience. The domain may later support other audience types, but campaign records must link to an authoritative Sales Eco identity or remain `Pending profile sync`; the module does not create a local shadow master.
3. **Evidence lineage:** Captured, queued, uploaded, processed, reviewed and counted are distinct states. Capture success never implies upload or approval success.
4. **Commercial language:** P0 reports campaign-linked contribution. Incremental uplift and ROI require approved cost, baseline and attribution methods and are P1 outcomes.
5. **Canonical counting:** Executive order totals use one verified canonical order ID and canonical pieces. Multiple source, field, CRM or fulfillment credits never multiply the order quantity.
6. **Controlled vocabulary:** Campaign, registration, attendance, import and integrity statuses are shared across web, mobile, notifications and analytics.

## Cross-Epic Success Measures

| Measure | Pilot target |
|---|---|
| Campaigns following the controlled lifecycle | 100% |
| Captured attendance mapped to a participant and live evidence | At least 95% |
| Captured records receiving a final decision within agreed SLA | At least 90% |
| Offline captures lost after app restart or network interruption | 0 |
| Executive order quantity duplicated through multiple credits | 0 |
| Material actions and sensitive evidence views with an audit event | 100% |
| Supported critical journeys meeting WCAG 2.2 AA/equivalent Android accessibility | 100% before rollout |

## Shared Dependencies and Decisions Required

- Sales Eco carpenter-master, profile-request, authentication/RBAC and organization-scope contracts.
- Secure media storage, short-lived signed access, encryption and retention contracts.
- Server-side idempotency, optimistic concurrency, audit and event-delivery contracts.
- Order-fact canonicalization, attribution facts, cost sources and reconciliation ownership.
- Legal approval of bilingual purpose notice, consent records, manual route and retention policy.
- Business confirmation of campaign/audience approval object, MVP audience scope, reason codes, SLA and walk-in policy.

## Delivery Sequence

The shared foundation enables campaign administration, participant registration and field capture in parallel. Field capture feeds human verification; approved decisions then feed Carpenter 360 and analytics. Integrity operations and configuration/audit controls span the flow and must be operational before pilot scale, even where their full management screens are delivered after MVP.

## Execution Backlog

The [Prioritized Task and Subtask Backlog](PRIORITIZED_TASK_BREAKDOWN.md) converts all 32 feature PRDs into remaining implementation work, ordered by pilot blockers, operational depth and governed optimization. It distinguishes existing screens that require verification or hardening from features that still require a production build.

## Feature PRD Map

| Epic | Features |
|---|---|
| Shared Sales Ecosystem Experience | [Adaptive shell and scoped access](shared-sales-ecosystem-experience/adaptive-shell-scoped-access/prd.md); [Design system and status vocabulary](shared-sales-ecosystem-experience/design-system-status-vocabulary/prd.md); [Bilingual localization and notices](shared-sales-ecosystem-experience/bilingual-localization-notices/prd.md); [Sensitive evidence and audit controls](shared-sales-ecosystem-experience/sensitive-evidence-audit-controls/prd.md); [Accessibility and resilient states](shared-sales-ecosystem-experience/accessibility-resilient-states/prd.md) |
| Campaign Lifecycle and Session Operations | [Campaign discovery and actions](campaign-lifecycle-session-operations/campaign-discovery-actions/prd.md); [Campaign authoring and validation](campaign-lifecycle-session-operations/campaign-authoring-validation/prd.md); [Campaign approval and correction](campaign-lifecycle-session-operations/campaign-approval-correction/prd.md); [Session readiness and lifecycle](campaign-lifecycle-session-operations/session-readiness-lifecycle/prd.md) |
| Participant Identity, Registration and Import | [Authoritative search and registration](participant-identity-registration-import/authoritative-search-registration/prd.md); [Profile request and reconciliation](participant-identity-registration-import/profile-request-reconciliation/prd.md); [Dry-run bulk import](participant-identity-registration-import/dry-run-bulk-import/prd.md) |
| Offline Field Attendance | [Mobile session readiness](offline-field-attendance/mobile-session-readiness/prd.md); [Registered carpenter selection](offline-field-attendance/registered-carpenter-selection/prd.md); [Purpose notice and camera capture](offline-field-attendance/purpose-notice-camera-capture/prd.md); [Durable offline sync and status](offline-field-attendance/durable-offline-sync-status/prd.md) |
| Human-Led Verification | [Prioritized verification queue](human-led-attendance-verification/prioritized-verification-queue/prd.md); [Secure evidence review](human-led-attendance-verification/secure-evidence-review/prd.md); [Decision, return and recapture](human-led-attendance-verification/decision-return-recapture/prd.md) |
| Carpenter 360 | [Authoritative identity overview](carpenter-360-engagement-history/authoritative-identity-overview/prd.md); [Campaign and attendance timeline](carpenter-360-engagement-history/campaign-attendance-timeline/prd.md); [Commercial history and attribution](carpenter-360-engagement-history/commercial-history-attribution/prd.md) |
| Campaign Performance, Attribution and ROI | [Exception-first campaign dashboard](campaign-performance-attribution-roi/exception-first-campaign-dashboard/prd.md); [Funnel and verification analytics](campaign-performance-attribution-roi/funnel-verification-analytics/prd.md); [Canonical contribution and attribution](campaign-performance-attribution-roi/canonical-contribution-attribution/prd.md); [Governed ROI, comparison and drill-down](campaign-performance-attribution-roi/governed-roi-comparison-drilldown/prd.md) |
| Integrity and Operational Control | [Explainable signals and investigations](integrity-operational-control/explainable-signals-investigations/prd.md); [Service health and reconciliation](integrity-operational-control/service-health-reconciliation/prd.md); [Sensitive access monitoring](integrity-operational-control/sensitive-access-monitoring/prd.md) |
| Configuration, Audit and Policy | [Configuration catalog and versioning](configuration-audit-policy-administration/configuration-catalog-versioning/prd.md); [Approval, activation and rollback](configuration-audit-policy-administration/approval-activation-rollback/prd.md); [Audit, retention and restricted settings](configuration-audit-policy-administration/audit-retention-restricted-settings/prd.md) |
