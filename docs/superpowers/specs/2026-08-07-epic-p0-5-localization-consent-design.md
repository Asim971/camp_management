# Design — Epic P0.5: Localization & Versioned Consent Notice

**Status:** Approved (design); implementation plan pending
**Date:** 2026-08-07
**Epic:** [`TASK_BREAKDOWN.md`](../../../TASK_BREAKDOWN.md) → Phase P0 → Epic P0.5 (T-0.5.1, T-0.5.2)
**Basis:** [UI/UX Guideline v1.0](../../../ACSL_Carpenter_Campaign_Management_UI_UX_Design_Guideline_v1_0.md) §4.3 (typography/Bangla), §10.3 (consent notice), §8.10 (capture flow) · [`ARCHITECTURE_Flutter.md`](../../../ARCHITECTURE_Flutter.md) §9 (offline)
**Builds on:** [P0.3](2026-08-06-epic-p0-3-core-services-design.md) (Drift, `cryptography`), [P0.4](2026-08-07-epic-p0-4-auth-rbac-routing-design.md) (`AppShell` account menu)

---

## 1. Verified state of the epic

| Task | Verified state | Evidence |
|---|---|---|
| T-0.5.1 (marked ✅) | **The app is not localized in any functional sense.** ARB scaffolding exists and is at parity, and the fonts are bundled — but the generated delegates are never registered, nothing consumes `AppL10n`, there is no way to choose a language, and 179 strings across 13 screens are hardcoded English. | `lib/app/app.dart:26-27`; grep for `AppL10n` outside `l10n/generated`; grep over `lib/features` |
| T-0.5.2 | **Not started** (🔒 Legal). Better positioned than it looks: its consumer already exists and is waiting. | `lib/features/camera_capture/application/capture_controller.dart:29-93` |

Five defects surfaced while verifying, all in code this epic touches:

- **`AppL10n.localizationsDelegates` and `supportedLocales` are commented out** at `app.dart:26-27`. Only the `Global*` delegates are registered, so the generated localizations are **never applied**. This was noticed during P0.4 and deferred here.
- **`AppL10n` is referenced nowhere** in `lib/` outside those two comment lines. Zero consumption — the ARB files are decorative.
- **`status.dart` was designed for localization and its promise is broken.** It exposes five `l10nKey` getters (`campaignStatus_$name`, `registrationStatus_$name`, `attendanceStatus_$name`, `importStatus_$name`, `integrityFlag_$name`), but the ARB contains keys for only **two** of those families. `registrationStatus_*`, `importStatus_*` and `integrityFlag_*` do not exist. Because `l10nKey` is **never consumed**, nothing has ever noticed.
- **`l10nKey` cannot work with `gen-l10n` as designed.** It returns a runtime `String`, but `gen-l10n` emits *named getters* — there is no `AppL10n[key]` lookup. The seam as built cannot resolve, which is presumably why it was never wired.
- **No locale selection and no persistence.** `supportedLocales` is declared but nothing lets a user choose, and `shared_preferences` is not a dependency.

Confirmed sound, contrary to what a glance suggests: the ARB files are at **exact parity — 26 keys each** (an apparent 30-vs-28 gap is `description` metadata inside `@key` blocks, not strings), and Inter + Noto Sans Bengali really are bundled in `pubspec.yaml` with `test/flutter_test_config.dart` loading both for the whole test tree, so P0.2's font claim holds.

**Enum value counts, verified by listing them** (a Dart enum with members ends its value list with `;`, so a naive `,`-based count undercounts by one per enum):

| Enum | Values | ARB keys today |
|---|---|---|
| `CampaignStatus` | 8 | ✅ 8 |
| `AttendanceStatus` | 7 | ✅ 7 |
| `RegistrationStatus` | 6 | ❌ 0 |
| `ImportStatus` | 7 | ❌ 0 |
| `IntegrityFlag` | 6 | ❌ 0 |
| **Total** | **34** | **15** |

So **19 keys are missing**, and 45 (26 + 19) is the target count in each ARB file.

## 2. Decisions taken

