# Design — Epic P0.4: Auth, RBAC & Routing

**Status:** Approved (design); implementation plan pending
**Date:** 2026-08-07
**Epic:** [`TASK_BREAKDOWN.md`](../../../TASK_BREAKDOWN.md) → Phase P0 → Epic P0.4 (T-0.4.1 … T-0.4.4)
**Basis:** [`ARCHITECTURE_Flutter.md`](../../../ARCHITECTURE_Flutter.md) §7 (routing), §12 (RBAC/audit) · [UI/UX Guideline v1.0](../../../ACSL_Carpenter_Campaign_Management_UI_UX_Design_Guideline_v1_0.md) §2.1 (correction-first errors), §3.1–3.3 (shell), §11 (responsive)
**Builds on:** [Epic P0.3 spec](2026-08-06-epic-p0-3-core-services-design.md) — `SecureStore`, `AuthInterceptor`, `buildReplayDio`, `Result`/`Failure`

---

## 1. Verified state of the epic

| Task | Verified state | Evidence |
|---|---|---|
| T-0.4.1 Session + token lifecycle | **Partial.** `Session` (userId, displayName, scope, accessToken, expiresAt, `isExpired`) exists. **No login flow** — `/login` renders `PlaceholderScreen`. **No refresh** — the seam throws `UnimplementedError`. **No persistence** — `SecureStoreKeys` holds only `evidenceAesKeyV1`, so a session dies on app restart. | `lib/core/auth/session.dart`, `lib/app/di/providers.dart:56,77`, `lib/app/router/app_router.dart:44` |
| T-0.4.2 RBAC scope + permission checks | **Partial.** `AppRole` (7 values), `Permission` (11), `AccessScope.can/hasRole/inTerritory` all exist and are sound. But RBAC is referenced **only** by the router. **Zero widget-level gating**: no screen hides or disables any affordance on `.can()`. `inTerritory` has no caller anywhere. | `lib/core/auth/rbac.dart`; grep for `Permission.` outside `core/auth/` hits only `app_router.dart` and `route_guards.dart` |
| T-0.4.3 GoRouter + redirect guards | **Mostly done.** 15 routes; `RouteGuards.evaluate` is pure and Flutter-free; `_AuthListenable` bridges Riverpod → GoRouter refresh; dev routes correctly gated by `config.devRoutesEnabled`. | `lib/app/router/app_router.dart`, `route_guards.dart` |
| T-0.4.4 App shell wiring | **Barely started.** `AdaptiveScaffold` implements responsive layout well, but the nav is inert, the destinations are hardcoded and unfiltered, and there is no breadcrumb, notifications slot or account/sign-out affordance. | `lib/core/responsive/adaptive_scaffold.dart` |

Four defects surfaced while verifying, all in files this epic touches:

- **The navigation is inert.** `AdaptiveScaffold` renders a `NavigationBar`/`NavigationRail` whose `onDestinationSelected` is optional, and **not one of its 8 callers passes it**. Clicking a destination does nothing. Yet 7 of those 8 *do* pass `selectedIndex`, so the correct item highlights — which makes the shell look wired when no destination is reachable by click.
- **Nav destinations contradict the route guard.** The destination list is a hardcoded `static const` of four web surfaces, so a `fieldUser` holding only `attendanceCapture` is shown Dashboard, Campaigns, Verification and Analytics — every one of which `RouteGuards` will bounce to `/forbidden`. The shell advertises what the guard forbids.
- **`RouteGuards` has no tests.** Its own doc comment states it is "pure guard logic (unit-testable, no Flutter imports)", and `test/core/auth/` does not exist. This is the one component whose failure mode is silent privilege escalation.
- **`Session`'s doc comment is false.** It claims "Tokens live in secure storage, never here in plaintext beyond the in-memory access token." Nothing writes a token to secure storage; the comment describes an intent, not the code.

**Adjacent, and explicitly not this epic's scope:** `lib/app/app.dart:26-28` has `AppL10n.localizationsDelegates` commented out, so only the `Global*` delegates are registered and the en/bn ARB strings are never applied. That is T-0.5.1 work. It is recorded here because it sits in the app root this epic modifies, and because a reader comparing the shell against the bilingual requirement would otherwise assume this epic broke it.

