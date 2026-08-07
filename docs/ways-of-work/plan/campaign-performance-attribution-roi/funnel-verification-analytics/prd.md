# 1. Feature Name

Attendance Funnel and Verification Analytics

## 2. Epic

- [Parent Epic: Campaign Performance, Attribution and ROI](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 5, 10 and 14

## 3. Goal

**Problem:** Teams cannot improve attendance operations without separating registration, capture, processing and human decisions. Provider advice, human outcome, no-reference routes and quality failures need distinct measures.

**Solution:** Provide reconciled funnel, turnaround, quality, advisory-divergence and reason-code analysis with governed cohort definitions.

**Impact:** Operational bottlenecks and evidence-quality problems become measurable without treating machine disagreement as reviewer error.

## 4. User Personas

- Operations manager, CRM supervisor, quality auditor and analyst.

## 5. User Stories

- As an operations manager, I want lineage conversion and age so that I can locate backlog.
- As a quality lead, I want reason distributions so that capture guidance can improve.
- As a supervisor, I want advisory/human divergence as an audit signal so that samples can be reviewed.
- As an analyst, I want cohort and denominator definitions so that comparisons are valid.

## 6. Requirements

### Functional Requirements

- Report Registered -> Captured -> Uploaded -> Processed -> CRM reviewed -> Approved/Rejected/Returned.
- Provide conversion, fallout, backlog age and turnaround percentiles by campaign/session/territory/device/time cohort.
- Analyze quality, PAD, no-reference, provider failure and CRM reason codes separately.
- Show advisory recommendation versus final human decision divergence without labeling disagreement as fraud/error.
- Distinguish first attempt, recapture and final registration outcome.
- Exclude test/cancelled/invalid records using versioned policy and disclose exclusions.
- Drill to governed case populations under permission.
- Show source freshness and incomplete cohorts.

### Non-Functional Requirements

- Use stable event-time definitions and reconcile stages to immutable lineage.
- Protect small cohorts and sensitive drill-down according to policy.
- Provide accessible tables for all charts.
- Retain metric/rule versions for historical reproducibility.

## 7. Acceptance Criteria

- **Given** one registration with two attempts, **when** funnel is viewed, **then** attempt metrics show two while final registration outcome counts once.
- **Given** provider High and human Reject, **when** divergence renders, **then** it is an audit signal rather than an automatic reviewer error.
- **Given** an incomplete recent cohort, **when** turnaround renders, **then** incompleteness/freshness is disclosed.
- **Given** a reason-code filter, **when** drilled down, **then** detail reconciles to the displayed scoped count.
- **Given** excluded test data, **when** metrics render, **then** exclusion count and policy version are available.

## 8. Out of Scope

- Altering verification decisions or provider thresholds from analytics.
- Automated fraud conclusions.