| # | Decision | Rejected alternatives |
|---|---|---|
| D1 | **Scope: localization infrastructure + the notice model; defer the bulk copy migration.** Register the delegates, add per-device locale selection with persistence, prove Bengali renders, migrate the 26 cross-cutting keys already in ARB (plus the 19 missing), and build T-0.5.2 against the waiting capture seam. The ~150 screen-specific strings migrate per-feature alongside T-4.2's state-completeness pass, where each screen's copy is already under review. | All 179 strings now (needs authentic Bengali for 179 strings that neither author can write, touches all 13 feature screens, and risks wide regressions on copy later epics may rewrite). T-0.5.2 only (the notice must render bn/en to be verifiable, so it needs working delegates anyway, and would ship a compliance control into an app whose localization is still decorative). |
| D2 | **Notice content: a bundled floor plus server override, cached durably in Drift.** Capture uses the newest version it actually holds and never awaits a fetch. Legal can revise wording without an app release; a device that has never been online still has a valid, recordable notice. | Bundled only (Legal cannot correct wording without a store submission and a field-update cycle). Server-only with a cache (a freshly installed device that has never been online could not show a notice, therefore could not capture — precisely the field scenario the offline architecture exists for). |
| D3 | **The consent record stores version + language + timestamp + content hash.** Small enough to ride with every attendance record, and it *proves* the text rather than pointing at it: on a dispute, fetch version N in language L and verify the hash matches what was shown. | Full text snapshot per record (self-contained and assumption-free, but duplicates 1–2KB per capture on devices already holding encrypted evidence). Version + language + timestamp only (relies wholly on the store reproducing version N verbatim forever, with no way for the client to detect that it cannot — an edited version would leave every referencing record silently attesting to text nobody saw). |
| D4 | **Locale is remembered per device, initialised from the system locale.** A shared phone in a Bengali-speaking territory stays Bengali regardless of who signs in; language is a property of where a device is deployed more than of who holds it. Needs no server field. | Per user, restored on sign-in (needs either a 🔒 server preference field or per-user local keying, and a new user on a shared device gets the system default until they set their own — an extra step in the field). Per device with no system default (deterministic, but every freshly provisioned phone starts in the wrong language for its region). |
| D5 | **Replace the five `l10nKey` getters with typed `label(AppL10n)` extension methods**, each an exhaustive `switch` with no `default`. Adding a status value becomes a **compile error** until it has a label — the same guard `scope_claims.dart`'s wire maps and `AuditFlusher._isPermanentRejection` already use in this codebase. | Keep `l10nKey` and add a lookup map (preserves the API, but reinstates the silent-runtime-miss failure that let three families go missing, and adds a third hand-maintained list beside the enums and the ARB — the coupling P0.4 just deleted from the router). Keep status labels in Dart, skipping ARB (type-safe, but splits translations across two systems so no single file can be handed to a native reviewer). |
| D6 | **New Bengali values land as explicitly-marked machine drafts.** Each new `bn` value carries `@`-metadata noting it is unreviewed, plus a tracking row in the epic's closing note. | Shipping unmarked Bengali (plausible-looking text nobody has reviewed is worse than obviously-provisional text, because it invites no one to check it). Blocking the epic on native review (structure and tests can be complete and verifiable without final wording). |
| D7 | **Consent failures block capture; locale failures do not.** If no notice can be resolved at all, capture stops — you cannot photograph someone without showing them a notice. Every locale fault degrades to the system locale and continues. | One uniform policy (conflating a compliance control with a display preference; blocking a capture because a preference could not be read would be absurd, and continuing a capture with no notice shown would be a legal defect). |

## 3. Deliverables

