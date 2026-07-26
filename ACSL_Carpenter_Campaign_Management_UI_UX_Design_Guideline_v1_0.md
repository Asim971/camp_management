

| BMD SALES ECOSYSTEM |
| :---: |
| **ACSL Carpenter Campaign ManagementUI/UX Design Guideline***A native extension of the BMD Sales Ecosystem* |
| Version 1.0  |  24 July 2026  |  Internal Product and Design Use |

|  | Design positionUse the current BMD visual identity as the brand layer and Material 3 as the interaction foundation. Extend the existing Sales Ecosystem shell; do not create an unrelated campaign brand or a second navigation model. |
| :---- | :---- |

# **1\. Executive Design Direction**

The Carpenter Campaign Management experience must feel like a native Sales Ecosystem capability, not a separate event-management product. The design should reuse the existing organization, hierarchy, role, approval, status, audit and integration conventions while introducing three specialized experiences: campaign administration, field attendance capture and CRM identity verification.

| Experience surface | Primary outcome | Design character |
| :---- | :---- | :---- |
| Web \- Campaign Administration | Plan, approve, register participants, manage sessions and review campaign performance. | Structured enterprise workspace; information-dense but calm; exception-first. |
| Web \- CRM Verification | Resolve identity evidence quickly and consistently with human oversight. | Focused review console; side-by-side evidence; low distraction; high audit visibility. |
| Mobile \- Field Attendance | Find the correct carpenter, capture valid evidence and preserve work under weak connectivity. | Fast, guided, large-touch, camera-first and offline-aware. |
| Management Analytics | Evaluate verified attendance, order contribution, integrity and ROI. | Outcome-first dashboards; definitions visible; drill-down without double counting. |

## **1.1 Non-negotiable UX outcomes**

* Every participant resolves to one Sales Eco carpenter identity; the interface must discourage shadow or free-text-only records.  
* Field users see actionable capture guidance, not raw biometric scores or sensitive NID details.  
* CRM remains the final MVP decision-maker; machine results are advisory and clearly separated from the human decision.  
* Campaign activity and verified commercial outcomes are visually separated so attendance is not mistaken for sales impact.  
* The same status language must be used across list pages, detail pages, notifications, mobile sync and analytics.  
* Offline, retry and reconciliation states are first-class UI states, not hidden technical behavior.

## **1.2 Evidence classification**

| Classification | What is supported | How this guideline uses it |
| :---- | :---- | :---- |
| Confirmed from accessible Figma | BMD red \#E71E25, navy \#2B3674, Inter type, soft white/translucent card treatment, 24 px hero radius, Material 3 and Simple Design System libraries. | Used as the brand and component foundation. |
| Confirmed from PRD | Campaign/session lifecycle, master integration, bulk import, camera attendance, offline queue, CRM verification, Carpenter 360, campaign analytics, security and audit. | Translated into screen and component specifications. |
| Proposed design standard | Detailed spacing, responsive grid, semantic palette, component variants and screen layouts. | Requires visual design review before final component publication. |

# **2\. Product Experience Principles**

| Principle | Design implication |
| :---- | :---- |
| Operational clarity over decoration | Users should immediately understand what needs action, what is blocked and what is complete. Decorative treatments must never compete with workflow state. |
| Exception-first management | Dashboards and work queues begin with overdue, rejected, pending sync, no-reference, suspected spoof and reconciliation exceptions before aggregate totals. |
| Progressive disclosure | List pages show the minimum decision context; detail pages, drawers and side sheets reveal full history, evidence and audit. |
| Evidence-aware design | Photos, match quality, reference source, time, device, location and decisions remain visibly connected to the attendance lineage. |
| Human-in-the-loop by design | Machine recommendation and CRM decision are displayed as separate objects. Overrides require explicit explanation and cannot be visually hidden. |
| Privacy by default | Sensitive images are hidden until required, NID values are masked, exports are restricted, and every sensitive view is audit-visible. |
| Mobile resilience | The field experience must preserve work through weak networks, app restart and delayed sync without encouraging duplicate capture. |
| One order, one count | Analytics can show multiple contribution credits, but executive totals use one canonical order ID and quantity. |

## **2.1 Tone and interface language**

* Use direct action labels: “Submit for approval”, “Capture attendance”, “Return for recapture”, “Retry sync”.  
* Use sentence case for buttons and labels. Avoid ambiguous labels such as “Process”, “Okay” or “Done”.  
* Errors explain the required correction and preserve the user’s work.  
* Sensitive warnings are factual, neutral and non-accusatory. A failed liveness or match result means “Review required”, not “Fraud detected”.  
* Support Bangla and English content. Critical purpose/consent notices must have an explicit language selector and version record.

# **3\. Experience Architecture and Information Architecture**

## **3.1 Desktop application shell**

| Region | Specification |
| :---- | :---- |
| Navigation drawer | Expanded 248-264 px; collapsed 72-80 px. Use the current Sales Ecosystem hierarchy. Add Campaign Management as a parent module only where role and organization configuration permit. |
| Top app bar | 64 px; page title, breadcrumb, environment/context indicator, notifications, help and user menu. Keep organization context visible but not user-editable unless the role can switch. |
| Content area | Maximum working width 1440 px; 24 px gutter at 1280-1439, 32 px at \>=1440. Use a 12-column grid with 24 px gaps. |
| Page header | Title, short description, key status, primary action and contextual secondary actions. Avoid more than one filled primary button. |
| Right side sheet | Use for lightweight details, filters and audit context. Use a full page for complex creation, verification or 360 views. |

## **3.2 Mobile field shell**

| Region | Specification |
| :---- | :---- |
| Top app bar | 56 px; back, session title, sync indicator and overflow. Do not place organization/territory switchers on the capture path. |
| Primary navigation | Maximum four items: Home, Campaigns, Attendance, More/Sync. During an active session, prioritize a session-focused home. |
| Content | 16 px horizontal padding; 8-12 px internal card gap; single-column flow; primary action fixed above system navigation only when it cannot obscure content. |
| Touch targets | Minimum 48 x 48 px for field use. Camera and confirmation actions should be 52-56 px high. |
| Offline banner | Persistent but compact. Show queue count, last sync and a direct “View queue” action. |

