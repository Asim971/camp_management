# Flutter Architecture Plan
## ACSL Carpenter Campaign Management & Attendance Verification

**Status:** Proposed
**Date:** 2026-07-26
**Author:** Asim Ibne Ilyus (Head of Project)
**Basis:** `Campaign_Management_Carpenter_Attendance_Verification_PRD.md` v-Draft, `ACSL_Carpenter_Campaign_Management_UI_UX_Design_Guideline_v1_0.md` v1.0
**Decision:** Single Flutter codebase across all four surfaces (mobile field, web admin, web CRM, analytics), extending the BMD Sales Ecosystem shell.

---

## 1. Context & Constraints

| Force | Implication for architecture |
|-------|------------------------------|
| Four experience surfaces (Web Admin, Web CRM, Mobile Field, Analytics) from one product | One Flutter codebase, feature-first modular structure, responsive per breakpoint (320px → ≥1440px). |
| Native extension of BMD Sales Ecosystem — not a standalone product | Reuse org/role/hierarchy/approval/audit conventions; integrate via Sales Eco APIs; **reference/hybrid DB**, never write core master data directly. |
| Phase 1 = manual CRM verification; AI face-match deferred | Verification is a pluggable service boundary. Machine result is advisory and a *separate object* from the human decision. |
| Field capture under weak connectivity, bright light, corporate Android | Offline-first mobile: local queue, encrypted evidence, resilient sync, camera-first UX. Capture success ≠ upload success. |
| Sensitive data (NID, face, biometric) | Masking, permission-gated reveal, short-lived signed URLs, audit-on-view, no raw score to field users, encryption at rest. |
| WCAG 2.2 AA + Bangla/English | Semantics-first widgets, localized notices with version records, 4.5:1 contrast, keyboard/focus for CRM. |
| BMD-themed Material 3 with defined tokens | Design-token layer drives `ThemeData`; controlled status vocabulary as typed enums. |

### 1.1 Non-functional targets (from PRD NFRs + design)
- **Offline resilience** (NFR-04): capture, queue, restart, sync without data loss or duplicate encouragement.
- **Performance**: async bulk import beyond threshold; lists virtualized; images lazy/thumbnailed.
- **Security/privacy** (NFR-07..10): RBAC, audit, encryption at rest, signed media URLs.
- **Accessibility/localization** (NFR-11..13): WCAG 2.2 AA equivalent on web + Android a11y; bn/en parity.

---

## 2. Key Architecture Decision — Flutter Everywhere

### Decision
Build **all** surfaces from a single Flutter codebase: Android (+iOS optional) for field capture, Flutter **Web** for Campaign Admin, CRM Verification, and Analytics.

### Options considered

#### Option A — Flutter everywhere (SELECTED)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium — one codebase, shared design system & models |
| Cost | Low/Med — single team, single toolchain |
| Scalability | High for feature velocity; shared domain logic |
| Team familiarity | Assumes Flutter competency across team |

**Pros:** One design system implementation, shared domain/data layers, shared status vocabulary and validation, single CI, fastest cross-surface consistency (a hard PRD/design requirement: "same status language across list, detail, notification, mobile sync, analytics").
**Cons:** Flutter **Web** accessibility (CanvasKit) needs deliberate mitigation for WCAG 2.2 AA; dense enterprise tables and SEO are weaker than DOM frameworks; larger initial web payload.

#### Option B — Flutter mobile + web-native (React) admin/CRM
**Pros:** Best-in-class web a11y/tables/SEO. **Cons:** Two codebases, duplicated design system + status vocabulary + models, two skill sets, consistency drift risk, higher long-run cost.

#### Option C — Flutter mobile only, web later
**Pros:** Fastest to the highest-RICE feature (attendance capture). **Cons:** Defers admin/CRM which are P0; not viable as full-program architecture.

### Trade-off resolution
Option A is chosen per direction. The web accessibility/table risks are **real but mitigable** and are addressed in §11 (Web Strategy). We accept them in exchange for single-codebase consistency, which the design guideline treats as non-negotiable.

