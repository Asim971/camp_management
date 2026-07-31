# 1. Epic Name

Participant Identity, Registration and Bulk Import

## 2. Goal

**Problem:** Participant data can arrive from Sales Eco, spreadsheets and business-maintained lists, creating duplicate, stale and untraceable identities. A local free-text participant record would undermine Carpenter 360, attendance verification and order attribution. Large campaigns also need safe bulk handling without hiding row-level failures.

**Solution:** Resolve every campaign participant to an authoritative Sales Eco carpenter identity, support scoped search and eligibility checks, route missing identities through a profile-request workflow, and provide dry-run-first, idempotent bulk import with explicit row outcomes.

**Impact:** Campaign audiences become reusable and reconcilable, duplicate risk is controlled, and administrators can register large audiences without corrupting master data.

## 3. User Personas

- **Campaign Admin/Creator:** Selects and registers eligible carpenters.
- **Authorized Field User:** Performs limited single-person registration or confirmation where allowed.
- **Data/Integration Operator:** Monitors profile synchronization and import reconciliation.
- **Sales Eco Data Steward:** Resolves new-profile and master-data correction requests.
- **Support/Auditor:** Investigates duplicate, authorization and import outcomes.

## 4. High-Level User Journeys

1. An authorized user searches Sales Eco by name, carpenter ID or phone suffix within scope.
2. The user confirms the correct person using multiple identity cues, reviews freshness and eligibility, and registers the participant.
3. If no profile exists, the user submits a Sales Eco profile request and tracks `Pending profile sync` without creating a local master.
4. An admin downloads the approved template, uploads a file and runs a dry run.
5. The system classifies each stable row as valid, warning, duplicate, needs profile, unauthorized or error.
6. The admin commits confirmed valid rows idempotently and downloads a masked result/reconciliation file.

## 5. Business Requirements

### Functional Requirements

- Search the authoritative carpenter master within role, organization and territory scope.
- Show minimum necessary identity cues: profile thumbnail when allowed, ID, masked phone suffix, territory, dealer/retailer context, status and data freshness.
- Require confirmation using a second identity cue for similar names or ambiguous results.
- Evaluate campaign eligibility, active/inactive state, scope, prior registration and configured audience rules.
- Register only an authoritative linked identity; prohibit free-text-only shadow participant creation.
- Submit a master/profile request when no match exists and represent it as `Pending profile sync` until callback or reconciliation.
- Route corrections to the Sales Eco change process rather than editing source identity data locally.
- Maintain registration states: Invited, Registered, Pending profile sync, Ineligible, Waitlisted and Cancelled.
- Prevent duplicate campaign registration and flag high-confidence cross-source duplicate identities.
- Allow pre-start removal/cancellation only under policy and retain the audit history.
- Provide a versioned CSV template with stable row ID and documented required fields.
- Scan and validate uploads before processing; reject malformed or unauthorized files safely.
- Run a non-mutating dry run and show valid, warning, duplicate, needs-profile, unauthorized and error counts.
- Provide row-level reason, matched carpenter where applicable and corrective action; never use only a generic upload failure.
- Allow inspection/filtering of row outcomes and masked export of dry-run/results.
- Commit only explicitly confirmed rows using a job idempotency key and prevent replay duplication.
- Support asynchronous processing, progress, cancellation where safe, partial completion and retry of eligible failures.
- Reconcile committed rows to campaign registrations and preserve job-level and row-level audit.

### Non-Functional Requirements

- Do not cache or expose full NID or phone values in field/search results, URLs, logs or exports.
- Enforce authorization for every search result, row and committed registration server-side.
- Make large imports asynchronous beyond an agreed threshold and keep the UI responsive.
- Guarantee idempotent commit and deterministic row outcomes for the same file/configuration version.
- Show source and freshness for identity data and explicit degraded state when Sales Eco is unavailable.
- Preserve requests and uploaded job state through recoverable outages.
- Support keyboard-accessible tables, sticky identity columns and masked downloadable results.
- Emit complete audit records for search-sensitive reveals, registration, cancellation, import and profile request actions.

## 6. Success Metrics

| KPI | Target |
|---|---|
| Registered participants linked to one authoritative Sales Eco identity | 100%, excluding visible Pending profile sync requests |
| Local shadow master records created | 0 |
| Duplicate registrations committed for the same campaign/person | 0 high-confidence duplicates |
| Import rows with a stable, explainable outcome | 100% |
| Import commit replays creating additional registrations | 0 |
| Import success rate | Baseline by campaign type; at least 95% for valid template rows |
| Profile requests preserved through integration interruption | 100% |

## 7. Out of Scope

- Replacing Sales Eco master-data stewardship or directly overwriting core profiles.
- General-purpose CRM contact creation.
- Attendance capture or verification decisions.
- Unapproved walk-in creation; walk-in policy remains a business decision.
- Unsupervised fuzzy merging of identities.
- Bulk approval of identity or attendance outcomes.

## 8. Business Value

**High.** Authoritative identity resolution is the prerequisite for trustworthy attendance, Carpenter 360 and order attribution. Dry-run and idempotency controls also reduce high-volume operational and audit risk.

## Source Traceability and Dependencies

- **Requirements:** Original PRD G2, G6, F2-F6, FR-003-FR-005; guideline CM-FR-020 to CM-FR-036.
- **Design ownership:** W-06 Registration workspace and W-07 Bulk import job/results.
- **Depends on:** Sales Eco search/profile-request APIs, audience and eligibility configuration, idempotency and file-scanning services.
- **Hands off to:** Campaign sessions, field search/capture, Carpenter 360 and reconciliation operations.
