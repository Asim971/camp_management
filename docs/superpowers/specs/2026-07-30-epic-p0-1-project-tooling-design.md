# Design — Epic P0.1: Project & Tooling

**Status:** Approved (design); implementation plan pending
**Date:** 2026-07-30
**Epic:** [`TASK_BREAKDOWN.md`](../../../TASK_BREAKDOWN.md) → Phase P0 → Epic P0.1 (T-0.1.1 … T-0.1.5)
**Basis:** [`ARCHITECTURE_Flutter.md`](../../../ARCHITECTURE_Flutter.md), [`TESTING_MAESTRO.md`](../../../TESTING_MAESTRO.md)
**Toolchain observed:** Flutter 3.44.8 · Dart 3.12.2 · stable · remote `github.com/Asim971/camp_management`

---

## 1. Why this epic still has work

`TASK_BREAKDOWN.md` marks Epic P0.1 as scaffolded (✅). Verification against the working tree contradicts that in three material ways:

| Task | Claimed | Verified state | Evidence |
|---|---|---|---|
| T-0.1.1 `flutter create` web + **android** | ✅ | **Only `web/` exists.** No `android/` directory; never committed (`git log --diff-filter=A -- android` is empty) and not gitignored. The mobile surface cannot build or run. | repo root listing; `.gitignore:33-37` ignores only ios/macos/linux/windows |
| T-0.1.2 flavors + `--dart-define` | ✅ | Partial. `AppConfig.fromEnvironment()` reads `FLAVOR`/`API_BASE_URL`/`MEDIA_HOST` correctly, single entrypoint, no per-flavor `main_*.dart`. But no Gradle product flavors, no per-flavor application IDs, no committed run/build scripts. | `lib/app/flavors.dart:32-52`, `lib/main.dart:8-9` |
| T-0.1.3 strict lints | ✅ | Done. `strict-casts`, `strict-raw-types`, 11 explicit rules, `tool/**` excluded. Analyze is not yet run with `--fatal-infos`. | `analysis_options.yaml` |
| T-0.1.4 CI pipeline | — | **Absent.** No `.github/`, and no GitLab/Codemagic/CircleCI config anywhere in the repo. | glob over CI config paths |
| T-0.1.5 codegen wiring | ✅ | Partial. freezed + `json_serializable` + `drift_dev` genuinely produce output. `riverpod_annotation` / `riverpod_generator` are declared but **entirely unused** — they appear only in `pubspec.yaml`, with zero imports and zero `@riverpod` annotations. | `pubspec.yaml:18,72`; `campaign_dto.dart:6`; `app_database.dart:4` |

Two further reproducibility gaps cut across the epic: `pubspec.lock` is gitignored while every dependency is caret-ranged, and all generated output is gitignored — so a clean clone cannot analyze or test until code is generated, and no build is reproducible from a commit SHA.

## 2. Decisions taken