### Consequences
- **Easier:** cross-surface status/validation consistency; one design-token source; shared offline/domain code.
- **Harder:** web a11y compliance (needs `Semantics`, HTML renderer choice, audit); large data-grid ergonomics (needs a dedicated virtualized table component).
- **Revisit if:** WCAG audit fails materially on CanvasKit → fall back to Option B for CRM/Admin only, keeping mobile + domain packages intact (the modular boundaries below make this a contained change, not a rewrite).

---

## 3. Application Topology

```
                    ┌─────────────────────────────────────────────┐
                    │         Single Flutter Codebase             │
                    │                                             │
   Android/iOS ◄────┤  Field Attendance App (offline-first)       │
   (field)          │                                             │
                    │  Flutter Web ──► Campaign Admin             │
   Browser ◄────────┤            ──► CRM Verification Console     │
   (office)         │            ──► Management Analytics         │
                    └───────────────────────┬─────────────────────┘
                                             │ HTTPS / REST (+ SSE/poll)
                             ┌───────────────▼───────────────────┐
                             │   Campaign Management Service      │
                             │   (BMD Sales Eco microservice)     │
                             ├────────────────────────────────────┤
                             │  Reference/Hybrid DB               │
                             │  Media store (signed URLs, enc.)   │
                             │  Verification adapter (manual→AI)  │
                             │  Import/async jobs · Audit · Auth  │
                             └───────┬───────────────┬────────────┘
                                     │               │
                          Sales Eco APIs      Face/PAD provider
                          (carpenter master)  (Phase 2, adapter)
```

The Flutter clients are **thin over a well-defined API**. All authority (source of truth, verification decisions, attribution counting, retention) lives server-side. This keeps the "one order, one count" and "reference DB, no shadow master" rules enforceable regardless of client.

---

## 4. Client Architecture — Layered + Feature-First

Clean-architecture-lite in three layers, organized by **feature** (not by technical type), so each screen family in the design guideline maps to a module.

```
lib/
├── app/                      # bootstrap, routing, theme, DI, flavors
│   ├── router/               # GoRouter config, guards (role/scope)
│   ├── theme/                # BMD tokens → ThemeData (M3)
│   ├── di/                   # Riverpod providers / service locators
│   └── app.dart
├── core/                     # cross-cutting, no feature knowledge
│   ├── network/              # Dio client, auth interceptor, retry, error map
│   ├── storage/              # Drift (SQL), secure storage, file/media cache
│   ├── sync/                 # offline queue engine, idempotency, backoff
│   ├── auth/                 # session, RBAC scope, token refresh
│   ├── media/                # camera pipeline, encryption, signed-URL fetch
│   ├── localization/         # bn/en, ARB, notice versioning
│   ├── responsive/           # breakpoint system, adaptive scaffolds
│   ├── design_system/        # BMD component library (buttons, chips, tables…)
│   ├── audit/                # client-side audit event emission
│   └── result/               # Result/Either, failure types
├── domain/                   # pure Dart: entities, value objects, repo IFaces
│   ├── campaign/  registration/  attendance/  verification/
│   ├── carpenter/  analytics/  admin/  common/ (status enums, RBAC)
├── data/                     # repo impls, DTOs, mappers, data sources
│   └── <same subfolders as domain>/
└── features/                 # UI + state per screen family (see §5)
    ├── campaign_dashboard/  campaign_list/  campaign_wizard/
    ├── campaign_approval/   campaign_detail/ registration/
    ├── bulk_import/         session_readiness/ carpenter_search/
    ├── camera_capture/      offline_queue/   crm_queue/
    ├── crm_case/            carpenter_360/   analytics/
    ├── integrity_ops/       configuration/
```

### Dependency rule
`features → domain ← data`, and everything may use `core`. **Domain has zero Flutter/IO imports** (unit-testable). Repository interfaces live in `domain`; implementations in `data`. This is exactly the seam that makes a future "web in React" fallback contained.

---

## 5. Screen Inventory → Flutter Feature Modules

Direct mapping from design guideline §7 (each keeps its PRD traceability):