## **3.3 Recommended navigation map**

| Module | Sub-navigation |
| :---- | :---- |
| Campaigns | Dashboard; All campaigns; My campaigns; Approval queue; Templates |
| Sessions | Today; Upcoming; Active; Completed; Session readiness |
| Participants | Registrations; Add/select carpenter; Bulk imports; Exception queue |
| Verification | My queue; Unassigned; SLA breach; Returned; Completed; Quality audit |
| Analytics | Campaign performance; Carpenter 360; Order contribution; Integrity; ROI |
| Administration | Campaign types; reason codes; SLA; attendance windows; geofence; reference priority; retention; attribution windows |
| Operations | Integration jobs; sync queue; order reconciliation; media health; audit log |

# **4\. Visual Foundations**

## **4.1 Color system**

The brand palette uses confirmed BMD red and navy. Semantic colors below are proposed to make dense operational states readable without turning every status into brand red.

| Swatch | Token | Value | Usage |
| :---- | :---- | :---- | :---- |
|  | **brand.primary.600** | \#E71E25 | Primary actions, selected navigation, brand data series (confirmed from Figma) |
|  | **brand.ink.700** | \#2B3674 | Headings, core text, navigation labels (confirmed from Figma) |
|  | **brand.deepRed** | \#831D1D | High-emphasis outline or deep accent; use sparingly (confirmed from Figma) |
|  | **brand.red.50** | \#FFF2F3 | Tonal primary surfaces and selected rows (proposed) |
|  | **brand.navy.50** | \#F4F5FB | Neutral brand-tinted background (proposed) |
|  | **surface.base** | \#F8F9FC | Application background (proposed) |
|  | **surface.elevated** | \#FFFFFF | Cards, dialogs, sheets (proposed) |
|  | **border.default** | \#D9DDE8 | Card, divider and field borders (proposed) |
|  | **semantic.success** | \#1F7A4D | Approved, verified, completed (proposed) |
|  | **semantic.warning** | \#B54708 | Pending SLA, partial completion, attention (proposed) |
|  | **semantic.error** | \#B42318 | Rejected, failed, destructive actions (proposed) |
|  | **semantic.info** | \#175CD3 | Processing, informational state (proposed) |

## **4.2 Color usage rules**

* Reserve filled BMD red for the single primary action, current navigation item and one principal chart series.  
* Do not use brand red for ordinary errors and destructive states; use semantic error red so brand and risk remain distinguishable.  
* Use navy for typography and information hierarchy. Long body copy should use neutral dark gray to reduce visual fatigue.  
* Status colors always include text and, where useful, an icon. Color alone never communicates state.  
* Sensitive image areas use neutral dark overlays; do not use promotional gradients inside CRM verification.

## **4.3 Typography**

| Token | Desktop | Mobile | Usage |
| :---- | :---- | :---- | :---- |
| display.hero | 48/56, 700 | 36/44, 700 | Cover and marketing-only moments; not operational pages. |
| heading.page | 28/36, 700 | 24/32, 700 | Page title. |
| heading.section | 22/30, 700 | 20/28, 700 | Major content section. |
| heading.card | 16/24, 600 | 16/24, 600 | Card and panel title. |
| body.large | 16/24, 400 | 16/24, 400 | Important explanatory text. |
| body.default | 14/20, 400 | 14/20, 400 | Forms, tables, details. |
| label.default | 12/16, 600 | 12/16, 600 | Labels, chips and compact metadata. |
| caption | 12/18, 400 | 12/18, 400 | Secondary metadata, refresh time and helper text. |

|  | TypefaceUse Inter throughout, matching the accessible Figma cover. Ensure Bangla text uses a compatible fallback such as Noto Sans Bengali while preserving visual weight and line height. |
| :---- | :---- |

## **4.4 Spacing, radius and elevation**

| Foundation | Scale | Rule |
| :---- | :---- | :---- |
| Spacing | 4, 8, 12, 16, 20, 24, 32, 40, 48, 64 px | Use 8 px as the primary rhythm; 4 px only for tightly related metadata. |
| Radius | 6, 8, 12, 16, 24 px | Fields 8; standard cards 12; dialogs/sheets 16; hero/cover 24\. |
| Elevation 0 | No shadow | Tables, inline sections and default surfaces. |
| Elevation 1 | 0 1 2 / 8% | Cards and sticky bars. |
| Elevation 2 | 0 4 12 / 12% | Menus, popovers and side sheets. |
| Elevation 3 | 0 12 28 / 16% | Dialogs only; never stack multiple high-elevation surfaces. |

# **5\. Core Component Standards**

## **5.1 Buttons and actions**

| Variant | Use | Specification |
| :---- | :---- | :---- |
| Primary / filled | Single page-level or step-level action. | BMD red fill, white text, 44 px web / 52 px mobile, 8-12 px radius. Loading state preserves label width. |
| Secondary / tonal | Common alternative action. | Soft red or navy-tinted surface; navy/red label; no heavy shadow. |
| Outlined | Cancel, back, less prominent submit alternatives. | 1 px neutral border; white surface; navy label. |
| Text | Inline or low-emphasis action. | No container; underline only for links, not buttons. |
| Danger | Reject final, delete or cancel campaign. | Semantic error fill/outline; confirmation required where irreversible. |
| Icon button | Search, filter, zoom, more, close. | 40-48 px target; tooltip on web; visible label for ambiguous actions. |

## **5.2 Form controls**

