# Epic P0.1 — Outcome and Follow-ups

**Closes:** [`2026-07-30-epic-p0-1-project-tooling.md`](2026-07-30-epic-p0-1-project-tooling.md) (plan) · [`../specs/2026-07-30-epic-p0-1-project-tooling-design.md`](../specs/2026-07-30-epic-p0-1-project-tooling-design.md) (spec)
**Status:** Stopped deliberately at **7 of 10 tasks**. Branch `feat/campaign-management-flutter-scaffold`.
**Date:** 2026-08-03

## 1. What shipped

| Task | Commits | Result |
|---|---|---|
| 1 — Android platform | `329a6cd` | `android/` committed, `com.acsl.campaign`, minSdk 24, 5 permissions, no location |
| 1b — Analyzer cleanup (added mid-epic) | `17f5891`, `0192ffb` | 63 issues → 0, incl. Riverpod `.stream` and 4 `RadioListTile` → `RadioGroup` migrations |
| 2 — Flavors | `bff68ca` | dev/stg/prod, distinct application IDs verified via `aapt`, `parseFlavor` + tests, `run.ps1` |
| 3 — Reproducible deps | `f447907`, `cf064e1` | `pubspec.lock` + mock-server lockfile committed, 2 unused Riverpod codegen deps removed |
| 4 — Doc reconciliation | `9ffe9e5`, `7863137` | ARCHITECTURE §6/§15, TASK_BREAKDOWN status rows, README bootstrap |
| 5 — CI gate | `e7b6250`, `d7b4ca3` | `.github/workflows/ci.yml` job `gate`; green in 8m28s |
| 7 — Maestro parameterization | `a3a6d88` | 11 files `appId: ${APP_ID}`, `pr-smoke` / `android` selector tags |
| Final-review fixes | `20a63e1`, `16a2da7`, `fd8eaea`, `e9b6fb3` | See §4 |

**Verified at `e9b6fb3`:** `flutter analyze --fatal-infos` exits 0 · `flutter test` 37/37 · `dart format --output=none --set-exit-if-changed .` exits 0 · web build succeeds · Android builds in all three flavors · working tree clean.

## 2. What was NOT done, and what that costs

**Task 6 — prove the gate blocks. Skipped.** Branch protection was never enabled, so **spec done-criterion 4 is not met**: the `gate` check reports status but nothing mechanically prevents merging a red PR. It is informational until someone adds it as a required check (Settings → Branches, or Rules → Rulesets, with `gate` required). No code change needed.

**Task 8 — emulator E2E job. Cancelled.** The `e2e` job was never written. Consequence: `${APP_ID}` interpolation in the 11 Maestro flows has never been executed. Upstream documentation confirms Maestro supports it when supplied via `maestro test --env APP_ID=…`, and `TESTING_MAESTRO.md` §7 records that plus two caveats, but no run has proven it in this repo. Recovery if it fails: `git show d7b4ca3:.maestro/<file>` holds the original literals; one `sed` reverses all 11.

**Task 9 — nightly full suite. Cancelled.** No scheduled trigger exists.

**Maestro is not installed on the primary dev machine** (Windows; the CLI targets macOS/Linux/WSL), which is why Tasks 7's verification steps were deferred rather than performed locally.

## 3. Follow-ups worth scheduling

1. **Dependency modernization — not in any existing backlog item.** Every direct dependency was stale against Flutter 3.44.8. The Android-blocking ones were fixed in this epic; the Dart-only majors remain and each carries real API breakage: `go_router` 14→17, `flutter_riverpod` 2→3, `freezed` 2→3, `fl_chart` 0.68→1.2, `drift` 2.28→2.34, `flutter_lints` 4→6, `csv` 6→8. Recommend adding to `PRIORITIZED_TASK_BREAKDOWN.md` as its own item. With the SDK floor now at Dart 3.12 / Flutter 3.44, the argument for holding back is weaker.
2. **Enable branch protection** with `gate` as a required check — closes done-criterion 4 with no code.
3. **Build the E2E job (former Task 8)** when P2 field-capture work starts; that is the path it protects.
4. **Deferred minors**, triaged by the final review as genuinely deferrable: `kotlin.incremental=false` in `android/gradle.properties` belongs in `~/.gradle` rather than shared config; the gate builds only the `dev` flavor, so `stg`/`prod` Gradle breakage would ship unnoticed; `--flavor prod --release` currently produces a debug-signed artifact (signing is a P4 item); `cancel-in-progress` also applies to `main`, so a rapid second merge cancels the first's signal; `CupertinoIcons` is referenced without `cupertino_icons` in `pubspec.yaml`, so those glyphs render blank; `XTypeGroup(mimeTypes: ['text/csv'])` is unvalidated against Android's system picker.
5. **Windows dev note:** Norton TLS interception re-signs `services.gradle.org` with a root the JDK does not trust, breaking Gradle wrapper downloads. Worked around session-scoped during this epic; a permanent fix is undocumented. CI is unaffected (Linux).

## 4. Discoveries worth remembering

- **`workmanager` 0.5.2 cannot compile against Flutter 3.44.8** — its Android code references the removed v1 embedding (`Registrar`, `ShimPluginRegistry`, `PluginRegistrantCallback`). Bumped to `^0.9.0`. It is imported nowhere in `lib/`, so `TASK_BREAKDOWN.md`'s claim that T-2.1.3 background upload was implemented was false and has been corrected.
- **`file_picker` 11.0.3 silently fails under AGP 9** — it skips applying its Kotlin plugin when AGP ≥ 9, expecting Flutter's built-in Kotlin, but Flutter stamps `android.builtInKotlin=false`. Its output jar contained 1 class versus 339 for a working plugin. Replaced with first-party `file_selector ^1.1.0`; the sole call site is `bulk_import_screen.dart`.
- **The `sdk:` constraint controls the formatter.** Raising `sdk:` to `>=3.12.0` raises the package language version, which switches `dart_style` to Dart 3.12's formatter and reformats every file. If a CI step checks formatting, an SDK-floor bump and a repo-wide reformat must land together.
- **`flutter analyze` had never exited 0** in this repo despite documentation claiming it was clean — it reported 63 issues, all info/warning level. "No errors" and "analyze passes" are different claims.
- **A gitignored Gradle wrapper is fine.** `android/.gitignore` ignores `gradlew`/`gradle-wrapper.jar` per the current Flutter template, and `flutter build` regenerates them; a clean Linux CI checkout built an APK without them.

## 5. Review coverage

Tasks 1, 1b and 2 received task-level reviews (all spec ✅, quality Approved). Tasks 3, 4, 5 and 7 did not — reviews were skipped by request. The final whole-branch review covered `2ce254a..a3a6d88` with those ranges flagged for extra scrutiny; it found one Critical defect (`run.ps1` collapsing its dart-defines so `-Flavor prod` pointed at the dev API) and seven Important ones, all fixed and confirmed by a scoped re-review.
