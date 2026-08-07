# 1. Feature Name

Commercial History and Campaign Attribution

## 2. Epic

- [Parent Epic: Carpenter 360 Engagement and Commercial History](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 5, 10 and 14

## 3. Goal

**Problem:** Users need post-campaign order context, but duplicated source events and overlapping campaigns can overstate contribution. Commercial history must separate canonical orders, attributed contribution and unproven causality.

**Solution:** Show canonical order history with source freshness and transparent campaign-attribution labels, rules and exclusions.

**Impact:** Users gain commercial context without double counting or overstating campaign effects.

## 4. User Personas

- Campaign manager, analytics viewer, CRM user and commercial operations analyst.

## 5. User Stories

- As a manager, I want canonical orders once so that duplicated source events do not inflate history.
- As an analyst, I want attribution method/window visible so that contribution can be interpreted.
- As a user, I want unmatched and excluded orders explained so that missing values are not mistaken for zero.
- As a user, I want overlapping campaign handling visible so that one order is not counted repeatedly.

## 6. Requirements

### Functional Requirements

- Display canonical order/date, permitted value/volume, dealer/product context, source and freshness.
- Deduplicate source events to one canonical order using governed keys and reconciliation status.
- Show campaign attribution label, rule/version, window and confidence/eligibility where approved.
- Apply one documented overlap policy and prevent one canonical order counting more than once in the same metric.
- Distinguish unattributed, excluded, delayed and unavailable orders.
- Support date, campaign and attribution filters plus source-record drill-down under permission.
- Label P0 outputs as contribution/association, not causal ROI.
- Retain attribution revisions and affected-period metadata.

### Non-Functional Requirements

- Reconcile totals to canonical source records and publish as-of timestamp.
- Enforce commercial-data scope and masking.
- Support accessible tables and large histories through server pagination.
- Use deterministic, versioned attribution logic.

## 7. Acceptance Criteria

- **Given** duplicate events for one canonical order, **when** history renders, **then** it appears once with reconciliation context.
- **Given** one order eligible for overlapping campaigns, **when** attribution runs, **then** the configured policy selects/splits it without duplicate total count.
- **Given** delayed order feed, **when** history loads, **then** freshness warning appears and unavailable values are not rendered as zero.
- **Given** P0 attribution, **when** labels render, **then** they use contribution/association language and disclose method/window.
- **Given** attribution rules change, **when** history is recomputed, **then** rule version and affected period remain traceable.

## 8. Out of Scope

- Editing source orders, finance settlement or claiming causal lift.
- Defining the enterprise canonical-order model outside approved contracts.
