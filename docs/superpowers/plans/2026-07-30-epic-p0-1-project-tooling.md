# Epic P0.1 — Project & Tooling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the repo a real Android platform with dev/stg/prod flavors, reproducible builds, and a GitHub Actions pipeline that gates every PR and runs Maestro E2E on an emulator.

**Architecture:** Four sequential blocks, per decision D5 of the spec: (1) create and commit `android/` with Gradle product flavors, verified locally; (2) make builds reproducible by committing `pubspec.lock`, deleting the two unused Riverpod codegen dependencies, and correcting the three docs that describe them; (3) add a fast CI gate job and *prove* it blocks a red PR; (4) add an emulator job running Maestro against the bundled mock server. Each block is verified by a command before the next begins, because Gradle/NDK/KVM failures are miserable to debug through CI logs.

**Tech Stack:** Flutter 3.44.8 · Dart 3.12.2 · Gradle Kotlin DSL · GitHub Actions · `reactivecircus/android-emulator-runner` · Maestro · Dart `shelf` mock server (`tool/mock_server/`)

**Spec:** [`docs/superpowers/specs/2026-07-30-epic-p0-1-project-tooling-design.md`](../specs/2026-07-30-epic-p0-1-project-tooling-design.md)

## Global Constraints

Every task's requirements implicitly include this section.

- **Toolchain pinned to Flutter 3.44.8 / Dart 3.12.2** in CI and in every doc command.
- **minSdk 24.** `camera` and `google_mlkit_face_detection` impose a floor of 21; do not go below 24.
- **`compileSdk`, `targetSdk`, `ndkVersion` are pinned explicitly** to whatever values the Flutter 3.44.8 template emits. Never leave `ndkVersion` implicit.
- **Application IDs:** `dev` → `com.acsl.campaign.dev`; `stg` → `com.acsl.campaign.stg`; `prod` → `com.acsl.campaign` (bare — production identity is never suffixed).
- **Generated code stays gitignored** (`*.g.dart`, `*.freezed.dart`, `lib/l10n/generated/`). CI regenerates it.
- **`pubspec.lock` is committed**, and every bootstrap uses `flutter pub get --enforce-lockfile`.
- **Bootstrap order is mandatory and unchanging:** `pub get --enforce-lockfile` → `flutter gen-l10n` → `dart run build_runner build --delete-conflicting-outputs` → `flutter analyze --fatal-infos`. Analyze fails before generation on a clean clone.
- **No location permission** in the Android manifest. Capture geo-metadata belongs to backlog item P0.15.
- **No R8/ProGuard rules.** Flutter's release template does not minify; keep-rules would be dead config.
- **`flutter analyze --fatal-infos` must exit 0.**
- **The test suite is 30 tests, all passing** (verified 2026-07-30 on Flutter 3.44.8). It must stay at 30+ and green.
- **Never commit** `android/key.properties` or `*.jks` (already covered by `.gitignore:30-31`).
- **Maestro `appId` must resolve to the installed flavor's application ID** — CI installs `dev`.
- **Emulator:** API 33, `google_apis`, `x86_64`.
- **Flow selection:** PR → `pr-smoke` tag (2 flows). Nightly/manual → `android` tag (7 flows). `campaign_list_smoke` is never in an automated job.

---

## File Structure

**Created:**

| Path | Responsibility |
|---|---|
| `android/**` | Generated Android runner. Only `app/build.gradle.kts` and `app/src/main/AndroidManifest.xml` are hand-edited. |
| `tool/scripts/flavors.env` | Single source of truth mapping flavor → `API_BASE_URL` + `MEDIA_HOST`. Read by both the PowerShell and bash wrappers, so the mapping is never duplicated. |
| `tool/scripts/run.ps1` | Local dev entry point (Windows). Takes one flavor argument, emits the matching Gradle flavor *and* dart-defines. |
| `tool/scripts/build_e2e_apk.sh` | CI: builds the dev-flavor debug APK with E2E dart-defines. |
| `tool/scripts/run_maestro.sh` | CI: starts nothing, assumes emulator is up; runs Maestro for a tag selector with one retry. |
| `.github/workflows/ci.yml` | Both CI jobs (`gate`, `e2e`). |
| `test/app/flavor_parsing_test.dart` | Unit tests for flavor-name parsing and env defaults. |
| `pubspec.lock` | Now committed (was gitignored). |

**Modified:**

| Path | Change |
|---|---|
| `.gitignore` | Remove `pubspec.lock`; add `android/local.properties`, `android/.gradle/`, `android/.kotlin/`. |
| `pubspec.yaml:18,72` | Delete `riverpod_annotation` and `riverpod_generator`. |
| `lib/app/flavors.dart` | Extract `parseFlavor(String)` as a testable top-level function. |
| `.maestro/**` (11 files) | `appId: com.acsl.campaign` → parameterized; add `pr-smoke` / `android` tags. |
| `ARCHITECTURE_Flutter.md:166,177,326` | Riverpod codegen → manual providers. |
| `TASK_BREAKDOWN.md:11` + Epic P0.1 table | Honest status; correct test count to 30. |
| `README.md:9-11,15,27,72,123` | Bootstrap order, flavor scripts, drop `riverpod_generator` mentions, CI badge. |

---

## Task 1: Create and correct the Android platform

Closes T-0.1.1. This task is the gate for everything else — without `android/` there is no APK, no emulator job, and no Phase P2.

**Files:**
- Create: `android/**` (via `flutter create`)
- Modify: `android/app/build.gradle.kts`, `android/app/src/main/kotlin/**/MainActivity.kt`, `.gitignore`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a buildable Android target with `applicationId = "com.acsl.campaign"` and namespace `com.acsl.campaign`; APK at `build/app/outputs/flutter-apk/app-debug.apk`. Task 2 adds flavors on top of this; Task 5 and 8 build it in CI.

- [ ] **Step 1: Verify the Android toolchain exists — hard prerequisite**

Run: `flutter doctor -v`

Expected: a checkmark for "Android toolchain — develop for Android devices" and a JDK line. `README.md:123` already warns Android needs a JDK + Android SDK that web development does not.

**If the Android toolchain is missing, stop and install it before continuing** — install Android Studio (or `cmdline-tools` + platform-tools), then `flutter doctor --android-licenses`. Do not proceed to Step 2 without it; decision D5 exists specifically so this failure surfaces on your machine in seconds instead of through 10-minute CI cycles.

- [ ] **Step 2: Confirm the current failure**

Run: `flutter build apk --debug`

Expected: FAIL — no APK is produced, because the project has no Android platform directory. (Exact wording varies by Flutter version; the point is the absence of `build/app/outputs/flutter-apk/app-debug.apk`.)