* Use outlined fields for enterprise forms and dense configuration screens. Keep labels persistent; do not rely on placeholders as labels.  
* Field height: 44 px web, 52 px mobile. Textarea minimum 96 px. Use helper text for format, policy and privacy information.  
* Validation is inline and specific. Show an error summary at the top only when multiple fields fail after submit.  
* Date/time fields use locale-aware pickers and show timezone. Campaign start/end and session windows must show conflict or tolerance guidance.  
* Multi-select is appropriate for territory, product focus and audience segments. Use chips only when the selected set remains readable.  
* Sensitive values use masked display with permission-gated reveal. Full NID is never a general field.

## **5.3 Search, filters and sorting**

| Pattern | Rule |
| :---- | :---- |
| Global/list search | Debounced; match campaign name/code, carpenter ID/name/phone suffix and relevant references. Search scope must be visible. |
| Filter bar | Show 3-5 high-value filters; move the rest into a side sheet. Display active-filter count and removable filter chips. |
| Saved views | P1 for CRM and operations queues. Default views: My queue, SLA breach, Returned, High risk. |
| Sort | Default to action priority, not alphabetical order, for CRM and exception queues. |
| Empty search | Explain whether no record exists, the user lacks scope, or a new profile request is permitted. |

## **5.4 Status chips**

| Status family | Required values | Treatment |
| :---- | :---- | :---- |
| Campaign | Draft; Pending approval; Returned; Approved; Active; Paused; Completed; Cancelled | Use compact pill with status icon. Current lifecycle status appears beside page title. |
| Registration | Invited; Registered; Pending profile sync; Ineligible; Waitlisted; Cancelled | Avoid green for “Registered”; reserve green for verified/approved outcomes. |
| Attendance | Not captured; Pending sync; Match processing; CRM review; Approved; Rejected; Returned | Use the same wording across mobile, CRM and analytics. |
| Import | Dry run; Ready to commit; Processing; Completed; Partially completed; Failed; Cancelled | Pair with progress and row counts. |
| Integrity | No reference; Poor quality; Suspected spoof; Duplicate; Geofence exception; Manual override | Use warning/error semantics but neutral language. |

## **5.5 Cards, tables and lists**

* KPI cards display label, value, denominator or comparison, and refresh/source metadata. Avoid isolated vanity counts.  
* Operational tables use sticky headers, compact 44-48 px rows, bulk selection only where the underlying action can be safely batched.  
* Use row-level status, owner, SLA age and next action before less important metadata.  
* On mobile, replace wide tables with cards or two-line list items; preserve the primary action and status.  
* Photos appear as controlled evidence thumbnails, not decorative avatars, in verification contexts.

## **5.6 Dialogs, side sheets and confirmation**

| Pattern | Use |
| :---- | :---- |
| Dialog | Irreversible decision, short approval/rejection, consent notice and session override confirmation. |
| Right side sheet | Filters, audit preview, registration quick view and import row detail. |
| Full page | Campaign creation, CRM verification case, Carpenter 360 and complex analytics. |
| Bottom sheet | Mobile carpenter selection, reason code, session switch and offline queue action. |

# **6\. Data Visualization and Dashboard Rules**

## **6.1 Dashboard hierarchy**

1. Exceptions and action backlog: SLA breach, pending sync, failed import, no reference, returned capture, reconciliation gap.  
2. Conversion funnel: target, registered, captured, verified, rejected and no-show.  
3. Commercial outcome: distinct order count, canonical pieces, product mix and repeat conversion.  
4. Integrity and operational quality: duplicate rate, photo reuse, quality failure, override and geofence exceptions.  
5. Cost and ROI: cost per registered/verified/order, campaign-linked quantity and approved incremental metrics.

## **6.2 Chart patterns**

| Question | Recommended visualization | Rules |
| :---- | :---- | :---- |
| Where is the funnel leaking? | Horizontal funnel or staged bars | Always show count and rate; allow click-through to the underlying list. |
| How is performance changing? | Line chart by day/week | Use explicit date grain, source and refresh time. Do not interpolate missing data silently. |
| Which campaigns/territories lead? | Ranked bar chart | Sort descending; show denominator and minimum sample warning. |
| What is the verification mix? | 100% stacked bar | Match recommendation and final decision remain separate series. |
| What products are ordered? | Bar or treemap | Use canonical pieces; optional MT/RFT appears as a secondary view, never mixed in one axis. |
| Where are integrity risks? | Exception cards \+ table | Do not use a “fraud score” without an approved, explainable policy. |

## **6.3 KPI presentation standard**

| KPI element | Required content |
| :---- | :---- |
| Label | Clear business term, not database name. |
| Value | Distinct count, rate or canonical quantity with unit. |
| Denominator | Visible where the metric is a rate. |
| Definition | Info tooltip or drill-in with formula and exclusions. |
| Source | Campaign, attendance, verification, Sales Eco or order facts. |
| Freshness | Last refresh timestamp and delayed-data indicator. |
| Drill-down | National/organization \-\> campaign \-\> territory \-\> session \-\> carpenter, subject to permission. |

|  | Attribution ruleCampaign contribution may appear alongside source, field, CRM and fulfillment credits, but executive order quantity must use one canonical verified order ID and count once. |
| :---- | :---- |

# **7\. Screen Inventory and Priority**

