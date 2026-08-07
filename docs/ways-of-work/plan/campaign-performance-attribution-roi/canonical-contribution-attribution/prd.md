# 1. Feature Name

Canonical Order Contribution Attribution

## 2. Epic

- [Parent Epic: Campaign Performance, Attribution and ROI](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 9, 10 and 14

## 3. Goal

**Problem:** Duplicated order events, changing identifiers and overlapping campaign windows can inflate commercial contribution. Attribution that hides its rule/version cannot be audited or corrected.

**Solution:** Reconcile source events to canonical orders, apply a versioned eligibility/window/overlap policy and expose attributed/unattributed/excluded populations.

**Impact:** P0 contribution reporting is reproducible and one canonical order counts once per governed metric.

## 4. User Personas

- Analytics user, commercial operations analyst, data steward and auditor.

## 5. User Stories

- As an analyst, I want deduplicated canonical orders so that source retries do not inflate contribution.
- As a steward, I want unresolved mappings visible so that data quality can be corrected.
- As a manager, I want attribution windows and overlap policy disclosed so that contribution is interpretable.
- As an auditor, I want rule versions and recomputation lineage so that reported changes are explainable.

## 6. Requirements

### Functional Requirements

- Ingest/reconcile order events using approved canonical identifiers and deduplication rules.
- Quarantine ambiguous/unresolved events rather than counting them provisionally as unique orders.
- Determine campaign eligibility from approved attendance, configured window and permitted commercial dimensions.
- Apply one versioned overlap policy: priority, split or other approved deterministic rule.
- Guarantee one canonical order contributes at most once to a non-splittable metric.
- Expose attributed, unattributed, excluded, delayed and unresolved totals and reasons.
- Store canonical order ID, source events, attribution rule/version, campaign allocation and processing time.
- Support correction/recomputation with prior-version traceability and affected-period indication.
- Label outputs contribution/association for P0.

### Non-Functional Requirements

- Provide deterministic replay and aggregate-to-order reconciliation.
- Encrypt/restrict commercial detail and enforce scoped queries.
- Monitor duplicate, unresolved and late-arriving-event rates.
- Avoid irreversible mutation of raw source lineage.

## 7. Acceptance Criteria

- **Given** repeated source events for one order, **when** processed, **then** one canonical order is counted.
- **Given** ambiguous identifiers, **when** reconciliation cannot resolve them, **then** events are excluded from attributed totals and surfaced as unresolved.
- **Given** eligibility for two campaigns, **when** attribution runs, **then** the configured overlap rule prevents duplicate total contribution.
- **Given** late-arriving events, **when** a period recomputes, **then** affected-period freshness and rule version update traceably.
- **Given** P0 output, **when** displayed/exported, **then** no causal lift/ROI claim is made.

## 8. Out of Scope

- Source-system order editing and causal inference.
- Finance-grade revenue recognition or settlement.