- [ ] **Step 3: Generate the Android runner**

```bash
flutter create --platforms=android --org com.acsl .
```

This touches only platform folders — it will not overwrite `lib/`, `web/`, or `pubspec.yaml`.

- [ ] **Step 4: Inspect what the template actually produced**

```bash
ls android/app
cat android/app/build.gradle.kts
```

Record two things: the emitted `applicationId` (it will be derived from org + project name — something like `com.acsl.acsl_campaign`, **not** `com.acsl.campaign`), and the exact `compileSdk` / `targetSdk` / `ndkVersion` values. You need those values verbatim in Step 5.

If the template emitted Groovy (`build.gradle`) rather than Kotlin DSL (`build.gradle.kts`), use Groovy syntax throughout — translate the snippets in this plan rather than fighting the template.

- [ ] **Step 5: Correct the namespace and application ID**

In `android/app/build.gradle.kts`, set both to `com.acsl.campaign` and pin the SDK values you recorded (substitute the real numbers from Step 4):

```kotlin
android {
    namespace = "com.acsl.campaign"
    compileSdk = 36          // ← the value from Step 4
    ndkVersion = "27.0.12077973"  // ← the value from Step 4, never left implicit

    defaultConfig {
        applicationId = "com.acsl.campaign"
        minSdk = 24          // camera + ML Kit floor is 21; 24 for a corporate fleet
        targetSdk = 36       // ← the value from Step 4
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
}
```

- [ ] **Step 6: Move MainActivity to the matching package**

The generated Kotlin file sits under a path matching the *old* ID. Move it and fix its package declaration:

```bash
mkdir -p android/app/src/main/kotlin/com/acsl/campaign
git mv android/app/src/main/kotlin/com/acsl/acsl_campaign/MainActivity.kt \
       android/app/src/main/kotlin/com/acsl/campaign/MainActivity.kt 2>/dev/null || \
  mv android/app/src/main/kotlin/com/acsl/acsl_campaign/MainActivity.kt \
     android/app/src/main/kotlin/com/acsl/campaign/MainActivity.kt
rm -rf android/app/src/main/kotlin/com/acsl/acsl_campaign
```

Then edit the file so its first line reads:

```kotlin
package com.acsl.campaign

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
```

- [ ] **Step 7: Add the four required permissions**

In `android/app/src/main/AndroidManifest.xml`, immediately before the `<application>` tag:

```xml
<!-- camera: attendance evidence capture -->
<uses-permission android:name="android.permission.CAMERA" />
<!-- dio + connectivity_plus -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<!-- workmanager: background sync survives app death -->
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

Do **not** add any location permission. Capture geo-metadata is backlog item P0.15, and an unused location permission is a privacy-review liability.

- [ ] **Step 8: Extend .gitignore for Android build noise**

Add to `.gitignore` under the Flutter/Dart section:

```gitignore
android/local.properties
android/.gradle/
android/.kotlin/
```

The existing `build/` rule (line 6) already covers `android/app/build/` at any depth, and `key.properties` / `upload-keystore.jks` are already handled at lines 30-31.

- [ ] **Step 9: Verify the APK builds**

Run: `flutter build apk --debug`

Expected: PASS, ending in `✓ Built build/app/outputs/flutter-apk/app-debug.apk`.

If it fails on an NDK version mismatch, set `ndkVersion` to the exact version the error message demands — that is the failure the explicit pin in Step 5 exists to prevent recurring.

- [ ] **Step 10: Verify the app runs on a device**

Start an Android emulator, then:

```bash
flutter run --dart-define=FLAVOR=dev
```

Expected: the app launches. This is done-criterion 1 of the spec, and cannot be satisfied by a build alone.

- [ ] **Step 11: Verify nothing regressed**

```bash
flutter analyze --fatal-infos
flutter test
```

Expected: analyze exits 0; 30 tests pass.

- [ ] **Step 12: Commit**

```bash
git add android .gitignore
git commit -m "feat(android): add Android platform with corrected com.acsl.campaign ID

Closes T-0.1.1. minSdk 24 (camera + ML Kit floor is 21); compileSdk,
targetSdk and ndkVersion pinned explicitly. Permissions limited to camera,
internet, network state, wake lock and boot-completed - no location, which
belongs to P0.15."
```

---

## Task 2: Product flavors, flavor parsing, and wrapper scripts

Closes T-0.1.2. Adds three flavors with distinct application IDs, plus the scripts that stop anyone pairing a dev Gradle flavor with a production API.

**Files:**
- Modify: `android/app/build.gradle.kts`, `lib/app/flavors.dart`
- Create: `test/app/flavor_parsing_test.dart`, `tool/scripts/flavors.env`, `tool/scripts/run.ps1`

**Interfaces:**
- Consumes: the `android/` platform and `applicationId = "com.acsl.campaign"` from Task 1.
- Produces: Gradle flavors named exactly `dev`, `stg`, `prod` (referenced by `flutter build apk --flavor dev` in Tasks 5 and 8); APK path `build/app/outputs/flutter-apk/app-dev-debug.apk`; a top-level Dart function `Flavor parseFlavor(String name)`; `tool/scripts/flavors.env` with keys `<flavor>_API_BASE_URL` and `<flavor>_MEDIA_HOST`.

- [ ] **Step 1: Write the failing test for flavor parsing**

Create `test/app/flavor_parsing_test.dart`:

```dart
import 'package:acsl_campaign/app/flavors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseFlavor', () {
    test('resolves each known flavor name', () {
      expect(parseFlavor('dev'), Flavor.dev);
      expect(parseFlavor('stg'), Flavor.stg);
      expect(parseFlavor('prod'), Flavor.prod);
    });

    test('falls back to dev for an unknown name', () {
      // A typo must never silently resolve to prod. Failing closed to dev
      // points the app at the dev API, which is the safe direction.
      expect(parseFlavor('production'), Flavor.dev);
      expect(parseFlavor(''), Flavor.dev);
      expect(parseFlavor('PROD'), Flavor.dev);
    });
  });

  group('AppConfig.fromEnvironment', () {
    test('with no dart-defines yields the dev defaults', () {
      final config = AppConfig.fromEnvironment();
      expect(config.flavor, Flavor.dev);
      expect(config.isProd, isFalse);
      expect(config.apiBaseUrl, 'https://dev.api.example/campaign');
      expect(config.e2e, isFalse);
      expect(config.e2eRole, 'field_user');
    });
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/app/flavor_parsing_test.dart`

Expected: FAIL at compile time — `parseFlavor` is not defined (it is currently an inline closure inside `AppConfig.fromEnvironment`).

- [ ] **Step 3: Extract parseFlavor**

In `lib/app/flavors.dart`, add the top-level function after the enum:

```dart
/// Maps a `FLAVOR` dart-define to its enum. An unrecognized name falls back to
/// [Flavor.dev] — failing closed toward the dev API rather than production.
Flavor parseFlavor(String name) => Flavor.values.firstWhere(
      (f) => f.name == name,
      orElse: () => Flavor.dev,
    );
```

Then replace the inline `firstWhere` in `AppConfig.fromEnvironment()` (currently `flavors.dart:35-38`) with:

```dart
      flavor: parseFlavor(flavorName),
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/app/flavor_parsing_test.dart`

Expected: PASS, 2 groups / 3 tests.

- [ ] **Step 5: Add the Gradle product flavors**

In `android/app/build.gradle.kts`, inside the `android { }` block after `defaultConfig`:

```kotlin
    flavorDimensions += "env"

    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "ACSL Campaign Dev")
        }
        create("stg") {
            dimension = "env"
            applicationIdSuffix = ".stg"
            resValue("string", "app_name", "ACSL Campaign Staging")
        }
        create("prod") {
            dimension = "env"
            // No suffix: production keeps the bare com.acsl.campaign identity.
            resValue("string", "app_name", "ACSL Campaign")
        }
    }