| Design ID | Surface | Feature module | Notes |
|-----------|---------|----------------|-------|
| W-01 | Web | `campaign_dashboard` | Exception-first KPIs; drill-down providers |
| W-02 | Web | `campaign_list` | Virtualized data table; saved filters |
| W-03 | Web | `campaign_wizard` | 5-step stepper; persistent draft; validation summary |
| W-04 | Web | `campaign_approval` | 2-column; decision panel; SoD guard |
| W-05 | Web | `campaign_detail` | Tabs: Overview/Sessions/Reg/Attendance/Analytics/Audit |
| W-06 | Web | `registration` | Sales Eco search; registration basket; no shadow master |
| W-07 | Web | `bulk_import` | Upload→dry-run→row table→commit (idempotent) |
| M-01 | Mobile | `session_readiness` | Device/camera/network/version checklist |
| M-02 | Mobile | `carpenter_search` | Name/ID/phone-suffix; 2nd identity cue |
| M-03 | Mobile | `camera_capture` | Purpose notice → guide → live → quality → submit |
| M-04 | Mobile | `offline_queue` | Queue state, retry, last sync; capture≠upload |
| C-01 | CRM | `crm_queue` | SLA/risk sort; saved views; bulk assign (not bulk approve) |
| C-02 | CRM | `crm_case` | 3-zone evidence/context/decision; machine vs human separate |
| A-01 | Web | `carpenter_360` | Identity + campaigns/attendance/orders; canonical pieces |
| A-02 | Web | `analytics` | Funnel, contribution, ROI; definitions visible |
| A-03 | Web | `integrity_ops` | Exception cards/queues; explainable signals |
| AD-01 | Web | `configuration` | Versioned config, effective dating, audit |

---

## 6. State Management

**Choice: Riverpod (v2, manual providers)** as the single state solution.

> **Amended 2026-07-30 (Epic P0.1):** the original plan specified code-gen
> (`riverpod_generator`). In practice all ~30 providers are hand-written and the
> generator was never adopted, so its dependencies were removed rather than left
> declared-but-unused. Revisit code-gen when parameterized (`family`) providers
> become painful enough to justify migrating; the layering above is unaffected
> either way.

| Why | Detail |
|-----|--------|
| Compile-safe DI | Providers replace service locators; testable overrides for repos. |
| Async-first | `AsyncValue` models loading/data/error/delayed cleanly — the guideline mandates explicit loading/partial/delayed/permission-denied/empty states everywhere. |
| Scales to complex screens | Family providers for parameterized queries (campaign id, filters); `Notifier`/`AsyncNotifier` for wizard, capture, queue, case decision. |
| No BuildContext coupling | Works uniformly across web and mobile; easy background sync integration. |

**Pattern per feature:** `XxxState` (immutable, `freezed`) + `XxxNotifier` (`AsyncNotifier`) + UI consuming `ref.watch`. Side-effectful actions (approve, submit, capture) return `Result` and emit audit events.

> Alternative considered: BLoC. Rejected only to reduce boilerplate; Riverpod covers the same guarantees. Either is defensible — the layering above is state-library-agnostic.

---

## 7. Navigation & RBAC Routing

**GoRouter** with declarative routes + **redirect guards**:
- Guards enforce role + organization/territory scope *before* a route builds (Campaign Creator, Approver, Field User, CRM Verifier, Admin, Viewer).
- Deep-linkable web URLs (`/campaigns/:id/sessions/:sid`) — but **never** put NID/phone/personal data or media tokens in URLs (privacy rule).
- Adaptive shells: `NavigationDrawer` (desktop 248–264px / collapsed 72–80px), `NavigationRail` (tablet), `NavigationBar` with ≤4 items (mobile field). During an active session, mobile routes to a session-focused home and hides org/territory switchers on the capture path.

---

## 8. Design System Implementation

The BMD token layer (design §4, §12.2) becomes typed Dart, feeding Material 3 `ThemeData`.