| ID | Surface | Screen | Priority | Primary PRD area |
| :---- | :---- | :---- | :---- | :---- |
| W-01 | Web | Campaign dashboard | P0 | CM-FR-080 to 087 |
| W-02 | Web | Campaign list | P0 | CM-FR-001 to 007 |
| W-03 | Web | Create/edit campaign wizard | P0 | CM-FR-001 to 014 |
| W-04 | Web | Campaign approval | P0 | CM-FR-003 to 006 |
| W-05 | Web | Campaign detail and sessions | P0 | CM-FR-010 to 014 |
| W-06 | Web | Registration workspace | P0 | CM-FR-020 to 026 |
| W-07 | Web | Bulk import job and results | P0 | CM-FR-030 to 036 |
| M-01 | Mobile | Session readiness and overview | P0 | CM-FR-010 to 013; NFR-13 |
| M-02 | Mobile | Carpenter search and selection | P0 | CM-FR-020 to 021; 040 |
| M-03 | Mobile | Purpose notice and camera capture | P0 | CM-FR-041 to 046; privacy controls |
| M-04 | Mobile | Offline queue and capture status | P0 | CM-FR-044; NFR-04 |
| C-01 | CRM | Verification queue | P0 | CM-FR-060; 067 |
| C-02 | CRM | Verification case | P0 | CM-FR-061 to 066 |
| A-01 | Web | Carpenter 360 | P0/P1 | CM-FR-070 to 076 |
| A-02 | Web | Campaign analytics and ROI | P0/P1 | CM-FR-080 to 087 |
| A-03 | Web | Integrity and operations dashboard | P1 | CM-FR-087; 095 |
| AD-01 | Web | Configuration and audit | P0 | CM-FR-090 to 095 |

# **8\. Detailed Screen Guidelines**

## **8.1. Campaign Dashboard**

|  | Screen objectiveProvide a trusted opening view of campaign exceptions, funnel status, verified attendance and commercial outcome without mixing activity with sales impact. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | Campaign Admin, ACSL Marketing, approvers and management |
| PRD traceability | CM-FR-080 to CM-FR-087 |
| Desktop / web layout | Top row: exception cards and active campaign summary. Second row: funnel and verification SLA. Third row: campaign-linked pieces/product mix. Bottom: campaign table with owner, date, status, registration, verified attendance and next action. |
| Mobile behavior | Mobile management view is read-only and card-based; advanced filters open a full-screen sheet. |
| Primary actions | Create campaign; open approval queue; export authorized report; drill into campaign. |
| Required states | Loading; delayed data; no campaigns; partial order feed; permission-limited; filter applied. |
| Design notes | Every KPI shows definition and refresh. Brand red highlights the main action and selected series, not every card. |

## **8.2. Campaign List**

|  | Screen objectiveEnable rapid campaign discovery and lifecycle management under organization and territory scope. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | Campaign Admin, Marketing, approvers |
| PRD traceability | CM-FR-001 to CM-FR-007 |
| Desktop / web layout | Sticky filter bar; table columns: campaign, type, owner, territory scope, date/session, status, target, verified attendance, approval/SLA and actions. Use row click for detail and overflow for permitted actions. |
| Mobile behavior | Cards show name, date, location, status, target vs verified and next action. |
| Primary actions | Create; edit draft; submit; view; duplicate as template; cancel under permission. |
| Required states | Draft; pending approval; returned; approved; active; paused; completed; cancelled. |
| Design notes | Default sort: active exception, then upcoming date. Do not bury returned or unapproved campaigns. |

## **8.3. Create/Edit Campaign Wizard**

|  | Screen objectiveGuide users through complete campaign setup while preventing incomplete schedule, audience, target, budget and session configuration. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | Campaign Admin / Marketing |
| PRD traceability | CM-FR-001 to CM-FR-014 |
| Desktop / web layout | Five-step stepper: 1 Basics and objective; 2 Audience and territory; 3 Sessions/venue/geofence; 4 Targets/budget/approval; 5 Review and submit. Persistent draft save and validation summary. |
| Mobile behavior | Mobile supports draft review only; full campaign creation is tablet/desktop preferred unless business approves mobile creation. |
| Primary actions | Save draft; continue; preview; submit for approval. |
| Required states | Unsaved; validation error; schedule conflict; missing approver; submitted; returned. |
| Design notes | Show which fields are organization-configured. Use a final read-only summary before submission. |

## **8.4. Campaign Approval**

|  | Screen objectiveSupport a deliberate decision with complete campaign scope, targets, sessions, budget reference and segregation-of-duties context. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | Campaign Approver, configured Org/BMD Admin |
| PRD traceability | CM-FR-003 to CM-FR-006 |
| Desktop / web layout | Two-column layout: submitted plan left; approval history and decision panel right. Changes are highlighted when reviewing a change request. |
| Mobile behavior | Responsive stacked view; decision bar fixed at bottom. |
| Primary actions | Approve; return for correction; reject. |
| Required states | Pending; changed since prior approval; conflict warning; decision complete. |
| Design notes | Reason mandatory for return/reject. “Approve” remains disabled until the reviewer acknowledges critical warnings. |

## **8.5. Campaign Detail and Session Operations**

|  | Screen objectiveProvide one operational source for campaign overview, sessions, participant counts, attendance status and issues. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | Campaign Admin, Field organizer, management |
| PRD traceability | CM-FR-010 to CM-FR-014 |
| Desktop / web layout | Header with lifecycle status and primary next action. Tabs: Overview, Sessions, Registrations, Attendance, Analytics, Audit. Session cards show date, venue, capacity, registration, pending sync, review and approved counts. |
| Mobile behavior | Mobile opens the assigned session first and exposes only operational actions relevant to the user. |
| Primary actions | Start/close session; open attendance; manage registration; view readiness; pause under permission. |
| Required states | Upcoming; readiness failed; active; capture closed; completed; over capacity; geofence unavailable. |
| Design notes | A session readiness panel must surface camera, app version, network, user assignment, venue and location configuration before activation. |

## **8.6. Registration Workspace**

|  | Screen objectiveResolve participants to existing Sales Eco carpenter profiles and prevent duplicate or ineligible registrations. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | Campaign Admin and authorized Field User |
| PRD traceability | CM-FR-020 to CM-FR-026 |
| Desktop / web layout | Search panel above results. Results include profile photo thumbnail, ID, masked phone, territory, dealer/retailer context, status and last sync. Selected participants appear in a registration basket with eligibility warnings. |
| Mobile behavior | Mobile uses single-select search with a large profile confirmation card; no multi-select bulk operation. |
| Primary actions | Select existing; request new profile; register; remove before start; open profile. |
| Required states | Active; pending profile sync; inactive; duplicate registration; out of scope; consent missing. |
| Design notes | Never create a local shadow master. Display profile data freshness and direct the user to Sales Eco change request for corrections. |

