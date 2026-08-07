# 1. Epic Name

Shared Sales Ecosystem Experience and Trust Controls

## 2. Goal

**Problem:** Campaign administration, mobile attendance, CRM verification and analytics serve different jobs, but they operate on the same identities, statuses and sensitive evidence. Separate interaction models or inconsistent terminology would create reconciliation errors, permission leaks and avoidable training cost. The product must also remain usable across corporate Android devices and dense web workflows in Bangla and English.

**Solution:** Extend the existing BMD Sales Ecosystem shell with a shared role- and scope-aware experience, controlled status vocabulary, responsive components, bilingual content, privacy controls, audit context and common error-recovery states. Apply BMD brand tokens over Material 3 interactions without introducing a second campaign brand or navigation model.

**Impact:** All downstream epics can deliver consistent workflows faster, users can understand a record across surfaces, and security/accessibility controls become release criteria rather than late remediation.

## 3. User Personas

- **Campaign Creator and Approver:** Need consistent navigation, status and scoped actions across campaign workflows.
- **Field Attendance User:** Needs large-touch, bilingual, resilient mobile interactions with unambiguous sync state.
- **CRM Verifier and Supervisor:** Need keyboard-efficient, accessible evidence review with strict privacy boundaries.
- **Management and Reporting Viewer:** Need stable definitions, freshness and permission-aware drill-down.
- **Org/BMD Admin, Support, Security and Auditor:** Need traceability, controlled access and diagnostic context.

## 4. High-Level User Journeys

1. A user signs in and sees only modules, organizations, territories and actions allowed by role and scope.
2. A user follows a record from campaign to registration, attendance, verification and analytics using the same labels and lineage.
3. A user switches between Bangla and English where supported; a purpose notice records the selected language and version.
4. A keyboard or assistive-technology user completes critical web workflows without losing status, identity or primary-action context.
5. Support or audit personnel trace a material action through actor, time, scope and correlation ID without exposing unnecessary sensitive data.

## 5. Business Requirements

### Functional Requirements

- Extend the existing Sales Ecosystem navigation, organization context, authentication and role conventions.
- Enforce role plus organization/territory scope before displaying or executing an action.
- Provide one controlled vocabulary and renderer for campaign, registration, attendance, import, verification and integrity states.
- Preserve an attendance lineage of captured, queued, uploaded, processed, decided and counted states across consuming epics.
- Provide responsive web, tablet and mobile shells matching the documented breakpoint priorities.
- Provide reusable interaction patterns for forms, tables, search, filters, dialogs, sheets, evidence and exception-first dashboards.
- Support English and Bangla labels and critical notices with equivalent meaning, hierarchy and wrapping.
- Record correlation-aware audit events for material changes, decisions, exports and sensitive evidence access.
- Represent loading, empty, partial, delayed, failed, retry, permission-denied and reconciliation states explicitly.
- Keep notifications non-authoritative: workflow completion must not be rolled back when notification delivery fails.

### Non-Functional Requirements

- Meet WCAG 2.2 AA for supported web journeys and equivalent Android accessibility practices.
- Support visible focus, logical tab order, accessible names, 200% browser zoom and alternatives to keyboard shortcuts.
- Never rely on color alone; maintain required text, control and meaningful-graphic contrast.
- Use minimum 48 x 48 px field touch targets and preserve status, identity, privacy and sync warnings on narrow screens.
- Encrypt sensitive data at rest and in transit; use short-lived signed media access and disable download by default.
- Mask NID and phone data by role and context; never place full NID in URLs, notifications or general exports.
- Log every authorized sensitive-image open/reveal and expose raw vendor payloads only to explicitly authorized support/security roles.
- Maintain a shared idempotency and error taxonomy so retries do not duplicate material business actions.
- Use the BMD token system consistently; visual design must pass the documented color and component checks.

## 6. Success Metrics

| KPI | Target |
|---|---|
| Critical supported journeys passing accessibility acceptance | 100% before rollout |
| Material actions producing complete audit events | 100% |
| Sensitive evidence opens producing access-log events | 100% |
| Status labels that differ for the same state across surfaces | 0 |
| Critical bilingual notices with approved semantic parity and version records | 100% |
| Unauthorized route/action attempts blocked before data disclosure | 100% in security tests |
| UI defects caused by unsupported 320 px to large-desktop layouts | 0 release-blocking defects |

## 7. Out of Scope

- Replacing the enterprise identity provider or Sales Ecosystem organization model.
- Creating a standalone campaign brand, shell or duplicate navigation hierarchy.
- Defining campaign, registration, verification or analytics business rules owned by the downstream epics.
- Exposing raw biometric scores to field users or ordinary business roles.
- Building automated identity decisions; machine assistance remains governed by the verification epic.
- Replacing organization-wide master-data governance or audit platforms.

## 8. Business Value

**High.** This is a mandatory enabler for every user-facing epic and directly reduces regulatory, accessibility, reconciliation and training risk. Shared status, security and interaction rules also prevent each surface from implementing incompatible versions of the same workflow.

## Source Traceability and Dependencies

- **Guideline:** Sections 1-5, 9.4, 10-13; Appendix B; NFR-01 to NFR-14.
- **Design artifacts:** Foundations and shared component specimens, including status, lineage, accessibility, evidence, states and shell.
- **Depends on:** Enterprise auth/RBAC, organization context, audit/event and media-security contracts.
- **Enables:** All other epics in this portfolio.