```dart
// core/design_system/tokens.dart
abstract class BmdColor {
  static const primary600 = Color(0xFFE71E25); // brand red
  static const ink700      = Color(0xFF2B3674); // navy
  static const deepRed     = Color(0xFF831D1D);
  static const red50       = Color(0xFFFFF2F3);
  static const surfaceBase  = Color(0xFFF8F9FC);
  static const surfaceElev  = Color(0xFFFFFFFF);
  static const borderDefault= Color(0xFFD9DDE8);
  static const success = Color(0xFF1F7A4D);
  static const warning = Color(0xFFB54708);
  static const error   = Color(0xFFB42318);
  static const info    = Color(0xFF175CD3);
}
abstract class BmdSpace { static const s1=4.0, s2=8.0, s3=12.0, s4=16.0,
  s5=20.0, s6=24.0, s7=32.0, s8=40.0, s9=48.0, s10=64.0; }
abstract class BmdRadius { static const field=8.0, card=12.0, sheet=16.0, hero=24.0; }
```

**Rules encoded as components, not conventions:**
- `BmdButton` variants (primary/tonal/outlined/text/danger/icon) enforce "one filled primary per screen/step" via a screen-level assertion in debug.
- Brand red reserved for primary action + selected nav + one chart series; **semantic error red** is a distinct token so risk ≠ brand.
- **Status is typed, never a raw string.** Controlled vocabulary (design Appendix B) as enums with a single `StatusChip` renderer → guarantees identical wording across list, detail, mobile sync, notifications, analytics.

```dart
enum AttendanceStatus { notCaptured, pendingSync, matchProcessing,
  crmReview, approved, rejected, returned } // one source of truth
```

Typography: Inter + **Noto Sans Bengali** fallback, token-mapped to `TextTheme`. Never color-only status — every chip carries icon + label (a11y).

---

## 9. Offline-First Mobile Capture (the highest-risk subsystem)

This is where Flutter earns its place and where most engineering rigor goes.

### 9.1 Pipeline
```
Capture (camera-only, gallery disabled)
  → client quality checks (face count / blur / light / orientation)
  → encrypt evidence locally (AES; key in secure storage/Keystore)
  → write AttendanceRecord + media ref to Drift (SQLite) with idempotency key
  → enqueue SyncTask (status = pendingSync)
        ↓ (connectivity available)
  → request short-lived pre-signed upload URL
  → upload encrypted media → confirm → server runs quality/PAD/1:1
  → poll/SSE status: matchProcessing → crmReview → approved/rejected/returned
```

### 9.2 Guarantees
- **Capture success ≠ upload success** — two distinct, separately shown states. The UI *never* prompts recapture merely because sync is delayed.
- **Idempotency**: every attendance + import commit carries a client-generated key; server dedups on replay (covers app restart, retry, double-tap).
- **Durable queue**: `Drift` table for tasks; survives process death. Persistent offline banner shows queue count + last sync + "View queue".
- **Backoff & retry**: exponential with cap; per-task retry count visible; manual retry/pause; discard only under controlled permission.
- **No shadow master**: if a carpenter profile is missing, submit a Sales Eco profile request → local state `Pending profile sync`; never create a local authoritative record.

### 9.3 Key packages
`camera`, `drift` (typed SQL + migrations), `flutter_secure_storage`, `connectivity_plus`, `workmanager` (background sync on Android), `crypto`/`cryptography`, `dio` (pre-signed uploads with progress). Google ML Kit face detection *on-device* only for capture-quality hints (face present/blur) — **not** identity matching, and no score shown to the field user.

---

## 10. Data Layer & Backend Integration

| Concern | Approach |
|---------|----------|
| Transport | `Dio` + interceptors: auth/refresh, correlation-ID, retry, structured error → typed `Failure`. |
| DTO ↔ domain | `freezed` + `json_serializable`; mappers isolate API shape from domain entities. |
| Sales Eco master | **Read/link only.** Carpenter search hits Sales Eco via the campaign service (never client-direct if it risks scope leakage). Display data freshness + "last sync". |
| Local persistence | `Drift` for offline attendance, sync queue, cached reference lists; `flutter_secure_storage` for tokens/keys. |
| Media | Never bundle in JSON. Fetch via short-lived signed URLs; in-memory/disk cache with eviction; blur/hide thumbnails until authorized case open; every open emits an audit event. |
| Bulk import | Client uploads file → server async job. Client shows job lifecycle (Uploading→Scanning→Dry run→Ready→Processing→Partial/Completed/Failed) with per-row outcomes; masked result download. No generic "upload failed". |
| Real-time-ish | Verification/queue updates via polling or SSE; optimistic locking on CRM case (version check → "another reviewer completed" refresh). |
| Attribution | Client only *renders* server-computed canonical counts. "One order, one count" is server-enforced; client shows contribution credits as clearly secondary. |

