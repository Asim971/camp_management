# 1. Epic Name

Configuration, Audit and Policy Administration

## 2. Goal

**Problem:** Campaign types, status rules, reason codes, SLA, attendance windows, geofences, reference priority, retention and attribution rules change over time. Unversioned or immediate configuration changes can alter active workflows, invalidate historical reporting and expose sensitive thresholds. Material product behavior must be change-controlled, explainable and reversible.

**Solution:** Provide desktop administration for versioned, scoped, effective-dated configuration with impact preview, approval, rollback and immutable audit history. Restrict raw thresholds and secrets while still telling unauthorized admins that governed settings exist and who owns them.

**Impact:** Business policy can evolve without code releases or silent historical changes, and auditors can reconstruct which rules governed any campaign, capture, decision or metric.

## 3. User Personas

- **Org/BMD Admin:** Proposes scoped business configuration changes.
- **Product Owner:** Governs campaign/status and workflow policy.
- **Security/Privacy Administrator:** Controls sensitive thresholds, retention and access policy.
- **Support/Operations:** Reviews effective configuration and retries failed application/reconciliation.
- **Approver/Auditor:** Approves high-risk changes and reconstructs history.

## 4. High-Level User Journeys

1. An admin selects a configuration category and creates a new draft version from the active value.
2. The system shows before/after values and the impact on campaigns, sessions and already-decided records.
3. The admin supplies reason, scope, effective date and approver and submits the version.
4. An eligible approver approves or returns the change; scheduled activation occurs at the effective date.
5. A failed application remains visible and can be retried or rolled back under policy without erasing history.
6. An auditor traces active and superseded versions, actor, scope, time, before/after and correlation ID.

## 5. Business Requirements

### Functional Requirements

- Manage versioned categories for campaign types, controlled statuses, reason codes, verification SLA, attendance windows, geofence, reference priority, score bands, retention, attribution windows and notifications.
- Scope configuration by organization, campaign type, territory or other approved business boundary.
- Create draft versions from current effective configuration and show before/after values.
- Require reason, approver and future effective date for high-risk changes.
- Validate that an effective date does not conflict with active sessions or retroactively alter completed/decided records.
- Preview affected campaigns, sessions, records and expected behavioral change before submission.
- Enforce segregation of duties and configured approval levels for high-risk categories.
- Support Draft, Pending approval, Scheduled, Active, Superseded and Failed application states.
- Activate approved versions at the effective time and preserve the governing version on resulting business facts.
- Support retry and rollback under policy; a rollback creates a new auditable event/version rather than deleting history.
- Prevent retroactive recomputation unless a separately authorized, explicit reconciliation process exists.
- Provide searchable audit history with category, version, before/after, actor, approver, time, scope, reason and correlation ID.
- Restrict raw score thresholds and sensitive settings to authorized Product/Security roles.
- Never expose verification vendor credentials in the product at any role.
- Tell unauthorized admins that a restricted setting exists, its business-facing band/meaning and the owning role, without showing the raw value.
- Provide authorized retention/policy metadata and prohibit ordinary users from arbitrary evidence deletion.
- Preserve notification templates/version and make notification failure visible to support without reversing committed workflow.

### Non-Functional Requirements

- Configuration reads and writes must be strongly authorized and server-enforced.
- Every business fact requiring policy interpretation must retain or resolve the governing configuration version.
- Audit history must be immutable, queryable and exportable only under permission.
- Activation, retry and rollback operations must be idempotent and concurrency-safe.
- Scheduled changes must use an explicit timezone and dependable server time.
- Configuration failures must fail closed where safety/privacy controls are involved and expose actionable operations state.
- Desktop administration must meet WCAG 2.2 AA; optional mobile access is read-only.
- Secrets must be stored outside product configuration views and logs.

## 6. Success Metrics

| KPI | Target |
|---|---|
| High-risk changes with reason, approval, scope and effective date | 100% |
| Business facts traceable to governing configuration version | 100% |
| Retroactive changes to completed/decided records outside approved reconciliation | 0 |
| Raw restricted thresholds disclosed to unauthorized roles | 0 |
| Vendor credentials displayed in product UI/log export | 0 |
| Failed applications/rollbacks retained in history | 100% |
| Configuration activation replays creating duplicate effects | 0 |

## 7. Out of Scope

- General enterprise identity/role administration.
- Storing or displaying vendor secrets and credentials.
- Arbitrary deletion of audit or evidence records.
- Silent retroactive reclassification of attendance or analytics.
- Infrastructure-as-code or deployment configuration unrelated to business behavior.
- Full configuration editing on mobile.

## 8. Business Value

**High.** Versioned policy administration allows the product to support multiple organizations and evolving controls safely, while providing the historical reproducibility needed for verification, privacy, analytics and audit.

## Source Traceability and Dependencies

- **Requirements:** Original PRD F2, F13, FR-015; guideline CM-FR-090 to CM-FR-095 and sensitive-evidence/retention controls.
- **Design ownership:** AD-01 Configuration and audit.
- **Depends on:** Organization/RBAC, server time/scheduler, immutable audit, policy owners and legal/security approval.
- **Provides to:** All epics through versioned reason codes, SLA, windows, retention, reference and attribution policies.