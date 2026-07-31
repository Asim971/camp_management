# 1. Epic Name

Carpenter 360 Engagement History

## 2. Goal

**Problem:** Campaign participation, attendance decisions and commercial activity are spread across operational systems, making it difficult to understand an individual carpenter's engagement history. Naively combining order stages or campaign credits can double count sales, while unrestricted views can expose commercial or identity data beyond a user's role. Stale, merged or deactivated profiles also need explicit handling.

**Solution:** Provide a role-scoped Carpenter 360 view anchored to the authoritative Sales Eco identity, with distinct tabs for campaigns, attendance, orders, sites/outlets, rewards and audit. Separate all-order activity from campaign-attributed activity and enforce canonical order and quantity definitions.

**Impact:** Authorized users gain a trusted longitudinal view for engagement and follow-up without creating another master record or overstating campaign contribution.

## 3. User Personas

- **Authorized Sales User:** Reviews engagement and commercial history for follow-up.
- **CRM User:** Understands prior attendance and verification context.
- **Campaign/Marketing User:** Reviews campaign participation and outcomes.
- **Management Viewer:** Uses role-scoped summaries for engagement decisions.
- **Auditor/Support:** Traces profile merges, source freshness and access history.

## 4. High-Level User Journeys

1. An authorized user opens a carpenter from registration, verification, analytics or Sales Eco context.
2. The header confirms authoritative identity, status, geography, dealer context and last source sync.
3. The user reviews campaign and attendance history with final decisions and evidence lineage.
4. A commercial user compares all orders with the campaign-attributed subset without adding them together.
5. The user drills into canonical order attribution and sees multiple credits while quantity is counted once.
6. The system explains stale, restricted, merged, deactivated or no-data states and directs the user to the authoritative source where appropriate.

## 5. Business Requirements

### Functional Requirements

- Anchor every 360 profile to one authoritative Sales Eco carpenter ID and show source/freshness.
- Show identity summary, profile status, geography, dealer/retailer context and masked contact information under permission.
- Provide Overview, Campaigns, Attendance, Orders, Sites/Outlets, Rewards and Audit tabs subject to role.
- Show campaign registrations, sessions, capture attempts, final verification outcomes, reference source and relevant reward state.
- Preserve attendance lineage and clearly explain why rejected, returned or pending records do not count as verified attendance.
- Separate all orders from campaign-attributed orders as subset and parent; never visually imply they should be summed.
- Count one canonical verified order ID once even when User Order, Retail Order, SO, DN or multiple contribution credits refer to it.
- Use canonical pieces as the primary quantity; show MT/RFT only as secondary conversions with source, version and effective date.
- Show attribution window and credits for campaign, source, field, CRM and fulfillment without multiplying executive quantity.
- Support period filtering and role-authorized export with definition and source metadata.
- Link to the authoritative Sales Eco profile rather than editing master attributes locally.
- Represent stale sync, pending sync, no photo, no orders, restricted data, merged and deactivated states explicitly.
- Retain redirected/merged profile identifiers for audit while counting activity only under the surviving profile.

### Non-Functional Requirements

- Enforce identity, commercial, rewards and audit permissions independently.
- Mask sensitive values and log controlled reveals/exports.
- Show data source, freshness and delayed/reconciliation states for every integrated summary.
- Use server-enforced canonicalization so clients cannot double count orders or quantities.
- Meet WCAG 2.2 AA and support read-only mobile summary with deeper analysis on web/tablet.
- Load tabs progressively and avoid exposing restricted data in initial payloads.
- Preserve traceability from summary metrics to underlying campaign, attendance and order facts.

## 6. Success Metrics

| KPI | Target |
|---|---|
| Registered campaign participants with an accessible core 360 history | 100% where source identity is active |
| Executive order records/quantity duplicated by stage or credit | 0 |
| Commercial metrics displaying source, window and freshness | 100% |
| Merged profile activity counted under more than one surviving identity | 0 |
| Restricted data disclosed outside role scope | 0 |
| Users able to trace a summary value to underlying facts | 100% of supported metrics |

## 7. Out of Scope

- Replacing Sales Eco as the carpenter master or editing its core identity data.
- General customer data platform segmentation or recommendation engine.
- Proving incremental campaign causality.
- Reward payment or accounting settlement.
- Combining User Order, Retail Order, SO and DN as independent sales totals.
- Full deep analytics on phone-sized screens.

## 8. Business Value

**High.** A trusted person-level history turns campaign execution into reusable relationship intelligence and supports better follow-up, while canonicalization prevents materially misleading sales reporting.

## Source Traceability and Dependencies

- **Requirements:** Original PRD G5, F11, FR-013; guideline CM-FR-070 to CM-FR-076.
- **Design ownership:** A-01 Carpenter 360.
- **Depends on:** Authoritative identity, final attendance decisions, canonical order/attribution facts, role scope and profile-merge rules.
- **Hands off to:** Campaign analytics, authorized sales follow-up and audit investigations.