## **8.7. Bulk Import Job and Results**

|  | Screen objectiveMake large registration imports safe, explainable and idempotent. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | Campaign Admin with dedicated bulk-import permission |
| PRD traceability | CM-FR-030 to CM-FR-036 |
| Desktop / web layout | Four panels: Upload; dry-run summary; row-level validation table; commit/reconciliation. Show valid, warning, duplicate, needs profile, unauthorized and error counts. Provide masked result download. |
| Mobile behavior | Tablet supports monitoring only; file upload and correction remain desktop-first. |
| Primary actions | Download template; upload; run dry run; review row; commit valid rows; retry failed; cancel. |
| Required states | Uploading; scanning; dry run; ready; processing; partial; failed; completed. |
| Design notes | Never show a single generic “upload failed”. Each row has stable ID, outcome, linked carpenter or corrective action. |

## **8.8. Session Readiness and Mobile Overview**

|  | Screen objectiveConfirm the user, device and session are ready before field attendance begins. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | Field Attendance User |
| PRD traceability | CM-FR-010 to 013; NFR-04 and NFR-13 |
| Desktop / web layout | Web view may show all session readiness checks for supervisors. |
| Mobile behavior | Mobile checklist: login/session, camera, storage, time sync, location permission, network, app version and offline capacity. Large “Start attendance” button only when blocking checks pass or an authorized override exists. |
| Primary actions | Run checks; retry; open settings; start attendance; view assigned registrations. |
| Required states | Ready; warning; blocked; offline-ready; location denied; update required. |
| Design notes | Warnings distinguish optional from blocking checks. A blocked state gives exact remediation and support reference. |

## **8.9. Carpenter Search and Selection \- Mobile**

|  | Screen objectiveHelp the operator select the correct registered carpenter quickly and safely. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | Field Attendance User |
| PRD traceability | CM-FR-020, 021, 040 |
| Desktop / web layout | Desktop equivalent appears within session attendance console. |
| Mobile behavior | Search by name, carpenter ID and phone suffix. Results show thumbnail, name, ID, territory/dealer context and attendance state. Confirmation card requires a second identity cue before capture. |
| Primary actions | Search; select; scan approved code in future P2; view registration detail. |
| Required states | Eligible; already captured; pending sync; returned; ineligible; out of session. |
| Design notes | Use photo as one cue only. Do not expose full NID or phone. Similar-name results require extra confirmation. |

## **8.10. Purpose Notice and Camera Capture \- Mobile**

|  | Screen objectiveCapture valid, purpose-limited evidence with clear participant notice and immediate quality guidance. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | Field Attendance User and participant |
| PRD traceability | CM-FR-041 to 046; consent and biometric controls |
| Desktop / web layout | A desktop capture mode is not recommended for normal field operation. |
| Mobile behavior | Step 1 language-selectable purpose notice; step 2 face positioning guide; step 3 live camera; step 4 quality result; step 5 submit. Gallery disabled. Use neutral lighting/pose prompts. |
| Primary actions | Accept/continue; capture; recapture; submit; use manual route under policy. |
| Required states | No face; multiple faces; blur; poor light; orientation; permission denied; storage full; offline queued. |
| Design notes | Do not show raw match score. Do not use red during normal camera framing; reserve red for explicit capture failure. |

## **8.11. Offline Queue and Capture Status \- Mobile**

|  | Screen objectivePreserve captured work and make synchronization status unambiguous. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | Field Attendance User |
| PRD traceability | CM-FR-044; NFR-04; NFR-09 |
| Desktop / web layout | Supervisor web view may monitor device/session queue health without exposing raw media. |
| Mobile behavior | Queue list shows carpenter, session, captured time, state, retry count and action. Persistent header shows total pending and last successful sync. |
| Primary actions | Retry; pause; view error; discard only under controlled permission; contact support. |
| Required states | Queued; uploading; match processing; CRM review; returned; approved; failed. |
| Design notes | A user must never be encouraged to recapture simply because sync is delayed. Clearly distinguish capture success from upload success. |

## **8.12. CRM Verification Queue**

|  | Screen objectivePrioritize cases by SLA, risk and business impact while preserving individual decisions. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | CRM Verifier and CRM Supervisor |
| PRD traceability | CM-FR-060 and CM-FR-067 |
| Desktop / web layout | Queue table with preview thumbnail, campaign/session, carpenter, age, match band, reference source, quality/PAD flags, reward impact and assignee. Left saved views; right optional quick preview. |
| Mobile behavior | Tablet supported for review; phone limited to queue monitoring, not final image comparison. |
| Primary actions | Open case; assign; claim; filter; escalate; mark for quality audit. |
| Required states | Unassigned; assigned; nearing SLA; breached; no reference; suspected spoof; returned. |
| Design notes | Default sort is SLA/risk, not creation time alone. Bulk assignment is allowed; bulk approval is not. |

## **8.13. CRM Verification Case**

|  | Screen objectiveEnable a consistent human decision using minimum necessary evidence and explicit consequences. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | CRM Verifier / Supervisor |
| PRD traceability | CM-FR-061 to CM-FR-066 |
| Desktop / web layout | Three-zone layout: evidence comparison; profile/capture context; decision panel. Images use same crop and scale with zoom. Show machine recommendation, quality/PAD and reference source separately. Audit timeline is collapsible. |
| Mobile behavior | Tablet landscape acceptable. Phone final decision is not recommended due evidence comparison risk. |
| Primary actions | Approve; reject; return for recapture; escalate; supervisor override where configured. |
| Required states | Loading image; no reference; low quality; PAD review; concurrent decision; returned attempt; final decision. |
| Design notes | Decision reason is required. Confirmation states downstream effect on attendance, reward eligibility and analytics. Sensitive image view is logged. |