```

For `resValue` to take effect, `AndroidManifest.xml`'s `<application>` tag must reference it:

```xml
android:label="@string/app_name"
```

- [ ] **Step 6: Verify all three flavors build with distinct IDs**

```bash
flutter build apk --flavor dev  --debug
flutter build apk --flavor stg  --debug
flutter build apk --flavor prod --debug
ls build/app/outputs/flutter-apk/
```

Expected: three APKs — `app-dev-debug.apk`, `app-stg-debug.apk`, `app-prod-debug.apk`.

Confirm the IDs differ (requires Android SDK build-tools on PATH):

```bash
aapt dump badging build/app/outputs/flutter-apk/app-dev-debug.apk | grep package
```

Expected: `package: name='com.acsl.campaign.dev'`. This is done-criterion 2.

- [ ] **Step 7: Create the single-source-of-truth env map**

Create `tool/scripts/flavors.env`:

```sh
# Flavor -> environment mapping. Read by tool/scripts/run.ps1 (local dev) and by
# CI. This is the ONLY place these URLs are written; never inline them into a
# workflow or a launch config.
dev_API_BASE_URL=https://dev.api.example/campaign
dev_MEDIA_HOST=https://dev.media.example
stg_API_BASE_URL=https://stg.api.example/campaign
stg_MEDIA_HOST=https://stg.media.example
prod_API_BASE_URL=https://api.example/campaign
prod_MEDIA_HOST=https://media.example
```

- [ ] **Step 8: Create the local run wrapper**

Create `tool/scripts/run.ps1`:

```powershell
<#
.SYNOPSIS
  Runs the app with a Gradle flavor and its MATCHING dart-defines.

.DESCRIPTION
  Gradle flavors and --dart-define are independent: nothing stops
  `--flavor dev --dart-define=FLAVOR=prod`, which installs a dev-ID app
  pointed at the production API. This script derives both from one argument
  so they cannot disagree. Values come from tool/scripts/flavors.env.

.EXAMPLE
  ./tool/scripts/run.ps1 -Flavor dev -Device chrome
  ./tool/scripts/run.ps1 -Flavor stg
#>
param(
  [ValidateSet('dev', 'stg', 'prod')][string]$Flavor = 'dev',
  [string]$Device = ''
)

$ErrorActionPreference = 'Stop'
$envFile = Join-Path $PSScriptRoot 'flavors.env'

$map = @{}
foreach ($line in Get-Content $envFile) {
  if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
  $parts = $line -split '=', 2
  $map[$parts[0].Trim()] = $parts[1].Trim()
}

$apiBase = $map["${Flavor}_API_BASE_URL"]
$mediaHost = $map["${Flavor}_MEDIA_HOST"]
if (-not $apiBase -or -not $mediaHost) {
  throw "flavors.env is missing entries for flavor '$Flavor'"
}

$args = @(
  '--dart-define=FLAVOR=' + $Flavor,
  '--dart-define=API_BASE_URL=' + $apiBase,
  '--dart-define=MEDIA_HOST=' + $mediaHost
)

# Gradle flavors only exist on Android; the web target takes dart-defines only.
if ($Device -eq 'chrome') {
  Write-Host "flutter run -d chrome ($Flavor)" -ForegroundColor Cyan
  & flutter run -d chrome @args
} else {
  $deviceArgs = if ($Device) { @('-d', $Device) } else { @() }
  Write-Host "flutter run --flavor $Flavor" -ForegroundColor Cyan
  & flutter run @deviceArgs '--flavor' $Flavor @args
}
```

- [ ] **Step 9: Verify the wrapper works for both targets**

```powershell
./tool/scripts/run.ps1 -Flavor dev -Device chrome
./tool/scripts/run.ps1 -Flavor dev
```

Expected: the first launches in Chrome, the second on the Android emulator with the dev flavor. Then confirm the guard rail:

```powershell
./tool/scripts/run.ps1 -Flavor nope
```

Expected: FAIL immediately from `ValidateSet` — an invalid flavor never reaches Flutter.

- [ ] **Step 10: Full verification**

```bash
flutter analyze --fatal-infos
flutter test
```

Expected: analyze exits 0; **33 tests pass** (30 existing + 3 new).

- [ ] **Step 11: Commit**

```bash
git add android lib/app/flavors.dart test/app/flavor_parsing_test.dart tool/scripts
git commit -m "feat(android): add dev/stg/prod flavors with matched dart-defines

Closes T-0.1.2. Distinct application IDs per flavor (prod keeps the bare
com.acsl.campaign). parseFlavor is extracted and unit-tested, including the
fail-closed fallback to dev for unknown names. tool/scripts/run.ps1 derives
the Gradle flavor and dart-defines from one argument so they cannot disagree."
```

---

## Task 3: Reproducible dependencies and honest codegen

Closes T-0.1.5. Deletes two dependencies that generate nothing and commits the lockfile.

**Files:**
- Modify: `pubspec.yaml:18,72`, `.gitignore:9`
- Create (commit): `pubspec.lock`

**Interfaces:**
- Consumes: nothing from Tasks 1-2.
- Produces: a committed `pubspec.lock`; the bootstrap contract `flutter pub get --enforce-lockfile` that Tasks 5 and 8 rely on; a build graph containing only `freezed`, `json_serializable`, `drift_dev`.

- [ ] **Step 1: Confirm the two dependencies are genuinely unused**

```bash
grep -rn "riverpod_annotation\|riverpod_generator\|@riverpod" lib test
```

Expected: **no matches** in `lib/` or `test/`. (Verified 2026-07-30: they appear only at `pubspec.yaml:18` and `pubspec.yaml:72`.) If this command returns any hit inside `lib/` or `test/`, stop — the removal is no longer safe and the spec's decision D3 needs revisiting.

- [ ] **Step 2: Remove both dependencies**

Delete `pubspec.yaml:18`:

```yaml
  riverpod_annotation: ^2.3.5