## 2. Decisions taken

| # | Decision | Rejected alternatives |
|---|---|---|
| D1 | **Close all four tasks, with the auth contract behind an `AuthService` seam** and a mock-server-backed implementation, so the lifecycle runs end-to-end today and swaps by replacing one class. | Skip T-0.4.1 and do the unblocked three (leaves refresh throwing and sessions dying on restart — the app still cannot serve a real signed-in user, and P0.6 stays blocked). Shell-only (most visible defect, but the shell cannot filter destinations correctly without the RBAC work). |
| D2 | **Mobile persists the refresh token; web is memory-only.** P0.3 established that `SecureStore` on web is `localStorage` with a wrapped key, not hardware-backed, and concluded the web surface must persist nothing whose compromise matters beyond the session. A refresh token is exactly that. Field devices persist to Keystore/Keychain, because a field user reopening the app mid-session may be offline and unable to re-authenticate at all. | Persist on both (one code path, web survives reload — but puts a long-lived credential in `localStorage` for an app whose CRM surface reveals face photos and NID digits). Specify an httpOnly refresh cookie for web (the correct web answer, and we are positioned to state the requirement — but it makes the epic depend on an unverifiable backend commitment, leaving web persistence unbuilt). |
| D3 | **The access token is never persisted on either platform.** It is short-lived and re-derivable from the refresh token, so storing it only widens the attack surface for no gain. | Persisting both (marginally faster cold start; strictly more exposure). |
| D4 | **One `PermissionGate` supporting both hide and disable, with the mode chosen per call site**, because the right answer differs by context. Whole surfaces the user has no business knowing about are hidden (a disabled "Analytics" nav item is noise and leaks org structure). Individual actions on a record the user is already looking at are disabled with a reason, so the absence is explainable and diagnosable. | Always hide (one rule, no clutter — but a user missing an Approve button cannot tell permission from lifecycle state from bug, and neither can support). Always disable (self-teaching, never mysterious — but fills a field user's screen with admin actions they will never hold and reveals the full capability map). |
| D5 | **One typed `routeTable` that both the router and the guard read**, with an exhaustiveness test asserting the two path sets are identical. Today's prefix-matching `_requiredPermission` is maintained separately from the route definitions, so a new route matches no prefix and is silently ungated. | Per-`GoRoute` redirects (idiomatic and local, but no single place enumerates coverage — the same auditability gap in a different shape). Keep the prefix function and test it exhaustively (catches regressions in existing routes; nothing forces a *new* route to be considered, which is exactly how the gap recurs). |
| D6 | **A dedicated `SessionManager` owns the lifecycle; `AuthService` is only transport.** Refresh has two independent triggers — a 401 from the interceptor and proactive renewal near expiry. Without one owner holding a single in-flight future, they race on a rotating refresh token and the loser presents a consumed one, signing the user out mid-task. That failure appears only under concurrency, so it must be structural rather than tested-for. | Lifecycle inside `AuthController` (fewest files, but the Notifier accretes transport, storage I/O, platform branching and concurrency control — the accretion that made `providers.dart` need surgery in P0.3). `AuthInterceptor` owns refresh (most direct fix, but makes the interceptor a second source of session truth alongside the router and every permission check, in the one file P0.3 already spent two fix rounds on for subtle re-entrancy). |
| D7 | **`AuthState` is a sealed tri-state, replacing `Session?`.** `Session?` conflates "signed out" with "not yet known". On mobile, cold start holds a persisted token that has not yet been exchanged; treating that as signed-out flashes the login screen on every launch and then redirects away from it. | Keeping `Session?` and adding a separate `isRestoring` flag (two sources of truth for one state machine, and every consumer must remember to check both). |
| D8 | **No client-emitted audit event for sign-in/sign-out.** The server is the authoritative recorder and knows what the client cannot (source address, whether the credential was genuinely valid); a client-emitted `signedIn` would be both redundant and forgeable. `AuditAction` gains no new values. | Adding `signedIn`/`signedOut` to `AuditAction` (superficially completes the audit vocabulary; produces an untrustworthy duplicate of a server-side record). |

## 3. Deliverables

1. `lib/core/auth/auth_service.dart` — `AuthService` seam, `AuthTokens`, `DioAuthService` (🔒), `FakeAuthService`
2. `lib/core/auth/session_manager.dart` — `SessionManager`, `AuthState` tri-state, single-flight refresh
3. `lib/core/auth/token_store.dart` — platform-split persistence; `SecureStoreKeys.refreshTokenV1`
4. `lib/core/auth/scope_claims.dart` — server claims → `AppRole`/`Permission`, failing loudly on unknowns
5. `lib/core/auth/permission_gate.dart` — `PermissionGate.hidden` / `.disabled`
6. `lib/app/router/route_table.dart` — the typed registry + `Access` markers
7. `lib/features/auth/presentation/login_screen.dart` — replaces the `/login` placeholder
8. `lib/app/shell/app_shell.dart` + `nav_destinations.dart` — session-aware shell
9. `tool/mock_server/bin/server.dart` — `/auth/login`, `/auth/refresh`, `/auth/logout`
10. Modified: `session.dart` (add `refreshToken`; correct the false doc comment), `providers.dart`, `main.dart` (call `SessionManager.restore()` before `runApp`), `app_router.dart`, `route_guards.dart`, `adaptive_scaffold.dart`, and the 8 `AdaptiveScaffold` callers that migrate to `AppShell`

## 4. Component contracts

### 4.1 `AuthService` — the 🔒 seam

```dart
class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final Map<String, Object?> claims; // raw scope claims, mapped by scope_claims
}

abstract interface class AuthService {
  Future<Result<AuthTokens>> login(String username, String password);
  Future<Result<AuthTokens>> refresh(String refreshToken);
  Future<Result<void>> logout(String refreshToken);
}
```

`DioAuthService` posts to `/auth/login`, `/auth/refresh`, `/auth/logout` with placeholder payload shapes, flagged contract-pending exactly as `DioAuditTransport` is. Returning `Result` rather than throwing keeps `session_manager.dart` free of any Dio import — the same dependency direction P0.3 established for the audit transport.

`FakeAuthService` returns role-shaped tokens for E2E and tests. It **replaces** the `config.e2e` special case in `AuthController.build()`, so E2E exercises the real lifecycle against a scripted transport instead of bypassing it. `buildE2ESession` becomes the fake's fixture builder rather than a branch in the composition root.

### 4.2 `SessionManager` and `AuthState` (T-0.4.1)

```dart
sealed class AuthState {}
final class AuthRestoring extends AuthState {}  // boot only; mobile only
final class AuthSignedOut extends AuthState {}
final class AuthSignedIn extends AuthState { final Session session; }
```

| Behaviour | Rule |
|---|---|
| `signIn(username, password)` | `AuthService.login` → map claims → persist refresh token (mobile) → `AuthSignedIn`. On `Err`, stay `AuthSignedOut` and surface the `Failure`. |
| `restore()` | Mobile: `AuthRestoring` → read token → `refresh()` → signed-in or signed-out. Web: goes straight to `AuthSignedOut`; the state machine never enters `AuthRestoring`. |
| `refresh()` | **Single-flight.** The in-flight future is stored and returned to concurrent callers. On `Err`: clear storage, `AuthSignedOut`. |
| Proactive renewal | Refresh when remaining lifetime < **60s**. A request sent with 2s of validity is a guaranteed 401 and a wasted round-trip, so the 401 path becomes the exception rather than the norm. |
| `signOut()` | **Local first**: clear state and storage, *then* best-effort `logout`. A failed network call must not leave the user signed in — staying authenticated because the server was unreachable is the wrong failure direction on a shared field device. |

`AuthInterceptor.refreshToken` stops throwing and delegates to `SessionManager.refresh()`. `onAuthLost` already clears session state and needs no change.

The single-flight guard closes a race that is **not** two concurrent 401s — `QueuedInterceptor` already serialises those. It is a 401-triggered refresh colliding with a proactive one: with server-side token rotation the loser presents a token the winner already consumed, and the user is signed out mid-task.

### 4.3 `TokenStore` (T-0.4.1, D2/D3)

```dart
abstract interface class TokenStore {
  Future<void> persist(String refreshToken);
  Future<String?> read();
  Future<void> clear();
}
```

`MobileTokenStore` wraps `SecureStore` with `SecureStoreKeys.refreshTokenV1`. `WebTokenStore` is a deliberate no-op: `persist` discards, `read` returns null. Isolating the split here keeps `kIsWeb` out of `SessionManager` and makes both behaviours directly testable. Like `evidenceAesKeyV1`, `refreshTokenV1` must never be renamed — a rename silently signs out every installed device.

The access token is passed in memory only and never reaches either store (D3).

### 4.4 `scope_claims.dart` — a trust boundary (T-0.4.2)

Maps server role/permission strings to `AppRole`/`Permission`. **An unrecognised string must not degrade to an empty set.** A user with zero permissions is indistinguishable from a legitimately restricted one, so a mapping bug would present as mysterious `/forbidden` redirects rather than as the deployment mismatch it is. Unknown strings are collected and returned as an explicit sign-in `Failure` naming them.

### 4.5 `routeTable` and guards (T-0.4.3, D5)

```dart
sealed class Access {}
final class Public extends Access {}          // /login, /forbidden
final class Authenticated extends Access {}   // any signed-in user
final class Requires extends Access { final Permission permission; }

const routeTable = <RouteEntry>[
  RouteEntry('/login',                 Public()),
  RouteEntry('/campaigns',             Authenticated()),
  RouteEntry('/campaigns/new',         Requires(Permission.campaignCreate)),
  RouteEntry('/campaigns/:id/approve', Requires(Permission.campaignApprove)),
  // …one entry per registered route
];
```

**The guard keys on the route *template*, not the concrete location.** Entries like `/campaigns/:id/approve` cannot be compared to a real location such as `/campaigns/CMP-1/approve` by string equality, and reintroducing pattern matching would recreate the fragility this decision exists to remove. GoRouter already resolves this: `GoRouterState.fullPath` is the matched route's configured pattern, so the guard looks up `state.fullPath` and matching stays exact string equality. Today's guard reads `state.matchedLocation` (the concrete path), which is why it needs prefix matching at all — switching the key is what makes `location.endsWith('/register')` unnecessary rather than merely discouraged.

**Dev routes are in the table too.** `/dev` and `/gallery` are registered conditionally on `config.devRoutesEnabled`, so "the registered set equals the table" is ambiguous unless the flag is pinned. Both are `routeTable` entries carrying an `Access`, and the exhaustiveness test runs **twice** — with dev routes enabled, the registered set must equal the full table; with them disabled, it must equal the table minus exactly those two. That keeps the production build's smaller surface an asserted property rather than an assumption.

**Guard behaviour:**

| State | Result |
|---|---|
| `AuthRestoring` | **No redirect.** Hold on a splash. Redirecting here is what would flash the login screen on every mobile cold start. |
| `AuthSignedOut`, non-public route | Redirect to `/login`, carrying the intended location |
| `AuthSignedIn` on `/login` | Redirect to home |
| `Requires(p)` and `!scope.can(p)` | Redirect to `/forbidden` |

**Deep-link restoration re-checks permission.** Restoring blindly sends a user lacking `verificationDecide` from login straight to `/forbidden`, which reads as a broken sign-in rather than a permissions answer; when the restored destination is not permitted they land on their default home instead. The stored location is validated against `routeTable` rather than trusted as free text — on web it is user-influenceable via the URL, and "only paths this app declares" is a cheap and complete answer.

### 4.6 `PermissionGate` (T-0.4.2, D4)

```dart
PermissionGate.hidden(Permission.export, child: analyticsNavItem)

PermissionGate.disabled(
  Permission.campaignApprove,
  reason: 'Only a Campaign Approver can approve this campaign.',
  child: approveButton,
)
```

`disabled` wraps the child in `Semantics(enabled: false)` with the reason as its label **and** a visual tooltip, so the explanation reaches a screen reader rather than only a mouse hover — T-3.4.1's accessibility gate checks precisely that.

**`AccessScope.inTerritory` stays and remains unconsumed.** PRD §11 requires org/territory scoping and its first consumers are the territory-filtered queries in P1/P3, so removing it would discard a required concept — but no consumer is invented here to justify it. Stated explicitly so a reader does not assume territory scoping is enforced when it is not.

### 4.7 The shell (T-0.4.4)

**Permission-filtering the destinations invalidates every hardcoded `selectedIndex`.** `AdaptiveScaffold` has **8 callers** — `placeholder_screen.dart` plus 7 feature screens — and **7 of them pass a literal index** (`placeholder_screen` does not) against today's fixed four-item list. Filtering shifts the indices per user, so a `fieldUser` with one destination receives a request to highlight index 2. Selection is therefore **derived from the current location** against the filtered list: the 7 call sites drop the parameter, all 8 migrate to `AppShell`, and `AdaptiveScaffold` stops accepting `selectedIndex` at all.

**The split:** `AdaptiveScaffold` keeps pure responsive layout (drawer / rail / bottom-nav by breakpoint, 1440px content clamp) and receives `destinations` + `onSelect`. `AppShell` composes it with everything session-aware — the filtered destinations, breadcrumb, notifications slot, and an account menu carrying display name and sign-out. Screens use `AppShell`; the already-tested layout is untouched.

Wiring the dead navigation is then one line in `AppShell` (`onSelect` → `context.go(path)`). The fix is small; the reason it was never made is that nothing owned the destination list.

### 4.8 Mock server

`POST /auth/login` returns role-shaped scope claims keyed off the username, so E2E can sign in as each role; `POST /auth/refresh` rotates and returns a new pair; `POST /auth/logout` returns 204. Payload shapes are placeholders pending the 🔒 contract. Without these the login flow could not run at all before the contract lands.

## 5. Error handling

Login failures map to correction-first messages (§2.1), never a generic error:

| `FailureKind` | Message |
|---|---|
| `unauthorized` | "That username or password is not correct." Deliberately does **not** distinguish which — doing so is a username-enumeration oracle. |
| `forbidden` | "This account is not enabled for this app." |
| `network` / `timeout` | "Cannot reach the sign-in service. Check your connection and try again." |
| `server` | "The sign-in service is having trouble. Try again shortly." |
| unknown claim strings | "This account has a role this app version does not recognise." — names the deployment mismatch instead of silently granting nothing (§4.4). |

A failed **refresh** shows no dialog. It signs out and lets the router redirect: a modal over a screen whose session is gone is worse than a clean return to login.

## 6. Testing

| Unit | Assertions |
|---|---|
| `session_manager_test` | Concurrent `refresh()` calls produce exactly **one** transport call; failed refresh signs out and clears storage; `signOut` clears locally even when `logout` errors; proactive refresh fires inside the 60s skew and not outside; boot restores on mobile and never on web |
| `token_store_test` | Mobile persists and reads back; web `persist` is a no-op and `read` returns null; the **access token is never written** on either platform; `refreshTokenV1` key value is frozen |
| `scope_claims_test` | A valid claim set maps to the expected roles/permissions; an **unknown role string fails loudly** rather than yielding an empty scope |
| `route_table_test` | **The router's registered path set equals `routeTable`'s path set** — the exhaustiveness guarantee (D5) — asserted **twice**, once with `devRoutesEnabled: true` against the full table and once with it false against the table minus `/dev` and `/gallery`. Also: every entry carries an explicit `Access`, and no path appears twice |
| `route_guards_test` | Unauthenticated → `/login`; `AuthRestoring` → **no redirect**; permitted → allow; denied → `/forbidden`; signed-in on `/login` → home; a **parameterised** route resolves via its template (`/campaigns/:id/approve`) and not its concrete location, for two different `:id` values; deep link restored after sign-in; restored destination **re-checked** and replaced with home when not permitted; a `from` value absent from `routeTable` is rejected |
| `permission_gate_test` | `hidden` renders nothing; `disabled` renders the child, reports `Semantics(enabled: false)`, and exposes the reason to a screen reader |
| `app_shell_test` | Destinations filtered per scope (a `fieldUser` does not see Analytics); selection derived from location rather than an index; sign-out clears the session |
| `login_screen_test` | Field validation; each `FailureKind` maps to its specific message; loading state disables submit |

`route_guards_test` is the suite that should already have existed: guards are the one component whose failure is silent privilege escalation.

Existing coverage that must stay green: the full suite — **147 passing / 29 skipped locally, 176 passing in CI**, the difference being the Linux-gated goldens that skip on Windows. In particular the **2** existing widget tests (`test/widget/bulk_import_screen_test.dart`, `crm_case_screen_test.dart`) cover screens whose shell call sites change; the other 6 migrated screens have no widget test of their own, which is why `app_shell_test` carries the load for location-derived selection.

## 7. Sequence

Each step ends with analyze clean and tests green.

1. `AuthService` + `AuthTokens` + `FakeAuthService` + `DioAuthService` + tests
2. `TokenStore` (both platforms) + `SecureStoreKeys.refreshTokenV1` + tests
3. `scope_claims.dart` + tests
4. `SessionManager` + `AuthState` + tests; `AuthInterceptor.refreshToken` delegates
5. `routeTable` + `Access` + rewrite `RouteGuards` + the exhaustiveness and guard tests
6. `login_screen.dart` + tests; mock-server auth endpoints
7. `PermissionGate` + tests
8. `AdaptiveScaffold` split + `AppShell` + `nav_destinations` + tests; migrate all 8 screens
9. `providers.dart` wiring + `main.dart` calls `SessionManager.restore()`; close the epic in `TASK_BREAKDOWN.md`

Steps 1–3 are independent leaves and could run in parallel. Step 4 needs all three. Step 8 is last among the code steps because dropping `selectedIndex` touches every screen and is easiest to verify once the destination list is real.

**Verification gates:** `dart format --set-exit-if-changed .`, `flutter analyze --fatal-infos` (exit 0), `flutter test`, `flutter build web`, and CI's `gate` job green — CI is where `flutter build apk --flavor dev` actually runs, since the sandbox cannot reach Flutter's Android artifacts (SSL/PKIX).

## 8. Risks

| Risk | Mitigation |
|---|---|
| **The auth wire format is 🔒 unconfirmed**, so endpoints, payloads and claim names will change. | Contained to `DioAuthService` and `scope_claims.dart`. `SessionManager`, the tri-state, single-flight refresh, the route table and `PermissionGate` are all transport-agnostic. The mock server keeps the flow exercisable meanwhile. |
| **Migrating the shell touches all 8 callers** (7 of which drop `selectedIndex`), only 2 of which have a widget test. | Location-derived selection is covered by `app_shell_test`; the 2 tested screens catch structural breakage; the other 6 are thin shells over bodies already covered elsewhere. If a migration is going to break something invisibly, it is in those 6 — worth a manual pass before closing step 8. |
| **Replacing `Session?` with `AuthState` is a breaking change** to what the router and `AuthInterceptor` read. | Both consumers are in-repo and migrated in the same step. The sealed type makes every unhandled case a compile error rather than a silent null-check. |
| **`FakeAuthService` replacing the `config.e2e` branch could break Maestro flows** that assume instant sign-in. | The fake resolves synchronously and seeds the same fixtures `buildE2ESession` did; TESTING_MAESTRO §3.2's documented behaviour is preserved. Verify the E2E launcher path before closing step 9. |
| **Web memory-only sessions mean CRM reviewers re-authenticate after a browser refresh** (D2), which will be reported as a bug. | Documented in the spec and in `TokenStore`'s doc comment as a deliberate security trade-off, with the httpOnly-cookie alternative named as the path to changing it once the contract can accommodate it. |

## 9. Out of scope

- **The auth service contract itself** — endpoints and claim names stay placeholders (🔒, Engineering).
- **httpOnly refresh cookies for web**, and therefore web session persistence — revisit when the backend can commit to it (D2).
- **Territory-scoped queries.** `AccessScope.inTerritory` stays modelled and unconsumed; P1/P3 own its first consumers (§4.6).
- **`AppL10n.localizationsDelegates`**, commented out in `app.dart` — T-0.5.1 owns it. Recorded in §1 because it sits in the app root this epic modifies.
- **The mobile field shell** (≤4 nav items, offline banner, session-focused home) — T-2.3.5 owns it. This epic makes destinations permission-filtered, which is the prerequisite.
- **Multi-factor auth, password reset, account lockout** — no PRD requirement, and all three are server-side concerns.
- **Client audit events for sign-in/sign-out** (D8).