## **8.14. Carpenter 360**

|  | Screen objectiveProvide one role-scoped profile that connects identity, campaigns, attendance, orders and commercial engagement. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | Authorized Sales, CRM, management and campaign users |
| PRD traceability | CM-FR-070 to CM-FR-076 |
| Desktop / web layout | Header: identity summary, profile status, geography and last sync. Tabs: Overview, Campaigns, Attendance, Orders, Sites/Outlets, Rewards, Audit. Summary cards separate all orders from campaign-attributed orders. |
| Mobile behavior | Mobile provides read-only summary and recent activity; deep analytics opens in web/tablet. |
| Primary actions | Open Sales Eco profile; view campaign; filter period; export when permitted. |
| Required states | Profile stale; pending sync; no photo; no orders; restricted data; merged/deactivated profile. |
| Design notes | Pieces are canonical. MT/RFT are secondary conversions with source/version. Never sum User Order, Retail Order, SO and DN as separate sales. |

## **8.15. Campaign Analytics and ROI**

|  | Screen objectiveEvaluate campaign funnel, verified order contribution, repeat behavior and cost without overstating causality. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | Management, Marketing, Product, Finance Control |
| PRD traceability | CM-FR-080 to CM-FR-087 |
| Desktop / web layout | Filter header; exception cards; funnel; verification trend; order count/pieces/product mix; attribution panel; repeat windows; cost/ROI when approved; detailed drill table. |
| Mobile behavior | Mobile shows summary cards and limited trend; complex attribution and ROI remain desktop-first. |
| Primary actions | Change filters; compare campaigns; open underlying records; export authorized dataset. |
| Required states | Data delayed; insufficient baseline; incomplete cost; order reconciliation gap; small sample. |
| Design notes | Label P0 “campaign-linked contribution” separately from P1/P2 “incremental uplift” and “ROI”. |

## **8.16. Integrity and Operations Dashboard**

|  | Screen objectiveSurface suspicious patterns, failures and reconciliation gaps without creating opaque automated accusations. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | CRM Supervisor, Security, Support, Auditor |
| PRD traceability | CM-FR-087; 090 to 095 |
| Desktop / web layout | Exception cards and queues for reused photo/hash, duplicate attendance, device burst, geofence exception, quality/PAD failure, manual override, sync backlog, profile/order reconciliation gap and sensitive access. |
| Mobile behavior | Mobile monitoring only; no sensitive image review. |
| Primary actions | Open case; assign investigation; retry integration; acknowledge alert; export controlled evidence. |
| Required states | Open; under review; resolved; false positive; service degraded; backlog. |
| Design notes | Use explainable signals and raw facts. Avoid a composite “fraud score” unless separately governed. |

## **8.17. Configuration, Audit and Support**

|  | Screen objectiveMake campaign behavior configurable and every material change traceable. |
| :---- | :---- |

| Design dimension | Specification |
| :---- | :---- |
| Primary users | Org/BMD Admin, Product, Security, Support, Auditor |
| PRD traceability | CM-FR-090 to CM-FR-095 |
| Desktop / web layout | Configuration categories: campaign types, statuses, reason codes, SLA, attendance windows, geofence, reference priority, score bands, retention, attribution windows, notifications. Audit table includes before/after, actor, time, scope and correlation ID. |
| Mobile behavior | Read-only mobile access is optional; configuration remains desktop-only. |
| Primary actions | Create version; schedule effective date; approve change; view impact; rollback under policy; retry/reconcile. |
| Required states | Draft config; pending approval; active; scheduled; superseded; failed application. |
| Design notes | High-risk changes require reason, approval and effective dating. Never expose vendor secret or raw threshold to ordinary business roles. |

# **9\. Interaction Flow Specifications**

## **9.1 Campaign lifecycle flow**

6. Campaign Admin creates a draft and configures objective, audience, territory, sessions, venue, targets and budget reference.  
7. System performs field, schedule, ownership and configuration validation.  
8. Admin reviews a read-only summary and submits.  
9. Approver approves, returns or rejects with reason; segregation of duties is enforced.  
10. Approved campaign opens registration and session readiness.  
11. Active sessions allow capture within configured windows.  
12. Campaign completion closes capture, preserves verification backlog and starts post-campaign analytics/reconciliation.

## **9.2 Registration and import flow**

13. Search Sales Eco carpenter master within role scope.  
14. Confirm correct profile and campaign eligibility.  
15. If no profile exists, submit a Sales Eco profile request; show Pending Profile Sync until callback/reconciliation.  
16. For bulk import, validate every row in a dry run and separate valid, warning, duplicate and error outcomes.  
17. Commit only confirmed rows using an idempotency key.  
18. Generate a masked result file and preserve job-level audit.

## **9.3 Attendance and verification flow**

19. Field user opens an active assigned session and passes readiness checks.  
20. User searches and confirms a registered carpenter.  
21. Participant sees the purpose notice; the app opens camera-only capture.  
22. Client checks face count, blur, lighting and orientation; failures prompt recapture.  
23. Evidence is encrypted and queued if offline, or uploaded through a short-lived pre-signed flow.  
24. The system resolves the approved reference and performs quality/PAD/1:1 comparison.  
25. CRM receives a case and makes the final decision: Approve, Reject or Return for Recapture.  
26. The decision updates attendance, reward eligibility and analytics inclusion; the full lineage remains auditable.

## **9.4 Error-recovery principles**

| Failure | User experience |
| :---- | :---- |
| Sales Eco profile API unavailable | Preserve registration request; show Pending Profile Sync; do not create a local profile. |
| Media upload fails | Keep encrypted evidence in queue; show retry state; do not instruct immediate recapture. |
| Face provider unavailable | Route to delayed or manual review; preserve attendance evidence. |
| Concurrent CRM decision | Lock or version-check the case; show that another reviewer completed it and refresh. |
| Order feed delayed | Show delayed-data banner and last refresh; do not display misleading zero contribution. |
| Notification fails | Workflow remains committed; surface notification failure only to support/operations. |