---

## 11. Web Strategy (accepting Option A's risks)

Concrete mitigations for the known Flutter-Web weaknesses flagged in §2:

| Risk | Mitigation |
|------|------------|
| CanvasKit accessibility gaps vs WCAG 2.2 AA | Enable Flutter's semantics; wrap all interactive controls in `Semantics` with names/roles; keyboard focus order + shortcuts for CRM actions; run automated + manual screen-reader audits each sprint; contrast enforced by tokens. Treat a11y as a **release gate**, not a polish task. |
| Dense enterprise tables | Build one `BmdDataTable`: virtualized rows (`TwoDimensionalScrollView`/lazy), sticky header + sticky identity column, 44–48px rows, column sizing, bulk-select where safe. Reused by list, import, CRM queue, 360, analytics drill. |
| Initial payload / load time | CanvasKit + deferred (`deferred as`) loading of heavy feature modules (analytics, wizard); route-level code splitting; skeleton loaders. |
| Deep-link/SEO | Internal enterprise app → SEO not required; ensure auth-guarded deep links + browser back/refresh correctness via GoRouter. |
| 200% zoom / responsive | Breakpoint system (§ design 11): Mobile S/L, Tablet, Desktop, Large ≤1440 working width; tables → horizontal scroll with sticky identity; never hide sync/privacy/SLA warnings on narrow viewports. |

**Renderer:** target CanvasKit for fidelity/consistency; validate a11y early — this is the single decision most likely to force a revisit.

---

## 12. Security, Privacy & Audit (client responsibilities)

- **RBAC at three levels**: route guard → widget visibility → action enablement. Server re-checks every call (client checks are UX, not security).
- **Sensitive data**: NID masked to suffix, reveal is permission-gated + audited; full NID never in field screens, URLs, notifications, exports. Field users see **no** match score; CRM sees band/recommendation + reasons only.
- **Media**: signed short-lived URLs, download disabled by default, no permanent public URL, blurred thumbnails until authorized open, view logged.
- **Encryption**: evidence encrypted at rest on device (Keystore-backed key); tokens in secure storage; TLS in transit.
- **Consent/purpose notice**: language-selectable *before* acceptance; record version + language + timestamp + outcome; optional marketing consent separated from attendance verification; non-coercive manual route.
- **Audit**: client emits structured audit events (with correlation ID) for create/submit/approve/reject/verify/import/sensitive-view; server is authoritative store.

---

## 13. Localization

- `flutter_localizations` + ARB files (`en`, `bn`); Noto Sans Bengali fallback with matched weight/line-height.
- **Purpose/consent notices are versioned content objects**, not hardcoded strings — bn/en parity, explicit selector, version record persisted with each acceptance.
- Layout tested for Bangla wrapping/expansion; equivalent hierarchy in both languages (a11y requirement).

---

## 14. Testing Strategy

| Layer | Approach | Priority |
|-------|----------|----------|
| Domain | Pure Dart unit tests: status transitions, validation, attribution/dedup rules, RBAC scope logic | P0 — highest value, fastest |
| Data | Repo tests with mocked Dio + Drift; DTO mapping; idempotent replay | P0 |
| Sync/offline | Integration tests: capture→queue→restart→sync→status; failure injection (upload fail, provider down, concurrent decision) | P0 — matches PRD error-recovery matrix |
| State | Riverpod notifier tests with overridden repos; AsyncValue state coverage (loading/partial/delayed/error/empty) | P0 |
| Widget | Golden tests for design-system components + key screens (light/… states); status-chip vocabulary snapshot | P1 |
| E2E | `integration_test` on the 7 prototype paths (design §13.1): campaign creation, manual registration, bulk import, online attendance, **offline attendance**, CRM return→recapture, analytics drill | P1 |
| A11y | Automated semantics checks + manual screen-reader passes on web CRM/admin each sprint | P0 (release gate) |
| Field validation | Weak-network + bright-light + real Android device testing (design §14.1) | P0 for pilot |