```

Delete `pubspec.yaml:72`:

```yaml
  riverpod_generator: ^2.4.0
```

Leave `flutter_riverpod: ^2.5.1` alone — that is the runtime the app actually uses.

- [ ] **Step 3: Stop ignoring the lockfile**

Delete `pubspec.lock` from `.gitignore` (currently line 9). Keep every other ignore rule untouched — generated code stays ignored by design.

- [ ] **Step 4: Regenerate and verify the build graph is clean**

```bash
flutter pub get
flutter pub deps --style=list | grep -i riverpod
```

Expected: `flutter_riverpod` and its transitive `riverpod`/`state_notifier` appear; **`riverpod_generator` and `riverpod_annotation` do not**.

- [ ] **Step 5: Verify codegen still produces everything**

```bash
rm -rf lib/l10n/generated
find lib -name "*.g.dart" -o -name "*.freezed.dart" | xargs rm -f
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
```

Expected: PASS. Then confirm all 12 outputs came back:

```bash
find lib -name "*.freezed.dart" | wc -l   # expect 8
find lib -name "*.g.dart" | wc -l         # expect 2
ls lib/l10n/generated                     # expect 3 files
```

- [ ] **Step 6: Verify the lockfile is enforceable**

```bash
flutter pub get --enforce-lockfile
```

Expected: PASS with no resolution changes. If it fails, the lockfile is out of sync with `pubspec.yaml` — rerun `flutter pub get` and commit the updated lockfile.

- [ ] **Step 7: Full verification**

```bash
flutter analyze --fatal-infos
flutter test
```

Expected: analyze exits 0; 33 tests pass.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock .gitignore
git commit -m "build: commit lockfile, drop unused Riverpod codegen deps

Closes T-0.1.5. riverpod_annotation and riverpod_generator appeared only in
pubspec.yaml with zero imports and zero @riverpod annotations; removing them
takes two builders out of the build_runner graph. pubspec.lock is now
committed so CI can use --enforce-lockfile and builds are reproducible from
a commit SHA."
```

---

## Task 4: Correct the three docs that describe removed or missing things

No task in this epic ships code that contradicts its own documentation. Three docs currently describe a codegen setup that no longer exists, an Android platform that never existed, and a test count that is wrong.

**Files:**
- Modify: `ARCHITECTURE_Flutter.md:166,177,326`, `TASK_BREAKDOWN.md:11` + Epic P0.1 table (lines 26-33), `README.md:9-11,15,27,72,123`

**Interfaces:**
- Consumes: the decisions realized in Tasks 1-3.
- Produces: docs whose commands match §5.2 of the spec. No code depends on this task.

- [ ] **Step 1: Amend ARCHITECTURE_Flutter.md §6**

Replace line 166:

```markdown
**Choice: Riverpod (v2, code-gen)** as the single state solution.
```

with:

```markdown
**Choice: Riverpod (v2, manual providers)** as the single state solution.

> **Amended 2026-07-30 (Epic P0.1):** the original plan specified code-gen
> (`riverpod_generator`). In practice all ~30 providers are hand-written and the
> generator was never adopted, so its dependencies were removed rather than left
> declared-but-unused. Revisit code-gen when parameterized (`family`) providers
> become painful enough to justify migrating; the layering above is unaffected
> either way.
```

- [ ] **Step 2: Fix the stale BLoC comparison at line 177**

Replace:

```markdown
> Alternative considered: BLoC. Rejected only to reduce boilerplate; Riverpod covers the same guarantees with codegen. Either is defensible — the layering above is state-library-agnostic.
```

with:

```markdown
> Alternative considered: BLoC. Rejected only to reduce boilerplate; Riverpod covers the same guarantees. Either is defensible — the layering above is state-library-agnostic.
```

- [ ] **Step 3: Fix the §15 package table at line 326**

Replace `| State/DI | `flutter_riverpod`, `riverpod_generator` |` with:

```markdown
| State/DI | `flutter_riverpod` |
```

- [ ] **Step 4: Correct the Epic P0.1 status claims in TASK_BREAKDOWN.md**

In the "Implemented so far" block, line 11 reads `flutter test` 15/15. The suite is **30 tests** (verified 2026-07-30). Update that number.

Then replace the Epic P0.1 table (lines 27-33) with a version carrying real status:

```markdown
| ID | Task | Est | Deps | Status (2026-07-30) |
|----|------|-----|------|---------------------|
| T-0.1.1 | `flutter create` with web + android platforms; adopt scaffold in this repo | S | — | ✅ web + android; runs on Chrome and Android emulator |
| T-0.1.2 | Configure flavors (dev/stg/prod) + `--dart-define` env (API base, media host) | M | 0.1.1 | ✅ Gradle flavors with distinct app IDs + `tool/scripts/run.ps1` |
| T-0.1.3 | `analysis_options.yaml` (strict lints), format + import-order rules | S | 0.1.1 | ✅ enforced in CI with `--fatal-infos` |
| T-0.1.4 | CI pipeline: analyze → test → build web + apk; artifact upload | M | 0.1.3 | ✅ `.github/workflows/ci.yml` (`gate` + `e2e`) |
| T-0.1.5 | Codegen wiring (`build_runner`, freezed, riverpod_generator, drift, l10n) | M | 0.1.1 | ✅ freezed + json_serializable + drift + gen-l10n. Riverpod codegen dropped — see ARCHITECTURE §6 amendment |
```

- [ ] **Step 5: Rewrite the README quick start**

Replace lines 9-21 (the note about running `flutter create` plus the bootstrap block) with:

````markdown
> Verified on **Flutter 3.44.8 / Dart 3.12.2** (min Flutter ≥ 3.22). Both the
> `web/` and `android/` runners are committed. Android additionally needs a JDK
> and the Android SDK; web and `flutter test` do not.

```bash
flutter pub get --enforce-lockfile   # lockfile is committed; fail loudly on drift
flutter gen-l10n                     # generate AppL10n from lib/l10n/*.arb
dart run build_runner build --delete-conflicting-outputs   # freezed / json / drift
flutter analyze --fatal-infos
```

Generated code is gitignored, so **this order matters** — analyze fails on a
clean clone until `gen-l10n` and `build_runner` have run.