# **10\. Accessibility, Privacy and Sensitive-Evidence UX**

## **10.1 Accessibility baseline**

* Meet WCAG 2.2 AA for supported web experiences and equivalent Android accessibility practices.  
* Visible keyboard focus, logical tab order and shortcut alternatives for all CRM review actions.  
* Minimum 4.5:1 contrast for normal text and 3:1 for large text, controls and meaningful graphics.  
* Do not use color alone for status; pair color with icon, label and, where necessary, explanatory text.  
* Provide accessible names for photo controls, zoom, comparison mode, capture guidance and error messages.  
* Support 200% browser zoom without horizontal loss of critical actions; tables may use horizontal scroll with sticky identifying columns.  
* Bangla and English notices must retain equivalent hierarchy, readability and line spacing.

## **10.2 Sensitive evidence controls**

| Control | UI requirement |
| :---- | :---- |
| Photo access | Thumbnail blurred/hidden until the user opens an authorized case. Every open/view is logged. |
| NID | Show only authorized suffix or minimal verified fields. Never expose full number in field screens, URL, notification or export. |
| Signed URLs | Short-lived viewer session; no permanent public URL; download disabled by default. |
| Reference source | Display Verified Profile Photo, Authorized NID Photo, Approved Baseline Photo or Unavailable. |
| Machine output | Field users see no score. CRM sees recommendation/band and reasons; raw vendor data is limited to support/security. |
| Manual route | Provide an explicit alternative when biometric processing is unavailable, inappropriate or unsuccessful. |
| Retention | Show retention/policy metadata to authorized admins; do not expose raw deletion controls to ordinary users. |

## **10.3 Consent and purpose notice pattern**

* Title: “Attendance photo and identity verification”.  
* State ACSL, campaign/session, purpose, data used, provider category, retention, rights/contact and consequence of refusal.  
* Separate optional communication/marketing consent from attendance identity verification.  
* Provide language choice before acceptance and record notice version, language, timestamp and outcome.  
* Use a clear manual verification path when policy permits; do not use coercive wording.

# **11\. Responsive Design Rules**

| Breakpoint | Width | Design behavior |
| :---- | :---- | :---- |
| Mobile S | 320-374 px | Single column; 16 px padding; 48 px touch targets; bottom sheets; no complex table. |
| Mobile L | 375-599 px | Single column; larger evidence preview; sticky primary action; bottom navigation. |
| Tablet | 600-1023 px | Two-column where safe; navigation rail; CRM review in landscape; side sheet filters. |
| Desktop | 1024-1439 px | Navigation drawer; 12-column content grid; tables and side panels. |
| Large desktop | \>=1440 px | Max 1440 working width; 32 px gutter; avoid stretching text and forms beyond readable measure. |

## **11.1 Responsive priority order**

27. Preserve current status and primary action.  
28. Preserve identity and decision context.  
29. Collapse secondary metadata into disclosure panels.  
30. Replace tables with cards or horizontal-scroll tables with sticky identity columns.  
31. Move filters into side/bottom sheets.  
32. Never hide sync, privacy or SLA warnings solely because the viewport is narrow.

# **12\. Figma File and Component Organization**

## **12.1 Recommended pages**

| Page | Contents |
| :---- | :---- |
| 00 Cover | Product identity, ownership, version and links. |
| 01 Foundations | Color, typography, grid, spacing, radius, elevation, icons and accessibility. |
| 02 Components | BMD-themed Material 3 components, variants and usage annotations. |
| 03 Web \- Campaign | Dashboard, list, wizard, approval, detail, registration and import. |
| 04 Web \- CRM | Queue, case review, quality audit and supervisor states. |
| 05 Mobile \- Field | Readiness, session, search, consent, camera, quality, queue and returned cases. |
| 06 Analytics | Campaign, Carpenter 360, integrity and ROI. |
| 07 Flows | Campaign, registration, attendance, CRM and offline sequence flows. |
| 08 Prototype | Pilot end-to-end clickable prototype. |
| 09 Handoff | Annotations, acceptance mapping, redlines, content and developer notes. |

## **12.2 Variable collections**

| Collection | Examples |
| :---- | :---- |
| BMD / Color | brand.primary, brand.ink, surface, border, text, semantic states. |
| BMD / Space | space.1=4 through space.16=64. |
| BMD / Radius | radius.1=6; 2=8; 3=12; 4=16; 5=24. |
| BMD / Type | display, page heading, section heading, card title, body, label, caption. |
| BMD / Elevation | elevation.0 through elevation.3. |
| Campaign / Status | campaign, registration, attendance, import and integrity semantic mappings. |

## **12.3 Naming convention**

* Components: BMD/Button/Primary, BMD/Field/Search, BMD/StatusChip/Attendance, Campaign/Card/Session.  
* Frames: \[Web\]/Campaign/List/Default; \[CRM\]/Verification/Case/NoReference; \[Mobile\]/Attendance/Capture/QualityError.  
* Variants: State=Default/Hover/Focus/Disabled/Loading; Size=S/M/L; Tone=Primary/Tonal/Outline/Danger.  
* Prototype flows: FLOW-01 Campaign approval; FLOW-02 Manual registration; FLOW-03 Offline attendance; FLOW-04 CRM return and recapture.  
* Annotations include PRD requirement IDs so design review, QA and implementation remain traceable.

|  | Library strategyUse the subscribed Material 3 Design Kit for interaction primitives and the BMD token layer for brand, spacing and application-specific status. Do not copy community components without converting them to local BMD components and controlled variables. |
| :---- | :---- |

# **13\. Developer Handoff Specification**