---

## 15. Recommended Package Set

| Concern | Package(s) |
|---------|-----------|
| State/DI | `flutter_riverpod` |
| Routing | `go_router` |
| Models | `freezed`, `json_serializable` |
| Network | `dio`, `retry` |
| Local DB | `drift`, `sqlite3_flutter_libs` |
| Secure storage | `flutter_secure_storage` |
| Camera/media | `camera`, `google_mlkit_face_detection` (quality hints only), `image` |
| Connectivity/bg | `connectivity_plus`, `workmanager` |
| Crypto | `cryptography` |
| L10n | `flutter_localizations`, `intl` |
| Charts (analytics) | `fl_chart` (funnel/line/bar; stacked/treemap via custom) |
| Files/import | `file_selector`, `csv` |
| Testing | `mocktail`, `integration_test`, `golden_toolkit` |

*Pin versions and vet each for null-safety + web support before lock.*

---

## 16. Delivery Phasing (aligned to PRD launch plan + design sprints)

| Phase | Scope | Flutter deliverable | Exit |
|-------|-------|---------------------|------|
| **P0 Foundation** | Design tokens → ThemeData, `core/` (network/auth/storage/sync scaffold), design-system components, status enums, RBAC routing, l10n scaffold, CI + flavors | Running app shell (web+mobile), component gallery, golden baselines | Foundations signed off |
| **P1 Campaign Admin** | Wizard, list, approval, detail/sessions, registration, bulk import | Web admin surface + backend contracts | UAT-ready admin |
| **P2 Field Capture** | Session readiness, carpenter search, camera+quality, offline queue+sync | Offline-first Android app | Field usability test passed |
| **P3 CRM + Analytics** | CRM queue/case, Carpenter 360, dashboard/ROI, integrity ops | CRM console + analytics; a11y gate | Metric definitions + a11y sign-off |
| **P4 Hardening** | Config/audit, accessibility, error states, retention UX, pilot fixes | Release candidate | Pilot report, design QA checklist green |
| **Later** | AI face-match via verification adapter (behind existing service boundary) | No client rearchitecture — advisory result slots already designed | Feasibility gate |

---

## 17. Risks & Watch-items

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Flutter Web fails WCAG 2.2 AA on CanvasKit | High | A11y as sprint gate from P0; contained fallback to web-native CRM/admin (domain/data packages reused). |
| Offline sync data loss / duplicates | High | Idempotency keys, durable Drift queue, restart integration tests, capture≠upload UX. |
| Sales Eco API readiness unknown (PRD R3) | High | Contract-first with mock server; `data` layer isolates API shape; run technical discovery before timeline lock. |
| Dense-table ergonomics on web | Medium | Single virtualized `BmdDataTable` built early in P0. |
| Sensitive media leakage | High | Signed URLs, no URL PII, audit-on-view, encryption, download-off by default. |
| Scope creep (AI/logistics) | Medium | Verification behind adapter; logistics out of scope per PRD non-goals. |
| Consistency drift across surfaces | Medium | Shared design system + typed status vocabulary + golden tests enforce it. |

---

## 18. Action Items
1. [ ] Confirm Sales Eco carpenter-master API contract + availability (blocks registration/360).
2. [ ] Ratify CanvasKit + a11y approach with a spike + screen-reader audit on one dense screen.
3. [ ] Stand up P0 foundation: tokens→theme, design-system gallery, RBAC router, sync scaffold, CI.
4. [ ] Define server-side idempotency + signed-URL + audit contracts (client depends on them).
5. [ ] Build `BmdDataTable` + `StatusChip` (typed vocab) as the first shared components.
6. [ ] Write the offline-capture integration test harness before P2 feature work.
7. [ ] Lock the bn/en notice-versioning model with Security/Legal.
8. [ ] Recalibrate phasing against engineering sizing (PRD delivery date TBD).
