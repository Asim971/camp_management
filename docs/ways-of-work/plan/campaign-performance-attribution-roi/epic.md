# 1. Epic Name

Campaign Performance, Attribution and ROI

## 2. Goal

**Problem:** Management cannot evaluate campaigns reliably when target, registration, capture, verification and order data are fragmented or delayed. Activity can be mistaken for commercial impact, multiple order credits can inflate totals, and incomplete baseline/cost data can produce false ROI precision. Users need exception-first dashboards whose metrics reconcile to operational records.

**Solution:** Deliver campaign dashboard and analytics experiences that separate operational funnel, final verification, campaign-linked contribution, integrity and cost/ROI. Apply canonical order counting, visible definitions/freshness and permission-aware drill-down, and gate incremental uplift/ROI until approved methodology and complete inputs exist.

**Impact:** Campaign owners and management can act on exceptions, compare performance and understand verified commercial contribution without overstating causality or double counting.

## 3. User Personas

- **Campaign Admin/Marketing:** Monitors execution, exceptions and funnel leakage.
- **Management/Business Head:** Compares campaigns and verified contribution.
- **Finance Control:** Reviews approved cost inputs and ROI methodology.
- **Product/Data Analyst:** Maintains definitions, attribution and reconciliation quality.
- **CRM/Operations Supervisor:** Drills from backlog metrics into actionable queues.

## 4. High-Level User Journeys

1. A user opens the dashboard and sees SLA breaches, pending sync, failed import, no-reference and reconciliation exceptions before totals.
2. The user reviews target-to-registered-to-captured-to-verified funnel counts and rates, then drills into the underlying list.
3. The user distinguishes machine recommendation mix from final CRM decision mix.
4. The user reviews distinct canonical orders, pieces, product mix and repeat behavior within the approved attribution window.
5. The user compares campaigns/territories with denominator and sample-size warnings.
6. Finance-authorized users review cost efficiency and, only when inputs/method are approved, incremental uplift and ROI.
7. Delayed feeds, missing days, incomplete cost and reconciliation gaps remain visible and excluded according to definition rather than silently treated as zero.

## 5. Business Requirements

### Functional Requirements

- Provide a campaign dashboard ordered as exceptions, funnel, commercial contribution, integrity/quality and cost/ROI.
- Show active campaigns and an action-priority campaign table with owner, dates, status, registration, verified attendance and next action.
- Display target, registered, captured, verified, rejected and no-show counts with rates and denominators.
- Keep pending sync, processing and CRM review visibly excluded from verified attendance until final approval.
- Present machine recommendation and CRM final-decision distributions as separate series.
- Provide daily/weekly trends with explicit date grain, timezone, source and missing-data treatment.
- Show distinct canonical order count, canonical pieces, product mix and repeat-order windows for verified attendees.
- Enforce one canonical verified order ID and quantity once across all credits and order stages.
- Label P0 outputs as `campaign-linked contribution`, not incremental uplift or proven causality.
- Provide attribution window, exclusions and multiple-credit detail without multiplying executive totals.
- Display MT/RFT only as versioned secondary conversions from canonical pieces.
- Support campaign, territory, period, product and other approved filters with visible context.
- Support comparison and drill-down from national/organization to campaign, territory, session, carpenter and canonical order under permission.
- Provide every KPI with label, value, denominator where relevant, definition, source, freshness and drill destination.
- Show delayed feeds, partial facts, small samples, insufficient baseline, incomplete cost and reconciliation gaps.
- Exclude unresolved canonical orders and incomplete ROI inputs from affected totals while disclosing the exclusion.
- Calculate cost per registered, verified and attributed order when approved actual cost exists.
- Gate incremental uplift and ROI behind approved baseline/control methodology, attribution rules and complete cost data.
- Provide chart/table alternatives and permission-controlled exports carrying filter and definition metadata.

### Non-Functional Requirements

- Metric calculations and canonicalization must be server-authoritative and reproducible for the same data/version.
- Dashboard values must reconcile to drill-down records and disclose delayed update/freshness.
- Do not interpolate missing data silently or substitute missing feeds with zero.
- Meet WCAG 2.2 AA for charts through text alternatives, direct labels/table views and keyboard-accessible drill-down.
- Preserve organization/territory and commercial-data permissions at aggregate and row level.
- Support agreed dashboard response targets using pre-aggregation where required without sacrificing freshness metadata.
- Version metric definitions, attribution windows and unit conversions and retain historical reproducibility.
- Use neutral, non-accusatory integrity language and avoid opaque composite risk scores.

## 6. Success Metrics

| KPI | Target |
|---|---|
| Dashboard KPIs with definition, denominator/source and freshness | 100% |
| Dashboard values reconciling to drill-down facts | 100% within documented refresh window |
| Canonical order quantity duplicated through multiple credits/stages | 0 |
| P0 metrics mislabeled as incremental or causal ROI | 0 |
| Delayed/incomplete feeds presented as zero without warning | 0 |
| Authorized users reaching underlying exception records from dashboard | 100% of actionable metrics |
| Verified Campaign Attendance Rate | Pilot baseline, with target at least 90% final decision coverage within SLA |

## 7. Out of Scope

- Claiming causal incremental uplift from simple post-attendance windows.
- ROI publication without approved baseline/control method and complete cost data.
- Budget accounting, ledger management or incentive settlement.
- Counting unverified attendance in verified commercial contribution.
- Summing multiple order stages or credits as separate executive sales.
- Opaque fraud scores or automated punitive conclusions.

## 8. Business Value

**High.** This epic gives management a trusted view of execution and commercial contribution while protecting the organization from inflated counts and unsupported ROI claims. It also turns operational exceptions into actionable queues instead of vanity metrics.

## Source Traceability and Dependencies

- **Requirements:** Original PRD F12, FR-014 and program metrics; guideline CM-FR-080 to CM-FR-087.
- **Design ownership:** W-01 Campaign dashboard and A-02 Campaign analytics/ROI.
- **Release split:** P0 includes exception backlog, funnel, final verification and campaign-linked contribution. P1 adds governed uplift/ROI where methodology and cost readiness pass.
- **Depends on:** Campaign/registration/verification facts, canonical order facts, attribution/config versions, finance cost source and reconciliation health.