Run the app through the flavor wrapper, which keeps the Gradle flavor and the
dart-defines in sync (they are independent, and mismatching them installs a dev
app pointed at production):

```powershell
./tool/scripts/run.ps1 -Flavor dev -Device chrome   # web
./tool/scripts/run.ps1 -Flavor dev                 # Android emulator
```
````

- [ ] **Step 6: Drop the remaining riverpod_generator references**

At `README.md:15` the codegen comment ends `# freezed / json / drift / riverpod` — drop the trailing ` / riverpod`. At line 27, replace the sentence:

```markdown
Codegen must run before the first build: `freezed`/`json_serializable` (models), `drift_dev` (offline DB), `riverpod_generator` (if you adopt annotated providers), and `gen-l10n` (localization).
```

with:

```markdown
Codegen must run before the first build: `freezed`/`json_serializable` (models), `drift_dev` (offline DB), and `gen-l10n` (localization). Providers are hand-written — there is no Riverpod code generation (see `ARCHITECTURE_Flutter.md` §6).
```

- [ ] **Step 7: Update the status and known-gaps lines**

At `README.md:72`, keep `30/30` but add the analyze flag: `` `flutter analyze --fatal-infos` clean ``. At line 123, replace the Android/iOS gap bullet:

```markdown
- **Android/iOS:** needs a JDK + Android SDK (not required for web or `flutter test`).
```

with:

```markdown
- **iOS:** no runner committed (gitignored by policy); Android is the field target.
```

- [ ] **Step 8: Add the CI badge**

Immediately under the `# ACSL Carpenter Campaign Management` heading:

```markdown
[![CI](https://github.com/Asim971/camp_management/actions/workflows/ci.yml/badge.svg)](https://github.com/Asim971/camp_management/actions/workflows/ci.yml)
```

- [ ] **Step 9: Verify every command in the README actually runs**

Execute each command from the rewritten quick start in order, from the repo root. Expected: all four succeed. A README command that does not run is worse than no README.

- [ ] **Step 10: Commit**

```bash
git add ARCHITECTURE_Flutter.md TASK_BREAKDOWN.md README.md
git commit -m "docs: reconcile architecture, task breakdown and README with P0.1

Amends ARCHITECTURE section 6 to manual Riverpod providers (codegen deps were
removed in the prior commit), corrects the Epic P0.1 status rows, fixes the
stale 15/15 test count to 30, and documents the mandatory bootstrap order plus
the flavor wrapper."
```

---

## Task 5: The fast CI gate

Closes the first half of T-0.1.4.

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: Gradle flavor `dev` (Task 2); committed `pubspec.lock` (Task 3).
- Produces: a job named exactly **`gate`** (Task 6 requires it in branch protection; Task 8 declares `needs: gate`); artifacts named `web-build` and `apk-dev-debug`.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

# A force-push should cancel the superseded run rather than queue behind it.
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

env:
  FLUTTER_VERSION: 3.44.8

jobs:
  gate:
    name: gate
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4

      # Flutter's Android build needs a JDK; the runner's default is not guaranteed.
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true

      # --enforce-lockfile: fail on lockfile drift instead of silently resolving
      # something newer. This is why pubspec.lock is committed.
      - name: Resolve dependencies
        run: flutter pub get --enforce-lockfile

      # Generated code is gitignored, so it must be produced before analyze.
      - name: Generate localizations
        run: flutter gen-l10n

      - name: Run code generation
        run: dart run build_runner build --delete-conflicting-outputs

      - name: Analyze
        run: flutter analyze --fatal-infos

      - name: Test
        run: flutter test

      - name: Build web
        run: flutter build web --release

      - name: Build APK (dev flavor)
        run: flutter build apk --flavor dev --debug

      - uses: actions/upload-artifact@v4
        with:
          name: web-build
          path: build/web
          retention-days: 7

      - uses: actions/upload-artifact@v4
        with:
          name: apk-dev-debug
          path: build/app/outputs/flutter-apk/app-dev-debug.apk
          retention-days: 7
```

- [ ] **Step 2: Commit and push to a branch**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add fast gate job (analyze, test, web + apk builds)

Closes the first half of T-0.1.4. Pins Flutter 3.44.8 and uses
--enforce-lockfile so a red gate means this change broke, not a transitive
caret bump. Generated code is produced in-job because it is gitignored."
git push -u origin HEAD
```

- [ ] **Step 3: Watch the first run and read the failure**

```bash
gh run watch
```

Expected on a first attempt: quite possibly FAIL. Work the failures in order — the three likely ones are a lockfile that needs regenerating under `--enforce-lockfile`, an `--fatal-infos` info-level diagnostic that never surfaced locally, and a Gradle/JDK mismatch on the APK step. Fix, push, repeat until green.

- [ ] **Step 4: Confirm green and artifacts present**

```bash
gh run list --limit 1
gh run view --log | tail -30
```

Expected: `gate` succeeded, with `web-build` and `apk-dev-debug` both listed as artifacts.

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "ci: fix gate job failures surfaced by the first run"
git push
```

---

## Task 6: Prove the gate actually blocks

This is done-criterion 4. Until a deliberately-broken PR is *rejected*, "PR blocks on red CI" is an untested claim — an unset required check produces a green-looking pipeline that gates nothing.

**Files:** none committed to `main`. This task creates and deletes a throwaway branch.

**Interfaces:**
- Consumes: the green `gate` job from Task 5.
- Produces: branch protection on `main` requiring `gate`. No code artifacts.

- [ ] **Step 1: Enable branch protection requiring the gate**

```bash
gh api -X PUT repos/Asim971/camp_management/branches/main/protection \
  -H "Accept: application/vnd.github+json" \
  -F "required_status_checks[strict]=true" \
  -F "required_status_checks[contexts][]=gate" \
  -F "enforce_admins=false" \
  -F "required_pull_request_reviews[required_approving_review_count]=0" \
  -F "restrictions=" \
  -F "allow_force_pushes=false"
