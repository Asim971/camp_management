# 1. Feature Name

Governed ROI, Campaign Comparison and Drill-Down

## 2. Epic

- [Parent Epic: Campaign Performance, Attribution and ROI](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 10, 11 and 14

## 3. Goal

**Problem:** Comparison and ROI screens can imply causal performance when only contribution exists, especially with missing costs, immature windows or unmatched cohorts. Users need guardrails before ratios and rankings are shown.

**Solution:** Provide comparable-cohort selection and a maturity-gated ROI workspace that defaults to contribution until approved causal and cost requirements are met.

**Impact:** Decision-makers compare campaigns transparently without false precision.

## 4. User Personas

- Leadership viewer, campaign manager, finance/analytics user and governance approver.

## 5. User Stories

- As a manager, I want comparable campaigns and normalized metrics so that scale differences are visible.
- As a leader, I want method/maturity warnings so that contribution is not mistaken for causal return.
- As an analyst, I want cost and attribution lineage so that ROI can be reproduced.
- As a user, I want drill-down and exports to retain definitions so that context is not lost.

## 6. Requirements

### Functional Requirements

- Compare selected campaigns by type, period, territory, audience, approved attendance, contribution, cost and operational quality.
- Warn/block comparison when cohorts or source completeness are materially incompatible.
- Default P0 labels to attributed contribution, cost per approved attendee and other non-causal measures.
- Show causal ROI only when approved methodology, complete cost basis, mature attribution window and governance gate are active.
- Display formula, numerator, denominator, currency, cost inclusions, attribution version, as-of time and exclusions.
- Support table/chart views and drill-down to governed campaign/order/case populations.
- Preserve filters, metric definitions, maturity labels and exclusions in export.
- Mark rankings as unavailable when comparability thresholds fail.

### Non-Functional Requirements

- Use versioned metric definitions and reproducible calculations.
- Reconcile drill-down totals and apply scoped commercial-data access.
- Provide accessible chart alternatives and avoid color-only comparison.
- Never silently substitute missing cost or incomplete windows with zero.

## 7. Acceptance Criteria

- **Given** P0 contribution data only, **when** the workspace loads, **then** causal ROI language/ranking is unavailable.
- **Given** missing campaign cost, **when** ROI is requested, **then** the ratio is blocked and the missing basis is named.
- **Given** approved methodology and mature complete data, **when** ROI renders, **then** formula, sources, version and exclusions accompany it.
- **Given** incompatible cohorts, **when** comparison is attempted, **then** a comparability warning or block appears instead of a misleading rank.
- **Given** an export, **when** opened, **then** applied filters, definitions, maturity label and as-of time are included.

## 8. Out of Scope

- Designing/approving the causal methodology itself.
- Financial ledger replacement, automated budget allocation or predictive optimization.