| Handoff area | Required content |
| :---- | :---- |
| Component anatomy | Layers, slots, icon position, text behavior, min/max width and responsive rules. |
| States | Default, hover, focus, pressed, disabled, loading, error, empty and permission-denied. |
| Tokens | No hard-coded one-off colors where a token exists. Export token mapping for web and mobile. |
| Data rules | Field format, masking, canonical unit, source, refresh behavior and permission visibility. |
| API states | Loading, no result, partial, retry, idempotent replay, delayed event and reconciliation gap. |
| Content | Final Bangla/English labels, purpose notice, reason codes, error messages and confirmation text. |
| Analytics | Metric definition, denominator, source, filter context and drill-down destination. |
| Accessibility | Accessible name, role, focus order, keyboard action, screen reader announcement and contrast. |

## **13.1 Required prototype coverage**

| Prototype | Minimum path |
| :---- | :---- |
| P-01 Campaign creation | Draft \-\> validation \-\> submit \-\> approve \-\> active session. |
| P-02 Manual registration | Search \-\> confirm profile \-\> eligibility \-\> register. |
| P-03 Bulk import | Upload \-\> dry run \-\> row exception \-\> commit \-\> result. |
| P-04 Online attendance | Session \-\> search \-\> notice \-\> capture \-\> quality \-\> submit \-\> CRM review. |
| P-05 Offline attendance | Capture offline \-\> queued \-\> restart \-\> sync \-\> processing \-\> review. |
| P-06 CRM return | Open case \-\> return with reason \-\> mobile recapture \-\> approve. |
| P-07 Analytics drill | Dashboard \-\> campaign \-\> session \-\> carpenter \-\> canonical order. |

## **13.2 Design QA checklist**

**\[ \]** All screens use the existing Sales Ecosystem shell and BMD brand tokens.

**\[ \]** One filled primary action per screen/step.

**\[ \]** All PRD statuses are represented consistently across web and mobile.

**\[ \]** Empty, loading, partial, failed, permission-denied and delayed-data states are designed.

**\[ \]** Offline queue and retry behavior are fully prototyped.

**\[ \]** CRM machine recommendation and human decision are visually separate.

**\[ \]** No raw match score or full NID appears in field-user designs.

**\[ \]** Every sensitive image view includes access context and audit expectation.

**\[ \]** Pieces are canonical; MT/RFT conversions are clearly secondary and versioned.

**\[ \]** Campaign-linked contribution is not labeled as proven incremental causality.

**\[ \]** Keyboard, focus, contrast and screen-reader annotations are included.

**\[ \]** Bangla/English notice layouts are tested for wrapping and equivalent meaning.

**\[ \]** All major screens are mapped to PRD requirement IDs and acceptance scenarios.

# **14\. Recommended Design Delivery Plan**

| Sprint | Design focus | Exit artifact |
| :---- | :---- | :---- |
| Design Sprint 0 | Confirm shell, tokens, IA, roles, status taxonomy, reason codes and critical flows. | Approved foundations, page map and low-fidelity flows. |
| Design Sprint 1 | Campaign admin, registration, import and session operations. | High-fidelity web screens and prototype. |
| Design Sprint 2 | Mobile readiness, search, camera, quality, offline and returned cases. | High-fidelity mobile prototype and field usability script. |
| Design Sprint 3 | CRM queue/case, Carpenter 360, campaign dashboard and attribution. | CRM and analytics prototype; metric annotations. |
| Design Sprint 4 | Accessibility, privacy, error states, redlines and handoff. | Published components, tokens, handoff and design QA sign-off. |

## **14.1 Required design validation**

* Field usability test under weak connectivity, bright outdoor light and common corporate Android devices.  
* CRM review test using real-world image quality, similar names, no-reference and return/recapture cases.  
* Marketing/Admin test for multi-session setup, approval return and bulk-import correction.  
* Management test for distinguishing attendance activity from verified order contribution and ROI.  
* Security/Legal review of purpose notice, sensitive media access, NID masking, retention and audit cues.

## **14.2 Final decision**

|  | Recommended directionProceed with a BMD-themed Material 3 extension using the screen hierarchy and interaction patterns in this guideline. Before pixel-finalization, obtain a readable frame-level link or branch reference for the intended “Super Admin View” page so the final shell, table density and component measurements can be reconciled against the active application screens. |
| :---- | :---- |

# **Appendix A. Screen-to-Requirement Traceability**

| Design area | Requirement references | Coverage |
| :---- | :---- | :---- |
| Campaign dashboard | CM-FR-080 to 087 | Funnel, outcomes, attribution, ROI, integrity |
| Campaign list/wizard/approval | CM-FR-001 to 014 | Campaign lifecycle, sessions, venue, targets and approval |
| Registration and import | CM-FR-020 to 036 | Sales Eco master integration, duplicate control and bulk job |
| Mobile attendance | CM-FR-040 to 058 | Camera, metadata, offline, quality, PAD and 1:1 match |
| CRM queue/case | CM-FR-060 to 067 | Priority, evidence comparison, decision and override |
| Carpenter 360 | CM-FR-070 to 076 | Identity, campaign, attendance and canonical order analytics |
| Administration/operations | CM-FR-090 to 095 | Notifications, audit, configuration, export and reconciliation |
| Accessibility/localization | NFR-11 to NFR-13 | Keyboard, screen reader, Bangla/English and devices |
| Reliability/security | NFR-01 to NFR-10; NFR-14 | Performance, offline, privacy, audit, events and recovery |

# **Appendix B. Controlled Status Vocabulary**

| Domain | Values |
| :---- | :---- |
| Campaign | Draft; Pending approval; Returned; Approved; Active; Paused; Completed; Cancelled |
| Registration | Invited; Registered; Pending profile sync; Ineligible; Waitlisted; Cancelled |
| Attendance | Not captured; Pending sync; Match processing; CRM review; Approved; Rejected; Returned |
| Import | Dry run; Ready to commit; Processing; Completed; Partially completed; Failed; Cancelled |
| Verification reason | Match confirmed; Poor quality; Wrong person; No reference; Suspected spoof; Duplicate attendance; Registration error; Consent/policy issue; Other |

