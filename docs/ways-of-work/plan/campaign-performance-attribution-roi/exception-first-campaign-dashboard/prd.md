# 1. Feature Name

Exception-First Campaign Performance Dashboard

## 2. Epic

- [Parent Epic: Campaign Performance, Attribution and ROI](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 7, 11 and 14

## 3. Goal

**Problem:** Leaders need actionable campaign performance, not a decorative KPI wall. Aggregates without freshness, lineage definitions or backlog exceptions can conceal operational failures.

**Solution:** Provide scoped KPI bands, exception panels and drill-downs with explicit captured/processed/approved definitions, freshness and exclusions.

**Impact:** Managers identify campaigns requiring intervention and interpret metrics consistently.

## 4. User Personas

- Campaign manager, leadership viewer, operations lead and analyst.

## 5. User Stories

- As a manager, I want exceptions before ordinary performance so that I can act quickly.
- As a leader, I want KPI definitions and freshness so that numbers are not misinterpreted.
- As an analyst, I want filters and drill-down reconciliation so that totals are defensible.
- As a user, I want delayed/unavailable data distinguished from zero.

## 6. Requirements

### Functional Requirements

- Provide role/scoped filters for period, campaign, type, territory, owner and status.
- Show registered, captured, processed, approved, rejected, returned, pending sync/review, SLA and attributable commercial KPIs.
- Define every KPI denominator, lineage stage, source, as-of time and exclusion policy.
- Prioritize sync backlog, verification SLA breach, low approval, no-reference and delayed-source exceptions.
- Support trend and campaign table with next action and controlled status vocabulary.
- Drill from aggregate to filtered campaign/session/case population under permission.
- Preserve filter context and expose removable active filters.
- Display partial/delayed/unavailable states without substituting zero.

### Non-Functional Requirements

- Reconcile displayed aggregates to governed detailed populations.
- Meet agreed dashboard load/freshness targets and show last successful refresh.
- Use accessible chart alternatives and responsive tables.
- Prevent out-of-scope populations from leaking through totals.

## 7. Acceptance Criteria

- **Given** an SLA breach and ordinary campaigns, **when** dashboard loads, **then** the breach appears in prioritized exceptions.
- **Given** a KPI, **when** definition is opened, **then** denominator, lineage stage, source, freshness and exclusions are available.
- **Given** drill-down from Approved attendance, **when** detail opens, **then** its population reconciles to the scoped KPI.
- **Given** a delayed source, **when** dependent KPI renders, **then** it is marked delayed/partial and not zero.
- **Given** a territory-limited user, **when** filters/counts load, **then** no other territory data is inferable.

## 8. Out of Scope

- Final CRM decisions, campaign editing and causal ROI conclusions.
- Arbitrary report builder in MVP.