1. `lib/app/app.dart` — register `AppL10n.localizationsDelegates` / `supportedLocales`; drive `locale:` from the controller
2. `lib/core/l10n/locale_store.dart` — `LocaleStore` + Drift-backed impl over `cached_reference`
3. `lib/core/l10n/locale_controller.dart` — `Notifier<Locale?>`; `null` == follow system
4. `lib/domain/common/status_labels.dart` — five typed `label(AppL10n)` extensions (D5)
5. `lib/features/settings/presentation/language_screen.dart` — language picker, reached from `AppShell`'s account menu
6. `lib/core/consent/notice.dart` — `ConsentNotice`, `ConsentRecord`, hash computation
7. `lib/core/consent/notice_repository.dart` — resolution, bundled-asset loader, `DioNoticeSource` (🔒)
8. `assets/consent/notice_v1.json` — the bundled floor, both languages
9. `.github/workflows/ci.yml` — a new **`e2e`** job (emulator + Maestro, all `android`-tagged flows) — see §7.1
10. `.maestro/flows/locale_bengali.yaml` — a new flow launching with `LOCALE: bn` and asserting Bengali renders
11. Modified: `lib/core/storage/app_database.dart` (schema **v3**), `capture_controller.dart` (the waiting TODO), `status.dart` (delete `l10nKey`), `lib/l10n/app_en.arb` + `app_bn.arb` (+19 keys), `pubspec.yaml` (asset), `lib/app/shell/app_shell.dart` (menu entry), `lib/app/flavors.dart` (`AppConfig.locale` from the `LOCALE` dart-define), `TASK_BREAKDOWN.md` (close the epic **and** correct T-0.1.4's "cancelled, not deferred" note)

## 4. Component contracts

### 4.1 Localization wiring (T-0.5.1)

Uncommenting `app.dart:26-27` is the single change that makes everything else non-inert; without it every other edit in this task has no user-visible effect.

`LocaleController` exposes `Locale?`, passed directly to `MaterialApp.router`'s `locale:`. **`null` means follow the system**, which is already what a null there means to Flutter — so a Bengali-configured device with nothing persisted is correct on first launch without any special-casing. An explicit choice writes `'en'` or `'bn'` and survives sign-out (D4).

`LocaleStore` persists to the existing `cached_reference` table (`key`, `valueJson`, `fetchedAt`) rather than adding `shared_preferences`. That table's stated purpose is durable key-value for non-authoritative data, which fits exactly; Drift is already a dependency; and schema v3 is being spent on the notice tables anyway, so this costs no extra migration.

Two specifics, so this does not become a source of confusion later. The reserved key is **`pref:locale`** — the `pref:` prefix marks rows that are user preferences rather than cached server data, so a future cache-eviction sweep can exclude them by prefix. And `fetchedAt` is set to the **write time**; the column's name is a poor fit for a preference, which is the honest cost of reusing the table, and the alternative was a whole new table or a new dependency for one string.

### 4.2 Typed status labels (T-0.5.1, D5)

```dart
extension CampaignStatusL10n on CampaignStatus {
  String label(AppL10n l) => switch (this) {
    CampaignStatus.draft => l.campaignStatus_draft,
    // … all 8 values, no `default`, no `_` wildcard
  };
}
```

Five such extensions, one per family, covering all 34 values. The five `l10nKey` getters are **deleted**: they were never consumed and promised keys for three non-existent families, so the seam was a silent runtime miss by construction. An exhaustive `switch` converts that into a compile error.

Nineteen ARB keys are added to both files: `registrationStatus_*` (6), `importStatus_*` (7), `integrityFlag_*` (6).

### 4.3 `ConsentNotice` and `ConsentRecord` (T-0.5.2)

```dart
class ConsentNotice {
  final int version;        // monotonic int — see below
  final String language;    // 'en' | 'bn'
  final String title;
  final String body;
  final String contentHash; // SHA-256 over the rendered fields
}

class ConsentRecord {
  final int version;
  final String language;
  final DateTime shownAt;
  final String contentHash;
}
```

**Version is a monotonic integer, not a version string.** "Newest held version wins" needs an unambiguous comparison, and semver-style strings invite `'10' < '9'` at exactly the moment it matters least to be clever.

**The hash input is length-prefixed, not delimiter-joined.** "Joined by a delimiter that cannot appear in the content" is not a real guarantee — any byte can appear in a title or body, and a notice whose text happens to contain the delimiter would collide with a different notice that splits differently. So the pre-image is built by writing, for each field in fixed order (`version`, `language`, `title`, `body`), its UTF-8 byte length as a decimal followed by `:` and then the bytes:

```
8:1|2:en|17:Attendance notice|412:We are taking…
```

Length prefixes make the encoding injective regardless of content, so two different notices cannot produce the same pre-image. Hashed with `Sha256()` from `cryptography` ^2.7.0 (resolved 2.9.0, verified to expose `Sha256`) — already a dependency from P0.3's evidence encryption, so no new package.

The exact pre-image format is part of the contract: changing it invalidates every previously written `contentHash`. It is therefore defined here rather than left to the implementation, and a test pins a known input to a known digest.

### 4.4 `NoticeRepository` — resolution and the offline guarantee (D2)

`resolve(language)` returns the highest cached version for that language, falling back to the bundled asset. **Capture never awaits the network.** Fetching newer versions is opportunistic and happens off the capture path entirely; a device that has never been online shows the bundled floor, which is a valid, fully recordable notice — that is the floor's entire purpose.

**The rule protecting the record: never show a version you cannot record.** Resolution and recording read the same resolved object, so the hash written is computed from the text actually rendered rather than recomputed later from a possibly-different source.

`DioNoticeSource` is the 🔒 seam. Endpoint and payload shape are placeholders flagged contract-pending, exactly as `DioAuthService` and `DioAuditTransport` already are.

**A requirement this design places on Legal and the backend, stated here so it is agreed rather than assumed:** a published notice version is **immutable** — corrections ship as a new version, never as an edit in place. Without that, a record's hash would eventually stop matching the text the store returns, with no way to tell whether the notice changed or the record was wrong. The hash makes that detectable instead of silent, which is the argument for stating the requirement now rather than discovering it during an audit.

### 4.5 Schema v3 and the capture seam

`consent_notices` caches fetched versions, keyed on `(version, language)`. `attendance_drafts` gains four columns: `consentVersion`, `consentLanguage`, `consentShownAt`, `consentContentHash`.

Columns rather than a side table because the record is strictly 1:1 with a capture, it avoids a join on the sync path, and it rides with the attendance payload the `SyncEngine` already sends. The migration is additive — v2's three tables and P0.3's `audit_events` are untouched — and the migration test asserts existing queued rows survive, as v1→v2's does.

**Notice language is independent of app locale**, which is what T-2.3.3's "language-selectable notice" requires: the person being photographed must understand the notice, and the field user's UI preference is irrelevant to that. The notice step defaults to the app locale but is switchable in place, and `acceptNotice(String language)` — which already exists — records what was actually shown.

`capture_controller.dart:93` currently reads `TODO(T-0.5.2): persist consent notice version + language + timestamp.` That becomes a real write of all four fields. Note the TODO **under-specifies**: it omits the hash, which is the field that makes the record prove rather than assert.

## 5. Error handling (D7)

| Failure | Behaviour | Reasoning |
|---|---|---|
| No notice resolvable at all (bundled asset missing/corrupt) | **Capture blocked**, specific message | You cannot photograph someone without showing them a notice. The one place in this epic where blocking the user is correct |
| Notice fetch fails | Silent; keep the held version | Opportunistic by design, never on the capture path |
| Locale store read fails | System locale, `debugPrint`, continue | A display preference, not a compliance control |
| Locale store write fails | Applies for the session, does not persist | The user's immediate intent is honoured |

Every user-visible message is correction-first per Guideline §2.1 — never a generic failure.

## 6. Testing

| Unit | Assertions |
|---|---|
| `arb_parity_test` | `en` and `bn` have **identical key sets**, and all **45** keys are present in both. The guard against exactly the drift that let three status families go missing |
| `status_labels_test` | All **34** enum values return a non-empty label in **both** locales. Exhaustiveness is compile-enforced; this catches an empty ARB value |
| `l10n_render_test` | Pumping with `Locale('bn')` renders a real Bengali string. **The chain-closing test** — its absence is why commented-out delegates survived since P0.2 |
| `locale_store_test` | Round-trip; unset returns null; a corrupt stored value returns null rather than throwing |
| `locale_controller_test` | `null` means follow-system; an explicit choice persists, survives rebuild, and survives sign-out (D4) |
| `notice_repository_test` | Newest cached version wins; bundled floor when the cache is empty; **resolution never awaits the network**; total resolution failure returns `Err`, not a null notice |
| `notice_hash_test` | **A known input hashes to a pinned literal digest** — the pre-image format is a contract, and changing it silently would invalidate every stored `contentHash`, so a golden digest is what makes that change loud. Plus: deterministic for identical input; differs for different body text; differs for the same text in another language; and two notices whose fields concatenate to the same string under naive delimiter-joining produce **different** hashes (the injectivity property length-prefixing buys) |
| `storage/migration_test` (extended) | v2→v3 preserves queued `sync_task`, `attendance_draft` and `audit_events` rows intact; the four consent columns round-trip |
| `capture_controller_test` | `acceptNotice` records version, language, timestamp **and hash** — the field the existing TODO omits |

Existing coverage that must stay green: the full suite (256 passing / 29 skipped locally, 285 in CI where the Linux-gated goldens run).

## 7. Sequence

Each step ends with analyze clean and tests green.

1. `arb_parity_test` + the 19 missing ARB keys (both languages, `bn` marked per D6) — the parity test first, so it fails before the keys land and passes after
2. `status_labels.dart` extensions + `status_labels_test`; delete the five `l10nKey` getters
3. Register the delegates in `app.dart` + `l10n_render_test` — the chain-closing test
4. `LocaleStore` + `locale_store_test`
5. `LocaleController` + `locale_controller_test`; wire `locale:` in `app.dart`
6. `language_screen.dart` + the `AppShell` account-menu entry
7. `notice.dart` (shapes + hash) + `notice_hash_test`
8. Bundled asset + `NoticeRepository` + `DioNoticeSource` + `notice_repository_test`
9. Schema v3 + extended `migration_test`
10. `capture_controller` consent write + `capture_controller_test`
11. `AppConfig.locale` from the `LOCALE` dart-define, wired as `LocaleController`'s initial value — the argument the flows have always passed and the app has always ignored
12. The **`e2e` CI job** + `locale_bengali.yaml` flow; iterate until all 8 `android`-tagged flows are green (the 7 existing + `locale_bengali`) (§7.1). Close the epic in `TASK_BREAKDOWN.md`, including the T-0.1.4 correction

Step 12 is last because it verifies everything before it, and because it is the step most likely to need iteration — emulator timing, install races and animation waits are tuned against a real run, not predicted. **The epic does not close until that job is green.**

Step 1 leads because a failing test is the cheapest possible proof the keys were actually added to both files. Be precise about what fails initially, though: `arb_parity_test` has **two** assertions, and before the 19 keys land only the second one fails. The key sets are *already* identical at 26 each, so the parity assertion passes from the start — it is there to prevent future drift, not to detect current drift. The count assertion (45 in each file) is the one that goes red first and green after.

Step 3 must precede 4–6: without registered delegates, no locale work is observable, so a locale test written before step 3 could pass while proving nothing.

**Verification gates:** `dart format --set-exit-if-changed .`, `flutter analyze --fatal-infos` (exit 0), `flutter test`, `flutter build web`, and CI's `gate` job green — CI is where `flutter build apk --flavor dev` runs, since this sandbox cannot reach Flutter's Android artifacts (SSL/PKIX).

### 7.1 Hard exit criterion: the emulator E2E suite must pass

**This epic is not complete until the app has run on an Android emulator and the E2E suite is green.** That is a deliberate strengthening of the exit bar, and it changes this epic's scope: it adds a CI job.

**Why it must run in CI rather than locally.** The development sandbox cannot execute this at all, and I verified that rather than assuming it:

| Requirement | State in the sandbox |
|---|---|
| Android emulator defined | ✅ one (`Resizable_Experimental`) |
| **Build any installable APK** | ❌ **`flutter build apk --debug` yields 61 TLS/resolution errors** fetching `io.flutter:*` artifacts — debug as well as release, so nothing installable can be produced |
| **Maestro CLI** | ❌ not installed |
| `adb` / `emulator` on `PATH` | ❌ absent (Flutter locates the SDK itself) |

The APK failure is the same sandbox TLS-interception problem proven during P0.3 and P0.4, independent of any code change. So a local gate would be unverifiable by the party writing the code, which is precisely the shape of claim this project has been burned by.

**This reverses a prior decision, deliberately.** `TASK_BREAKDOWN.md` T-0.1.4 records that the Maestro/emulator E2E job and a nightly suite were **"cancelled, not deferred."** Adding an `e2e` job reverses that cancellation on purpose, and the row must be updated to say so rather than leaving two contradictory statements in the same document.

**Scope of the suite — 7 flows, not 8.** The flows are already tagged by platform:

| Tag | Flows |
|---|---|
| `android` | `carpenter_search_confirm`, `crm_case_conflict`, `crm_case_decision`, `field_capture_recapture`, `field_offline_capture`, `field_online_capture`, `offline_queue_retry` (**7**) |
| `web` | `campaign_list_smoke` (**1**) — its own header notes "Maestro web support is experimental" |

An Android emulator job runs the `android`-tagged flows: the **7 existing** ones, plus the **`locale_bengali`** flow this epic adds, for **8** at close. The job selects by tag rather than by an enumerated list, so a future flow is picked up automatically instead of silently skipped — the same reason P0.4 derived `registeredRoutePaths` from the router rather than a hand-maintained literal. `campaign_list_smoke` is explicitly out of the emulator gate; it stays a web flow and is not what "E2E passing" means here. Two flows also carry `prsmoke`, indicating the original design intended a fast per-PR subset — the job runs all 7, and narrowing to `prsmoke` is the escape hatch if runtime proves unacceptable.

**What the job does:** boot the emulator, `flutter build apk --debug --flavor dev` with `--dart-define=E2E=true`, install it, `maestro test` the `android`-tagged flows against `.maestro/config.yaml` (which needs `APP_ID` exported — the dev flavor's application ID), and upload Maestro's output on failure so a red run is diagnosable rather than merely red.

**A locale assertion this epic uniquely enables.** Every existing flow already passes `LOCALE: en` as a launch argument, and **`AppConfig` does not read it** — the harness has been passing a locale the app ignores. P0.5 makes that argument meaningful, so `AppConfig` gains a `locale` field wired into `LocaleController`'s initial value, and one new flow launches with `LOCALE: bn` and asserts a Bengali string renders. That is the one assertion no widget test can make: a real app process on a real Android surface, with the real font stack, rendering Bengali glyphs. It closes the same class of gap that let commented-out delegates survive since P0.2.

**Honest expectations.** Android emulators on hosted runners are slow (10–15 minutes) and prone to flakiness — boot races, install timing, animation timing. The first run will likely need tuning, and that tuning is part of this work rather than a surprise. If a flow proves irreducibly flaky, the correct response is to fix or quarantine it explicitly with a recorded reason, never to drop the job.

## 8. Risks

| Risk | Mitigation |
|---|---|
| **The 19 new Bengali values are unreviewed machine drafts.** A reader could mistake them for verified translations. | D6: each carries `@`-metadata marking it unreviewed, and the epic's closing note lists them. Structure and tests are complete and verifiable without final wording. |
| **The notice's legal wording is 🔒 Legal.** The bundled `notice_v1.json` ships placeholder text. | Contained to one asset and `DioNoticeSource`. The version/hash/record machinery is wording-agnostic, so replacing the text is a content change, not a code change. |
| **Registering the delegates could change existing rendering** — every screen currently draws from `Global*` delegates only. | Only Material/Cupertino/Widgets strings are affected, and only where a locale differs from the device default. The 29 Linux-gated goldens render the gallery and will catch layout shifts in CI; a golden failure is a signal to investigate, not to regenerate baselines. |
| **Schema v3 runs on real field devices** holding un-uploaded attendance evidence. | The migration only adds a table and four columns; the migration test asserts existing rows survive with contents intact, as v1→v2's does. |
| **Deleting `l10nKey` is a breaking change** to `status.dart`'s public API. | It has zero consumers (verified by grep), so the blast radius is nil — and the compiler catches any that appear. |
| **Locale persistence in `cached_reference` shares a table with sync data.** A future `cached_reference` cleanup could evict the locale row. | The reserved `pref:` key prefix, documented beside the table; worst case the user's choice reverts to system locale, which D7 already treats as a benign path. |
| **The `e2e` job cannot be verified by whoever writes this epic.** The sandbox cannot build an APK or run Maestro (§7.1), so the author is structurally unable to confirm the gate they are adding. | CI is the sole authority and its result is reported verbatim, pass or fail. No claim that E2E passes may be made from a local run, because no local run is possible. This is the same discipline P0.3/P0.4 applied to `flutter build apk`. |
| **Android emulator jobs are slow and flaky on hosted runners.** A flaky gate that people learn to re-run erodes into no gate at all. | Budget 10–15 minutes and expect first-run tuning. A flow that proves irreducibly flaky is fixed or explicitly quarantined **with a recorded reason** — never silently dropped, and never by deleting the job. `prsmoke` (2 flows) is the documented fallback if full-suite runtime is unacceptable. |
| **Adding `e2e` contradicts T-0.1.4's recorded "cancelled, not deferred".** Leaving both statements in the same document would make the record self-contradictory. | The T-0.1.4 row is corrected in the same commit that adds the job, noting the reversal and why — the same pattern used when P0.4 corrected that row's branch-protection claim. |

## 9. Out of scope

- **The ~150 screen-specific hardcoded strings** (D1) — they migrate per-feature alongside T-4.2's state-completeness pass.
- **The notice's final legal wording** and the retention-policy text — 🔒 Legal / Security, and T-4.7 owns the review.
- **Native Bengali review** of the 19 new keys — tracked, not blocked (D6).
- **RTL layout support** — neither `en` nor `bn` requires it.
- **Per-user locale preferences** and any server-side preference field (D4).
- **Consent revocation and re-consent flows** — no PRD requirement; the record is append-only per capture.
- **Localizing the mock server's responses** — `tool/mock_server/` serves fixtures, not user-facing copy.