| # | Decision | Rejected alternatives |
|---|---|---|
| D1 | **Create and commit `android/`**, with Gradle product flavors. | Generate-but-gitignore (matches ios/macos handling, but flavors, permissions and signing config could not be version-controlled and CI could not build an APK — the likely reason it is missing today); defer Android to P2 (contradicts P2's exit criteria). |
| D2 | **Commit `pubspec.lock`; keep generated code gitignored.** CI regenerates. | Commit generated code too (diff churn, merge conflicts in generated files, risk of output drifting from source annotations); status quo (CI silently breaks on upstream caret bumps; no reproducibility from a SHA). |
| D3 | **Remove the Riverpod codegen deps; keep manual providers; amend `ARCHITECTURE_Flutter.md` §6.** | Adopt `@riverpod` now (a repo-wide refactor of ~30 providers plus every feature controller, with zero behavior change, smuggled into a tooling epic); codegen for new code only (two permanent DI idioms — the "consistency drift" risk named in §17). |
| D4 | **CI = fast gate + emulator Maestro E2E** (user-selected scope). | Lean gate only; full release pipeline with signing (deferred to P4). |
| D5 | **Sequence: platform floor → reproducibility → fast gate → emulator job.** | CI-first red-to-green (debugging Gradle/NDK/KVM through 10–25 min CI cycles with no local emulator path); two parallel tracks (they collide exactly at `build apk`, flavor app IDs, and Maestro `appId`). |

## 3. Deliverables

Six artifacts, and nothing else:

1. `android/` (committed) with dev/stg/prod product flavors — closes T-0.1.1, T-0.1.2
2. `pubspec.lock` (committed) + `pubspec.yaml` minus two unused Riverpod deps — closes T-0.1.5
3. `.github/workflows/ci.yml`, job `gate` — closes T-0.1.4
4. Same workflow, job `e2e` — closes T-0.1.4 at decision D4's scope
5. `.maestro/` appId parameterization + consistent flow tags — consequence of flavored app IDs
6. Doc amendments: `ARCHITECTURE_Flutter.md` §6/§15, `TASK_BREAKDOWN.md` P0.1 rows, `README.md` bootstrap + flavor commands

### Out of scope — recorded deferrals, not omissions

| Deferred | Owner task |
|---|---|
| Release signing, keystore, distribution | Phase P4 |
| Real ML Kit quality checker (replaces `PassthroughQualityChecker`) | T-2.2.2 |
| Golden test baselines | T-0.2.9 |
| Accessibility automation in CI | Prioritized backlog P0.5.4 |
| iOS platform | Policy: gitignored at `.gitignore:34` |
| Web E2E beyond the existing smoke flow | `TESTING_MAESTRO.md` §9.5 (Maestro web experimental) |
| `campaign_list_smoke` in automated CI | See §6.3 |

## 4. Android platform and flavors

### 4.1 Generation then correction

`flutter create --platforms=android .` derives the application ID from org + project name and will emit approximately `com.acsl.acsl_campaign` — never the `com.acsl.campaign` that `.maestro/config.yaml:2` already assumes. Generation is therefore step one and correction is step two:

- set `namespace` and `applicationId` to `com.acsl.campaign`
- move `MainActivity.kt` to the matching package directory and update its `package` declaration
- delete the stale generated package directory

Flutter 3.44's Android template emits **Kotlin-DSL** Gradle files (`build.gradle.kts`, `settings.gradle.kts`). The plan edits whatever the template actually produces; it does not assume Groovy.

### 4.2 Flavors and application IDs

One `env` flavor dimension. `prod` keeps the bare ID so store identity is never suffixed:

| Flavor | Application ID | API base |
|---|---|---|
| `dev` | `com.acsl.campaign.dev` | dev |
| `stg` | `com.acsl.campaign.stg` | staging |
| `prod` | `com.acsl.campaign` | production |

### 4.3 Consequence: Maestro appId

All **11** files under `.maestro/` hardcode `appId: com.acsl.campaign` (`config.yaml`, 2 subflows, 8 flows), but CI installs the **dev** flavor. Left alone, every flow would target an app that is not on the emulator.

Resolution: interpolate — `appId: ${APP_ID}` with `maestro test --env APP_ID=com.acsl.campaign.dev`.

**Unverified assumption:** Maestro's support for env interpolation *inside the `appId` field specifically* has not been confirmed. The plan's first Maestro task verifies it before the workflow depends on it. Fallbacks, in order of preference:

- **(a)** Rewrite the appId line in CI before invoking Maestro. Keeps §4.2's ID scheme intact; costs one opaque `sed`-style step in the workflow.
- **(b)** Assign `dev` the bare `com.acsl.campaign` and suffix stg **and prod**. Requires no Maestro change at all, but inverts §4.2's rationale — production would ship as `com.acsl.campaign.prod`, which is a permanent, hard-to-reverse store identity for a temporary tooling convenience. Choose (b) only if (a) also fails.

### 4.4 The flavor / dart-define mismatch trap

Gradle flavors and `--dart-define=FLAVOR=` are independent. Nothing prevents `--flavor dev --dart-define=FLAVOR=prod`, which installs a dev-ID app pointed at the production API. `.vscode/` is gitignored (`.gitignore:18`), so shared launch configurations cannot solve this.

Mitigation: committed wrapper scripts under `tool/scripts/` taking one environment argument and emitting both the Gradle flavor and its matching dart-defines. One source of truth per environment; CI invokes the same scripts developers do.

### 4.5 Gradle and manifest specifics

- **minSdk 24.** `camera` and `google_mlkit_face_detection` impose a floor of 21; 24 sits above it and suits a corporate Android fleet.
- **Pin `compileSdk`, `targetSdk`, and `ndkVersion` explicitly** to the template's values. Pinning `ndkVersion` heads off the "plugin requires Android NDK *x*" failure that this dependency set can trigger.
- **Permissions, each traced to its dependency:** `CAMERA` (`camera`); `INTERNET` + `ACCESS_NETWORK_STATE` (`dio`, `connectivity_plus`); `WAKE_LOCK` + `RECEIVE_BOOT_COMPLETED` (`workmanager`). **No location permission** — capture geo-metadata belongs to prioritized-backlog P0.15, and an unused location permission is a privacy-review liability.
- **`.gitignore` additions:** `android/local.properties`, `android/.gradle/`, `android/.kotlin/`. The existing `build/` rule already covers `android/app/build/` at any depth; `key.properties` and `upload-keystore.jks` are already handled at `.gitignore:30-31`.
- **No R8/ProGuard rules.** Flutter's release template does not enable minification, so ML Kit keep-rules would be dead configuration. They become necessary only if shrinking is later enabled.

**Accepted cost:** `google_mlkit_face_detection` is declared but unused (`providers.dart:112` runs `PassthroughQualityChecker`). It is still compiled into every APK, setting the minSdk floor and adding size for a feature deferred to T-2.2.2. It is kept rather than removed, because removing and re-adding would churn the lockfile being committed in the same epic.

## 5. Reproducibility and codegen

### 5.1 The real codegen graph

| Builder | Produces | Evidence |
|---|---|---|
| `freezed` | 8 × `*.freezed.dart` | `lib/domain/**` |
| `json_serializable` | `campaign_dto.g.dart` | `campaign_dto.dart:6` |
| `drift_dev` | `app_database.g.dart` | `app_database.dart:4` |
| `flutter gen-l10n` | `lib/l10n/generated/**` (3 files) | `l10n.yaml`, `pubspec.yaml:79` |

**No `build.yaml`.** Once the Riverpod generator is removed there is no builder left to configure or disable; every remaining builder works on defaults.

### 5.2 Mandatory command order

All four outputs are gitignored (`.gitignore:12-14`), so on a clean clone `flutter analyze` fails before anything is generated — the l10n classes and `.freezed.dart` parts do not exist yet. The sequence, identical in CI and in the README:

```bash
flutter pub get --enforce-lockfile
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze --fatal-infos
```

`--enforce-lockfile` is load-bearing: it makes CI fail when `pubspec.lock` does not satisfy `pubspec.yaml`, instead of quietly resolving something newer. Without it, committing the lockfile buys nothing in CI. Accepted friction: a dependency change requires updating the lockfile in the same PR.

### 5.3 Doc amendments

- `ARCHITECTURE_Flutter.md:166` — "Riverpod (v2, code-gen)" becomes manual providers, with one line recording why (30 providers do not need it; revisit when parameterized providers cause real pain). The §15 package table drops its `riverpod_generator` row.
- `TASK_BREAKDOWN.md` — Epic P0.1 rows get honest status per §1 of this spec. Line 11 claims `flutter test` 15/15 while `README.md:72` claims 30/30; the plan runs the suite and records the actual number rather than choosing between them.
- `README.md` — bootstrap sequence from §5.2, the flavor scripts from §4.4, and a CI badge.

## 6. CI design

One workflow file, `.github/workflows/ci.yml`, with two jobs — not two workflows, because `e2e` consumes the same run's status and the repo needs a single required-check surface for branch protection.

**Triggers:** `pull_request`; `push` to `main`; `schedule` (nightly); `workflow_dispatch` (manual full run). `concurrency` with `cancel-in-progress` so force-pushes do not queue emulators.

### 6.1 Job `gate` — `ubuntu-latest`, `timeout-minutes: 20`

```
checkout
→ subosito/flutter-action (pin 3.44.8, cache: true)
→ flutter pub get --enforce-lockfile
→ flutter gen-l10n
→ dart run build_runner build --delete-conflicting-outputs
→ flutter analyze --fatal-infos
→ flutter test
→ flutter build web --release
→ flutter build apk --flavor dev --debug
→ upload web + apk artifacts
```

Expected wall clock ~8–10 min.

### 6.2 Job `e2e` — `needs: gate`, `timeout-minutes: 30`

1. **Enable KVM** via the udev rule. Without it the emulator falls back to software rendering and the job effectively hangs — the most common cause of non-functioning emulator CI.
2. **Start the mock server** in the background. `tool/mock_server/` is a separate Dart package with its own committed `pubspec.lock`, binding `InternetAddress.anyIPv4` on port 8080 (`bin/server.dart:27-28`), reachable from the emulator at `10.0.2.2:8080`. Health-check the port rather than sleeping.
3. **Build the E2E APK** — distinct from `gate`'s plain dev APK because it requires `--dart-define=E2E=true --dart-define=LOCALE=en --dart-define=API_BASE_URL=http://10.0.2.2:8080`. Costs roughly 4 extra minutes. Accepted deliberately: building only the E2E variant would mean CI never validates the normal configuration.
4. **Boot the emulator** — `reactivecircus/android-emulator-runner`, **API 33, `x86_64`, `google_apis` image**, AVD snapshot cached between runs. API 33 sits well above minSdk 24, and `google_apis` (rather than plain AOSP) is chosen so that any later ML Kit work in T-2.2.2 has Play services present on the same image. Then install Maestro, run the selected flows, and retry once on failure via a shell wrapper.
5. **On failure**, upload Maestro's per-step video and screenshots — the only thing that makes a remote emulator failure debuggable.

### 6.3 Flow selection

Selection is by **tag**, not filename, so adding a flow does not require editing YAML in two places. Flows already carry tags (`field`, `critical`, `offline` at `field_offline_capture.yaml:4-7`), but the existing tags cannot express the policy: `critical` is on `field_online_capture`, `crm_case_decision` **and** `field_offline_capture`, so `--include-tags critical` would drag the nightly-only offline flow into the PR path. The plan therefore adds two selector tags — `pr-smoke` (exactly 2 flows) and `android` (the 7 non-web flows) — and drives CI from those.

Policy, matching `TESTING_MAESTRO.md:157`:

| Trigger | Flows |
|---|---|
| Pull request | 2-flow smoke: `field_online_capture`, `crm_case_decision` |
| Nightly / manual | Full Android suite |
| Never (automated) | `campaign_list_smoke` — see below |

`campaign_list_smoke` is excluded from the emulator suite: it is a **web** flow (`TESTING_MAESTRO.md` §9.5 marks Maestro web experimental) and TC-E2E-07 requires the mock server restarted three times with different `MOCK_CAMPAIGNS` values. Forcing it onto the Android emulator would yield a permanently red or permanently meaningless check. It gets a tracked follow-up task instead of a broken job.

### 6.4 Named flake sources

`setAirplaneMode` does not always propagate to `connectivity_plus` immediately on emulator images, and `field_offline_capture.yaml:57-59` allows only a 20 s `extendedWaitUntil` for the reconnect drain. That flow is nightly-only, so a flake never blocks a PR, but it is the flow most likely to need a widened timeout once real CI timings are known. Diagnose from the uploaded video before rerunning.

### 6.5 Manual step outside the repo

Branch protection on `main`, requiring `gate` and the PR smoke as checks. This is a GitHub repository setting, not a file. Without it the workflow runs but blocks nothing.

## 7. Verification — the epic's done-criteria

Each is a command or an observable outcome, not a judgement:

1. `flutter run --dart-define=FLAVOR=dev` launches on Chrome **and** on an Android emulator (T-0.1.1's literal done-when).
2. Each flavor resolves a distinct `API_BASE_URL` **and** a distinct installable application ID (T-0.1.2).
3. `flutter analyze --fatal-infos` exits 0 (T-0.1.3, stricter than today).
4. A throwaway PR containing a deliberate lint error, a failing test, and a broken web build turns CI red on each count, and is blocked from merging (T-0.1.4). Without this, "PR blocks on red CI" is an untested claim — a misconfigured `if: always()` or an unset required check produces a green-looking pipeline that gates nothing.
5. From a clean clone, `flutter pub get --enforce-lockfile` then `dart run build_runner build --delete-conflicting-outputs` succeeds with no Riverpod generator in the build graph (T-0.1.5).
6. `maestro test .maestro/flows/field_online_capture.yaml` passes on the CI emulator against `tool/mock_server/`.

## 8. Risks

| Risk | Likelihood | Handling |
|---|---|---|
| Maestro does not interpolate `${APP_ID}` in `appId` | Medium | Verified in the first Maestro task; two fallbacks in §4.3 |
| NDK / Gradle version mismatch across native plugins | Medium | `ndkVersion` pinned explicitly (§4.5); debugged locally, not through CI |
| Emulator job flakiness eroding trust in the gate | Medium | PR path is 2 flows only; offline flow is nightly; retry-once; video artifacts; §6.4 |
| Committed `pubspec.lock` conflicts on concurrent dependency PRs | Low | Regenerate rather than hand-merge |
| Committing `android/` surfaces a large first diff | Low | Reviewed as its own commit, separate from workflow changes |

## 9. Downstream effect

T-0.1.1 is on the critical path for all of Phase P2 (field capture): `camera`, `workmanager`, `google_mlkit_face_detection`, and `sqlite3_flutter_libs` cannot build without `android/`. Completing this epic converts Phase P2 from blocked to startable, and gives the prioritized backlog's P0.13–P0.16 a device target to run against.