```

Expected: a JSON body describing the protection rule.

**If this returns 403 or "Upgrade to GitHub Pro":** classic branch protection is not available on this plan for a private repository. Record that limitation in the PR description and try a repository ruleset instead (Settings → Rules → Rulesets → New branch ruleset → require status checks → `gate`). If neither is available, this epic's done-criterion 4 is **partially blocked** — the workflow still reports red, but merges are not mechanically prevented. Say so explicitly rather than reporting the criterion met.

- [ ] **Step 2: Create the probe branch with a lint violation**

```bash
git checkout -b chore/verify-ci-gate
```

Create `test/ci_gate_probe_test.dart`:

```dart
// TEMPORARY probe for T-0.1.4 - deleted at the end of Task 6.
// `print` violates the avoid_print rule in analysis_options.yaml.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe', () {
    print('this line must fail analyze');
    expect(1, 1);
  });
}
```

- [ ] **Step 3: Push and confirm analyze turns the gate red**

```bash
git add test/ci_gate_probe_test.dart
git commit -m "test: temporary CI gate probe (lint violation)"
git push -u origin chore/verify-ci-gate
gh pr create --title "TEMP: verify CI gate blocks" --body "Throwaway PR proving T-0.1.4. Do not merge." --draft
gh run watch
```

Expected: FAIL at the **Analyze** step, reporting `avoid_print`. Confirm the PR shows a failing required check and that merging is blocked.

- [ ] **Step 4: Swap the lint error for a failing test**

Replace the probe file contents:

```dart
// TEMPORARY probe for T-0.1.4 - deleted at the end of Task 6.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe fails on purpose', () {
    expect(2 + 2, 5);
  });
}
```

```bash
git commit -am "test: probe now fails at the test step"
git push
gh run watch
```

Expected: Analyze passes; FAIL at the **Test** step with `Expected: 5 Actual: 4`. This proves the second gate independently — the first probe stopped the job before `flutter test` ever ran.

- [ ] **Step 5: Break the web build**

```dart
// TEMPORARY probe for T-0.1.4 - deleted at the end of Task 6.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe passes', () {
    expect(1, 1);
  });
}
```

Then introduce a compile error the analyzer will also catch, confirming the build step is reached only when earlier steps pass. Append to the probe file:

```dart
// Deliberate type error for the build/analyze gate.
int probeTypeError() => 'not an int';
```

```bash
git commit -am "test: probe introduces a type error"
git push
gh run watch
```

Expected: FAIL at **Analyze** (a type error is an analyzer error, so it is caught before the build). Record which step caught it — the useful outcome is knowing the gate's ordering, not forcing a failure at one specific step.

- [ ] **Step 6: Tear down the probe**

```bash
gh pr close chore/verify-ci-gate --delete-branch
git checkout -   # back to the feature branch
```

Verify nothing leaked:

```bash
git log --oneline -3
ls test/ci_gate_probe_test.dart 2>/dev/null || echo "probe absent - good"
```

Expected: `probe absent - good`, and no probe commits on the working branch.

- [ ] **Step 7: Record the result**

Append to the plan's task list (or the PR description for the epic) which failure modes were proven and whether branch protection was mechanically enforceable. If Step 1 was blocked, this is the place that must say so.

---

## Task 7: Parameterize Maestro appId and add selector tags

Prerequisite for Task 8. CI installs the `dev` flavor (`com.acsl.campaign.dev`), but all 11 `.maestro/` files hardcode `com.acsl.campaign`.

**Files:**
- Modify: `.maestro/config.yaml`, `.maestro/subflows/launch_as_field_user.yaml`, `.maestro/subflows/launch_as_crm.yaml`, and all 8 files in `.maestro/flows/`

**Interfaces:**
- Consumes: application ID `com.acsl.campaign.dev` from Task 2.
- Produces: every flow resolving its appId from the `APP_ID` env var; tag `pr-smoke` on exactly `field_online_capture` and `crm_case_decision`; tag `android` on the 7 non-web flows. Task 8's `run_maestro.sh` selects on those tags.

- [ ] **Step 1: Verify Maestro interpolates env vars in the appId field**

This is the spec's one explicitly unverified assumption (§4.3). Test it on a single file before touching eleven.

Edit `.maestro/flows/field_online_capture.yaml:3` to `appId: ${APP_ID}`, install the dev-flavor APK on an emulator, then:

```bash
maestro test --env APP_ID=com.acsl.campaign.dev .maestro/flows/field_online_capture.yaml
```

Expected if supported: the flow launches the app normally.
Expected if unsupported: Maestro errors on the appId (e.g. an invalid/unknown package name containing a literal `${APP_ID}`).

**If unsupported, use fallback (a) from the spec:** keep the literal appId in the files and have CI rewrite it before running. Add to `tool/scripts/run_maestro.sh` in Task 8, before invoking Maestro:

```bash
# Fallback: Maestro does not interpolate env vars inside `appId`.
find .maestro -name '*.yaml' -exec sed -i "s/^appId: com\.acsl\.campaign$/appId: ${APP_ID}/" {} +
```

Do **not** adopt fallback (b) — suffixing production to `com.acsl.campaign.prod` trades a permanent store identity for a CI convenience. Record which path you took at the top of `run_maestro.sh`.

- [ ] **Step 2: Apply the appId change to all 11 files**

If Step 1 showed interpolation works, replace `appId: com.acsl.campaign` with `appId: ${APP_ID}` in each of:

| File | appId line |
|---|---|
| `.maestro/config.yaml` | 2 |
| `.maestro/subflows/launch_as_field_user.yaml` | 4 |
| `.maestro/subflows/launch_as_crm.yaml` | 2 |
| `.maestro/flows/campaign_list_smoke.yaml` | 4 |
| `.maestro/flows/carpenter_search_confirm.yaml` | 3 |
| `.maestro/flows/crm_case_conflict.yaml` | 4 |
| `.maestro/flows/crm_case_decision.yaml` | 4 |
| `.maestro/flows/field_capture_recapture.yaml` | 4 |
| `.maestro/flows/field_offline_capture.yaml` | 3 |
| `.maestro/flows/field_online_capture.yaml` | 3 |
| `.maestro/flows/offline_queue_retry.yaml` | 4 |

- [ ] **Step 3: Add the two selector tags**

The existing tags cannot express the CI policy: `critical` is on `field_online_capture`, `crm_case_decision` **and** `field_offline_capture`, so selecting `critical` would drag the nightly-only offline flow onto the PR path. Add `pr-smoke` and `android` to the existing `tags:` lists (keep all current tags):

| Flow | Final tags |
|---|---|
| `field_online_capture` | `field`, `critical`, `android`, `pr-smoke` |
| `crm_case_decision` | `crm`, `critical`, `android`, `pr-smoke` |
| `field_offline_capture` | `field`, `critical`, `offline`, `android` |
| `offline_queue_retry` | `field`, `offline`, `android` |
| `carpenter_search_confirm` | `field`, `android` |
| `field_capture_recapture` | `field`, `android` |
| `crm_case_conflict` | `crm`, `android` |
| `campaign_list_smoke` | `web`, `smoke` — **no `android` tag** |

`campaign_list_smoke` deliberately keeps no `android` tag: it is a web flow and TC-E2E-07 needs the mock server restarted three times with different `MOCK_CAMPAIGNS` values, so it can never pass in the emulator job.

- [ ] **Step 4: Verify tag selection picks the right flows**

```bash
maestro test --env APP_ID=com.acsl.campaign.dev --include-tags pr-smoke .maestro/ --dry-run || true
```

Expected: exactly 2 flows selected. Then:

```bash
maestro test --env APP_ID=com.acsl.campaign.dev --include-tags android .maestro/ --dry-run || true
```

Expected: exactly 7 flows, with `campaign_list_smoke` absent.

If your Maestro version has no `--dry-run`, verify by grep instead:

```bash
grep -l "pr-smoke" .maestro/flows/*.yaml | wc -l   # expect 2
grep -l "  - android" .maestro/flows/*.yaml | wc -l # expect 7
```

- [ ] **Step 5: Run one real flow end to end locally**

Start the mock server, install the E2E APK, and run the smoke selector:

```bash
cd tool/mock_server && dart pub get && dart run bin/server.dart &
cd ../..
flutter build apk --flavor dev --debug \
  --dart-define=E2E=true --dart-define=LOCALE=en \
  --dart-define=API_BASE_URL=http://10.0.2.2:8080
adb install -r build/app/outputs/flutter-apk/app-dev-debug.apk
maestro test --env APP_ID=com.acsl.campaign.dev --include-tags pr-smoke .maestro/
```

Expected: both smoke flows pass. Getting this green locally before wiring CI is the whole point of sequencing decision D5.

- [ ] **Step 6: Commit**

```bash
git add .maestro
git commit -m "test(e2e): parameterize Maestro appId, add pr-smoke/android tags

CI installs the dev flavor (com.acsl.campaign.dev), so the hardcoded appId in
all 11 .maestro files would target an app that is not on the emulator. Adds
pr-smoke (2 flows) and android (7 flows) selectors because the existing
critical tag also covers the nightly-only offline flow. campaign_list_smoke
stays out of the android set - it is web-only and needs mock server restarts."
```

---

## Task 8: The emulator E2E job

Closes the second half of T-0.1.4 at decision D4's scope.

**Files:**
- Create: `tool/scripts/build_e2e_apk.sh`, `tool/scripts/run_maestro.sh`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: job `gate` (Task 5); Maestro tags and `APP_ID` handling (Task 7); `tool/mock_server/bin/server.dart` on port 8080.
- Produces: a job named `e2e` running the `pr-smoke` selector; failure artifact `maestro-debug`.

- [ ] **Step 1: Write the E2E APK build script**

Create `tool/scripts/build_e2e_apk.sh`:

```bash
#!/usr/bin/env bash
# Builds the dev-flavor debug APK in E2E mode: fake auth, /dev launcher, fake
# camera, seeded data. API_BASE_URL uses 10.0.2.2, which is how an Android
# emulator reaches a server listening on the host (see tool/mock_server/README).
set -euo pipefail

flutter build apk --flavor dev --debug \
  --dart-define=E2E=true \
  --dart-define=LOCALE=en \
  --dart-define=API_BASE_URL=http://10.0.2.2:8080

ls -lh build/app/outputs/flutter-apk/app-dev-debug.apk
```

- [ ] **Step 2: Write the Maestro runner script**

Create `tool/scripts/run_maestro.sh`:

```bash
#!/usr/bin/env bash
# Installs the E2E APK on the already-booted emulator and runs one tag
# selector, retrying once. Maestro flakes are usually a missing explicit wait,
# so a single retry distinguishes a flake from a real failure without hiding it.
#
# APP_ID interpolation: see Task 7 Step 1. If Maestro cannot interpolate env
# vars inside `appId`, uncomment the sed fallback below.
set -euo pipefail

TAGS="${1:?usage: run_maestro.sh <tag>}"
APP_ID="${APP_ID:-com.acsl.campaign.dev}"
APK=build/app/outputs/flutter-apk/app-dev-debug.apk

# find .maestro -name '*.yaml' -exec sed -i "s|^appId: com\.acsl\.campaign$|appId: ${APP_ID}|" {} +

adb install -r "$APK"

run() {
  maestro test --env "APP_ID=${APP_ID}" --include-tags "$TAGS" .maestro/
}

if ! run; then
  echo "::warning::Maestro run failed for tag '${TAGS}' - retrying once"
  run
fi
```

- [ ] **Step 3: Make both scripts executable in git**

```bash
chmod +x tool/scripts/build_e2e_apk.sh tool/scripts/run_maestro.sh
git update-index --chmod=+x tool/scripts/build_e2e_apk.sh
git update-index --chmod=+x tool/scripts/run_maestro.sh
```

Without the git-level executable bit, the workflow fails with "Permission denied" on a Linux runner even though the file looks fine on Windows.

- [ ] **Step 4: Add the e2e job**

Append to `.github/workflows/ci.yml`:

```yaml
  e2e:
    name: e2e
    needs: gate
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4

      # Without KVM the emulator falls back to software rendering and the job
      # effectively hangs. This is the single most common cause of emulator CI
      # appearing to "just not work".
      - name: Enable KVM
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' \
            | sudo tee /etc/udev/rules.d/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true

      - name: Resolve dependencies
        run: flutter pub get --enforce-lockfile

      - name: Generate code
        run: |
          flutter gen-l10n
          dart run build_runner build --delete-conflicting-outputs

      # Separate from gate's plain dev APK: this one carries the E2E defines.
      # Building only the E2E variant would mean CI never validates the normal
      # configuration, which is the worse trade.
      - name: Build E2E APK
        run: ./tool/scripts/build_e2e_apk.sh

      - name: Start mock server
        run: |
          cd tool/mock_server
          dart pub get
          # nohup + disown, NOT a bare `&`: the step's shell exits at the end of
          # this step, and a plain background job can be killed with it - which
          # would leave Maestro unable to reach the server two steps later.
          nohup dart run bin/server.dart > "$RUNNER_TEMP/mock-server.log" 2>&1 &
          disown
          cd ../..
          # Poll rather than sleep - a fixed sleep is either flaky or wasteful.
          for i in $(seq 1 30); do
            if curl -sf -o /dev/null http://localhost:8080/campaigns; then
              echo "mock server up after ${i}s"; exit 0
            fi
            sleep 1
          done
          echo "::error::mock server did not become ready within 30s"
          cat "$RUNNER_TEMP/mock-server.log"
          exit 1

      # Prove the server survived the step boundary before spending 10 minutes
      # on an emulator that cannot reach it.
      - name: Confirm mock server still reachable
        run: curl -sf -o /dev/null http://localhost:8080/campaigns

      - name: Install Maestro
        run: |
          curl -fsSL "https://get.maestro.mobile.dev" | bash
          echo "$HOME/.maestro/bin" >> "$GITHUB_PATH"

      - name: Run Maestro (PR smoke)
        uses: reactivecircus/android-emulator-runner@v2
        env:
          APP_ID: com.acsl.campaign.dev
        with:
          api-level: 33
          target: google_apis
          arch: x86_64
          profile: pixel_5
          ram-size: 4096M
          disable-animations: true
          script: ./tool/scripts/run_maestro.sh pr-smoke

      # Maestro's per-step video and screenshots are the only thing that makes
      # a remote emulator failure debuggable.
      - name: Upload Maestro debug output
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: maestro-debug
          path: ~/.maestro/tests/
          retention-days: 7
```

- [ ] **Step 5: Push and iterate to green**

```bash
git add tool/scripts .github/workflows/ci.yml
git commit -m "ci: add emulator Maestro E2E job (PR smoke)

Closes T-0.1.4. Enables KVM, starts the shelf mock server with a polled
health check, builds a separate E2E-defined APK, and runs the pr-smoke tag on
an API 33 google_apis emulator with one retry. Maestro video/screenshots
upload on failure."
git push
gh run watch
```

Expected: iteration required. The likely failures, in rough order of probability: KVM/emulator boot timeout; `adb install` running before the emulator is fully booted; the mock server unreachable at `10.0.2.2` from inside the emulator; Maestro not on PATH inside the `script:` context.

- [ ] **Step 6: Confirm green and record the wall clock**

```bash
gh run list --limit 1
```

Expected: both `gate` and `e2e` succeeded. Note the `e2e` duration — the spec budgets ~30 min, and this number decides whether the nightly full suite in Task 9 needs a longer timeout.

- [ ] **Step 7: Commit fixes**

```bash
git add -A
git commit -m "ci: fix e2e job failures surfaced by the first emulator run"
git push
```

---

## Task 9: Nightly full suite

Completes decision D4's second half: the PR path stays fast while the full Android suite runs on a schedule.

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the working `e2e` job (Task 8) and the `android` tag (Task 7).
- Produces: a `schedule`/`workflow_dispatch` trigger and a tag selector that switches on event type.

- [ ] **Step 1: Add the schedule and manual triggers**

Extend the `on:` block at the top of `.github/workflows/ci.yml`:

```yaml
on:
  pull_request:
  push:
    branches: [main]
  schedule:
    # 19:00 UTC = 01:00 Asia/Dhaka. Nightly, off working hours.
    - cron: '0 19 * * *'
  workflow_dispatch:
```

- [ ] **Step 2: Select the tag by event type**

Replace the `Run Maestro (PR smoke)` step's `script:` line so the selector depends on the trigger, and give scheduled runs room:

```yaml
      - name: Run Maestro
        uses: reactivecircus/android-emulator-runner@v2
        env:
          APP_ID: com.acsl.campaign.dev
          # PRs run the 2-flow smoke; schedule and manual runs take all 7
          # Android flows. campaign_list_smoke is in neither - it is web-only.
          MAESTRO_TAGS: ${{ github.event_name == 'pull_request' && 'pr-smoke' || 'android' }}
        with:
          api-level: 33
          target: google_apis
          arch: x86_64
          profile: pixel_5
          ram-size: 4096M
          disable-animations: true
          script: ./tool/scripts/run_maestro.sh "$MAESTRO_TAGS"
```

Also raise the job timeout for the full suite:

```yaml
    timeout-minutes: 45
```

- [ ] **Step 3: Trigger a full run manually rather than waiting for midnight**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run the full Android Maestro suite nightly

PRs keep the 2-flow smoke; schedule and workflow_dispatch run all 7 android
flows. Timeout raised to 45 min for the full suite."
git push
gh workflow run ci.yml --ref "$(git branch --show-current)"
gh run watch
```

Expected: 7 flows attempted. `field_offline_capture` is the one most likely to fail: `setAirplaneMode` does not always propagate to `connectivity_plus` immediately on emulator images, and `field_offline_capture.yaml:57-59` allows only a 20 s `extendedWaitUntil` for the reconnect drain.

- [ ] **Step 4: If the offline flow fails, diagnose from the video before touching timeouts**

```bash
gh run download --name maestro-debug
```

Watch the recording for the failing step. Only widen the `extendedWaitUntil` timeout in `field_offline_capture.yaml` if the video shows the drain genuinely in progress when the wait expired. If airplane mode never took effect at all, that is a different bug and a longer timeout only hides it.

- [ ] **Step 5: Verify the PR path did not get slower**

Open any small PR (or re-run the last one) and confirm the `e2e` job still runs only 2 flows.

```bash
gh run view --log | grep -c "Running flow"
```

Expected: 2 for a pull_request event. If it is 7, the `MAESTRO_TAGS` conditional is inverted.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "ci: stabilize nightly suite after first full emulator run"
git push
```

- [ ] **Step 7: Final epic verification — walk the six done-criteria**

Run each in order and record the result:

```bash
# 1 - runs on both surfaces
./tool/scripts/run.ps1 -Flavor dev -Device chrome
./tool/scripts/run.ps1 -Flavor dev

# 2 - distinct IDs per flavor
aapt dump badging build/app/outputs/flutter-apk/app-dev-debug.apk | grep package

# 3 - strict analyze
flutter analyze --fatal-infos

# 5 - clean-clone reproducibility
git clone . /tmp/p01-verify && cd /tmp/p01-verify
flutter pub get --enforce-lockfile
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter pub deps --style=list | grep -i riverpod_generator || echo "no riverpod generator - correct"
cd - && rm -rf /tmp/p01-verify

# 6 - one real E2E flow
maestro test --env APP_ID=com.acsl.campaign.dev .maestro/flows/field_online_capture.yaml
```

Criterion 4 was proven in Task 6. If branch protection was blocked by repository plan limits, state that plainly in the epic's closing summary — a partially met criterion reported as met is worse than an honest gap.

---

## Deferred, with owners

Recorded so these read as decisions, not oversights:

| Deferred | Owner |
|---|---|
| Release signing, keystore, distribution | Phase P4 |
| Real ML Kit quality checker (replaces `PassthroughQualityChecker`) | T-2.2.2 |
| Golden test baselines | T-0.2.9 |
| Accessibility automation in CI | Prioritized backlog P0.5.4 |
| iOS platform | Policy — gitignored at `.gitignore:34` |
| `campaign_list_smoke` in automation (web flow; needs mock server restarts) | Follow-up task; see spec §6.3 |
| Drift-on-web assets (`sqlite3.wasm` + worker in `web/`) | Pre-existing gap, `README.md:119-120` |
