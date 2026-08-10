# Epic P0.6 — Composition-root integrity and the storage plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the composition root verifiable — the real provider graph exercised by a test, a bootstrap that degrades observably instead of blanking the screen, web persistence that actually works — and set the storage conventions the remaining 32 features will build against.

**Architecture:** Six independent deliverables over `lib/app/di/providers.dart`, `lib/core/storage/app_database.dart`, `lib/main.dart` and `test/support/`. No feature behaviour changes. The one production behaviour change is that the web build starts at all.

**Tech Stack:** Flutter 3.44.8, Drift 2.28.2 + `drift_flutter` 0.2.8, Riverpod (`Provider`/`Notifier`), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-09-epic-p0-6-composition-root-design.md`

## Global Constraints

- **Baseline: 368 passing / 29 skipped.** The 29 are Linux-gated golden tests that skip on Windows. **The skip count must stay exactly 29** — it is the only way a broken golden is noticed locally. Never add a skip, and never skip a test to make it pass.
- **The gate is three commands, and CI enforces all three:** `dart format --output=none --set-exit-if-changed .`, `flutter analyze --fatal-infos`, `flutter test`. Run all three before every commit. P0.5 shipped a red-CI commit by running only two.
- **`analysis_options.yaml`** enforces `strict-casts`, `strict-raw-types`, `always_declare_return_types`, `avoid_dynamic_calls`, `avoid_print` (use `debugPrint`), `directives_ordering`, `prefer_const_constructors`, `prefer_final_locals`, `require_trailing_commas`, `sort_child_properties_last`, `unawaited_futures`, `use_super_parameters`, `prefer_initializing_formals`.
- **Never run `flutter build apk` or `flutter build web` locally.** Norton Antivirus intercepts TLS, so Gradle cannot resolve dependencies and the build fails with PKIX errors unrelated to any code. A local workaround exists (a scratchpad `cacerts` copy with Norton's root imported, passed via `GRADLE_OPTS`) but it is machine-local and must not be committed or relied upon. CI is the authority for builds.
- **Do not redirect test output into a file inside the repo.**
- Generated files (`*.g.dart`, `test/generated/`, `drift_schemas/`) are produced by `build_runner`/`drift_dev` — never hand-edit them.

---

## File Structure

**Created:**

| Path | Responsibility |
|---|---|
| `test/app/di/composition_root_test.dart` | Proves the real graph builds *and that the real database works* |
| `test/app/bootstrap_test.dart` | Proves `bootstrap()` never throws and records what degraded |
| `lib/app/bootstrap.dart` | The pre-frame sequence, extracted from `main()` so it is testable |
| `lib/app/boot_diagnostics.dart` | `BootDiagnostics` value + its provider |
| `test/support/harness.dart` | `buildTestContainer` — one container builder for the whole suite |
| `web/sqlite3.wasm`, `web/drift_worker.js` | Drift's web assets (binary; committed) |
| `web/DRIFT_ASSETS.md` | Which drift version the assets came from, and how to refresh them |
| `docs/architecture/storage-tiers.md` | The storage plan: tiers, table-vs-blob rule, retention owners, roadmap |

**Modified:**

| Path | Change |
|---|---|
| `lib/core/storage/app_database.dart` | `open()` gains the directory seams and passes `web:` |
| `lib/app/di/providers.dart` | `databaseDirectoryProvider`, `tempDirectoryPathProvider`; `appDatabaseProvider` reads them |
| `lib/main.dart` | Reduced to binding + licences + `bootstrap()` + `runApp` |
| `lib/core/audit/audit_emitter.dart` | `flush()` guards its own failures |
| `lib/core/auth/session_manager.dart` | `restore()` wraps the token-store read |
| `lib/core/storage/preference_store.dart` (new) + `locale_store.dart` | Preferences move off the evictable cache table |
| 12 test files | Migrated onto `buildTestContainer` |

---

## Task 1: The database directory seams

The spec's D1 says one seam (`databaseDirectory`). **That is not enough**, and the plan corrects it: the failure actually measured under `flutter_test` was

```
MissingPluginException(No implementation found for method getTemporaryDirectory on channel plugins.flutter.io/path_provider)
```

`drift_flutter`'s `native.dart:66` defaults `tempDirectoryPath` to `getTemporaryDirectory().then((d) => d.path)`, so **both** seams are required or the boot test in Task 3 still throws.

**Files:**
- Modify: `lib/core/storage/app_database.dart:157` (`AppDatabase.open()`)
- Modify: `lib/app/di/providers.dart:137-141` (`appDatabaseProvider`)
- Test: `test/core/storage/database_seam_test.dart` (create)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `AppDatabase.open({Future<Object> Function()? databaseDirectory, Future<String?> Function()? tempDirectoryPath})`
  - `final databaseDirectoryProvider = Provider<Future<Object> Function()?>((ref) => null);`
  - `final tempDirectoryPathProvider = Provider<Future<String?> Function()?>((ref) => null);`

**Exact upstream types — do not guess these:**
- `DriftNativeOptions.databaseDirectory` is `Future<Object> Function()?` (returns a `String` **or** a `Directory`).
- `DriftNativeOptions.tempDirectoryPath` is `Future<String?> Function()?`. Returning `null` leaves sqlite3's temp directory unchanged.

- [ ] **Step 1: Write the failing test**

Create `test/core/storage/database_seam_test.dart`:

```dart
import 'dart:io';

import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the seams default to null, so production behaviour is unchanged', () {
    // If either default were non-null, a test directory could ship to a device.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(databaseDirectoryProvider), isNull);
    expect(container.read(tempDirectoryPathProvider), isNull);
  });

  test('open() honours an injected directory and can be queried', () async {
    // The point of the seam: a REAL AppDatabase.open() - not
    // NativeDatabase.memory() - running open() and the whole v1->v2->v3
    // migration chain against a real file on disk.
    final dir = await Directory.systemTemp.createTemp('acsl_seam_');
    addTearDown(() => dir.delete(recursive: true));

    final db = AppDatabase.open(
      databaseDirectory: () async => dir.path,
      // Required as well: drift_flutter otherwise calls
      // getTemporaryDirectory(), which has no plugin under flutter_test.
      tempDirectoryPath: () async => dir.path,
    );
    addTearDown(db.close);

    final row = await db.customSelect('PRAGMA user_version;').getSingle();
    expect(row.data.values.first, 3);
    expect(File('${dir.path}/acsl_campaign.sqlite').existsSync(), isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/storage/database_seam_test.dart`
Expected: FAIL to compile — `databaseDirectoryProvider` is undefined and `AppDatabase.open` takes no arguments.

- [ ] **Step 3: Add the seams to `AppDatabase.open()`**

In `lib/core/storage/app_database.dart`, replace line 157:

```dart
  AppDatabase.open() : super(driftDatabase(name: 'acsl_campaign'));
```

with:

```dart
  /// Opens the on-device database.
  ///
  /// Both seams default to null, which is exactly today's production behaviour:
  /// drift_flutter then resolves `getApplicationDocumentsDirectory()` and
  /// `getTemporaryDirectory()` from `package:path_provider`. They exist so a
  /// TEST can exercise this real code path — `open()` plus the whole migration
  /// chain — against a temp directory, because neither path_provider call has a
  /// plugin implementation under `flutter_test`.
  ///
  /// `tempDirectoryPath` is not optional-in-practice for tests: drift_flutter
  /// defaults it to `getTemporaryDirectory()`, and that is the call that
  /// actually throws MissingPluginException, so seaming only the database
  /// directory would leave the test broken.
  AppDatabase.open({
    Future<Object> Function()? databaseDirectory,
    Future<String?> Function()? tempDirectoryPath,
  }) : super(
         driftDatabase(
           name: 'acsl_campaign',
           native: DriftNativeOptions(
             databaseDirectory: databaseDirectory,
             tempDirectoryPath: tempDirectoryPath,
           ),
         ),
       );
```

- [ ] **Step 4: Add the two providers and wire them**

In `lib/app/di/providers.dart`, replace `appDatabaseProvider` (lines 137-141) with:

```dart
/// Overridden only by tests, so the real [AppDatabase.open] can run against a
/// temp directory. `null` means "use path_provider", i.e. production.
final databaseDirectoryProvider = Provider<Future<Object> Function()?>(
  (ref) => null,
);

/// Also test-only. drift_flutter defaults this to `getTemporaryDirectory()`,
/// which has no plugin under `flutter_test` — the specific call that throws.
final tempDirectoryPathProvider = Provider<Future<String?> Function()?>(
  (ref) => null,
);

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open(
    databaseDirectory: ref.watch(databaseDirectoryProvider),
    tempDirectoryPath: ref.watch(tempDirectoryPathProvider),
  );
  ref.onDispose(db.close);
  return db;
});
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/core/storage/database_seam_test.dart`
Expected: PASS, 2 tests. If the second still throws `MissingPluginException`, a seam is not reaching `DriftNativeOptions` — check both are passed.

- [ ] **Step 6: Run the full gate**

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

Expected: **370 passing / 29 skipped**. Report the real numbers.

- [ ] **Step 7: Commit**

```bash
git add lib/core/storage/app_database.dart lib/app/di/providers.dart test/core/storage/database_seam_test.dart
git commit -m "feat: seam the database directories so the real open() is testable

AppDatabase.open() took no arguments, so no test could exercise the real
open() plus migration chain - every test used NativeDatabase.memory(). Both
seams default to null, which is byte-identical to today's production path.

tempDirectoryPath is seamed as well as databaseDirectory, and that is not
belt-and-braces: drift_flutter defaults it to getTemporaryDirectory(), which
is the call that actually throws MissingPluginException under flutter_test.
Seaming only the database directory would have shipped a seam that does not
work."
```

---

## Task 2: Web persistence

**Files:**
- Create: `web/sqlite3.wasm`, `web/drift_worker.js`, `web/DRIFT_ASSETS.md`
- Modify: `lib/core/storage/app_database.dart` (`open()` gains `web:`)
- Test: `test/app/web_assets_test.dart` (create)

**Interfaces:**
- Consumes: `AppDatabase.open` from Task 1.
- Produces: an `AppDatabase.open()` that does not throw when compiled for web.

**Why this task exists.** On web, `drift_flutter`'s `connect.dart` exports `web.dart` (`if (dart.library.js_interop)`), whose opener begins:

```dart
if (web == null) {
  throw ArgumentError('When compiling to the web, the `web` parameter needs to be set.');
}
```

`AppDatabase.open()` passes no `web:`, so it throws **synchronously**, and `main.dart:62`'s `container.read(auditFlusherProvider)` resolves the database — so `runApp` is never reached. The error string is present exactly once in `build/web/main.dart.js`, confirming the throwing path ships.

- [ ] **Step 1: Fetch the two assets**

The versions must match the installed `drift`. Check it first:

```bash
grep -E "^  drift:" pubspec.lock -A2
```

Download into `web/`:

```bash
# sqlite3.wasm — from the sqlite3 Dart package's releases
curl -L -o web/sqlite3.wasm \
  https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-2.4.6/sqlite3.wasm
# drift_worker.js — from drift's releases, matching the installed drift version
curl -L -o web/drift_worker.js \
  https://github.com/simolus3/drift/releases/download/drift-2.28.2/drift_worker.js
```

If either URL 404s, the tag naming has changed — find the current release asset at <https://github.com/simolus3/drift/releases> and <https://github.com/simolus3/sqlite3.dart/releases>, and **record the URL you actually used** in `DRIFT_ASSETS.md` and in your report. Do not substitute a different major version.

Sanity-check them (a 404 HTML page is a classic silent failure):

```bash
ls -l web/sqlite3.wasm web/drift_worker.js
head -c 4 web/sqlite3.wasm | od -c   # must start with \0 a s m
head -c 20 web/drift_worker.js       # must be JavaScript, not "<!DOCTYPE"
```

- [ ] **Step 2: Write the failing test**

Create `test/app/web_assets_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Drift on web needs both files served from the web root. They were MISSING
  // for four epics, which is why AppDatabase.open() threw ArgumentError on web
  // and the web build could not start at all - CI's `flutter build web` passes
  // because compiling is not running. This test is cheap and it is the tripwire.
  test('the drift web assets are present and are not error pages', () {
    final wasm = File('web/sqlite3.wasm');
    final worker = File('web/drift_worker.js');

    expect(wasm.existsSync(), isTrue, reason: 'web/sqlite3.wasm is missing');
    expect(worker.existsSync(), isTrue, reason: 'web/drift_worker.js is missing');

    // A wasm module starts with the magic bytes \0asm. A downloaded 404 page
    // would satisfy existsSync() and fail here.
    expect(wasm.readAsBytesSync().take(4).toList(), [0x00, 0x61, 0x73, 0x6d]);
    expect(worker.lengthSync(), greaterThan(1000));
    expect(worker.readAsStringSync(), isNot(startsWith('<')));
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/app/web_assets_test.dart`
Expected: PASS if Step 1 worked. To prove the test is load-bearing, temporarily `mv web/sqlite3.wasm /tmp/` , re-run, confirm it FAILS with "web/sqlite3.wasm is missing", then restore. **Report both outcomes** — a tripwire nobody proved can trip is not a tripwire.

- [ ] **Step 4: Pass `web:` from `open()`**

In `lib/core/storage/app_database.dart`, extend the `super(...)` call from Task 1 to add:

```dart
           web: DriftWebOptions(
             // Relative URIs: both files are served from the web root because
             // they live in `web/`. Without this parameter drift_flutter's web
             // opener throws ArgumentError synchronously, which is why the web
             // build could not start.
             sqlite3Wasm: Uri.parse('sqlite3.wasm'),
             driftWorker: Uri.parse('drift_worker.js'),
           ),
```

`DriftWebOptions({required Uri sqlite3Wasm, required Uri driftWorker, onResult, initializeDatabase})` — the two `Uri`s are the only required parameters.

- [ ] **Step 5: Document the provenance**

Create `web/DRIFT_ASSETS.md`:

```markdown
# Drift web assets

`sqlite3.wasm` and `drift_worker.js` are binary/generated artifacts that Drift
needs to run on web. They are committed rather than fetched at build time so
`flutter run -d chrome` works with no extra setup, which is drift's own
documented approach.

| Asset | Source | Version |
|---|---|---|
| `sqlite3.wasm` | <https://github.com/simolus3/sqlite3.dart/releases> | *(record the tag actually downloaded)* |
| `drift_worker.js` | <https://github.com/simolus3/drift/releases> | *(record the tag actually downloaded)* |

**Refresh them whenever `drift` is upgraded.** `test/app/web_assets_test.dart`
catches deletion or a truncated download; it cannot detect a version mismatch,
so this file is the checkpoint. A mismatch typically shows up as a runtime
failure in the browser, not a build error.
```

Replace the two *(record ...)* cells with the actual tags — leaving them is a plan failure.

- [ ] **Step 6: Run the full gate**

Expected: **371 passing / 29 skipped**.

- [ ] **Step 7: Commit**

```bash
git add web/ lib/core/storage/app_database.dart test/app/web_assets_test.dart
git commit -m "fix: make the web build able to start at all

web/ had no sqlite3.wasm and no drift_worker.js, and AppDatabase.open() passed
no web: argument. drift_flutter's web opener throws ArgumentError
unconditionally without it, and main.dart resolves the database before runApp -
so the web build blanked on load. Web is the primary surface for P1 admin and
P3 CRM. CI's flutter build web passes because compiling is not running, and
nothing in the repo ever ran it.

Also fixes P0.5's locale preference on web, which persists into the same
database."
```

- [ ] **Step 8: Confirm in a real browser — the only check that would have caught this**

Ask the controller to run `flutter build web` in CI (or locally if their Norton workaround is in place), serve `build/web`, and load it. Report what you could and could not verify. **Do not claim web works from a passing Dart test** — no Dart test loads a browser.

---

## Task 3: The composition-root test

**Files:**
- Create: `test/app/di/composition_root_test.dart`

**Interfaces:**
- Consumes: `databaseDirectoryProvider`, `tempDirectoryPathProvider` (Task 1).
- Produces: nothing.

**Read this before writing the test.** Two measured facts shape it:

1. Replacing `appDatabaseProvider` with a `throw` left **all 368 tests passing** — the composition root is exercised by nothing.
2. All 24 core providers **build successfully** with only `appConfigProvider` overridden. So "every provider resolves" passes today with nothing overridden and is **nearly vacuous**; it catches wiring and dependency-cycle breakage only. Riverpod construction is lazy — the database is not opened until first query.

The assertion that carries weight is therefore a **query**, not a resolve.

- [ ] **Step 1: Write the test**

Create `test/app/di/composition_root_test.dart`:

```dart
import 'dart:io';

import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/app/flavors.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('acsl_root_');
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            flavor: Flavor.dev,
            apiBaseUrl: 'https://example.invalid',
            mediaHost: 'https://example.invalid',
          ),
        ),
        // ONLY the two directory seams. Everything else - the database, the
        // secure store, dio, the audit stack, the sync engine - is built for
        // real, which is the entire point of this file.
        databaseDirectoryProvider.overrideWithValue(() async => dir.path),
        tempDirectoryPathProvider.overrideWithValue(() async => dir.path),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await dir.delete(recursive: true);
  });

  test('the real database opens, migrates and answers a query', () async {
    // THE load-bearing assertion. Resolving appDatabaseProvider proves almost
    // nothing (Riverpod construction is lazy and drift defers the open), so this
    // QUERIES it: open() runs, the v1->v2->v3 chain runs, schema v3 is reached.
    final db = container.read(appDatabaseProvider);

    final version = await db.customSelect('PRAGMA user_version;').getSingle();
    expect(version.data.values.first, 3);

    // And the v3 tables are really there, not merely the version number.
    expect(await db.select(db.consentNotices).get(), isEmpty);
    expect(await db.select(db.syncTasks).get(), isEmpty);
  });

  test('every core provider builds against the real graph', () {
    // DELIBERATELY WEAK, and labelled so no future reader mistakes it for
    // coverage: all 24 of these build today with only appConfigProvider
    // overridden, because construction is lazy. It catches a broken dependency
    // or the authService -> dio -> authState -> sessionManager cycle failing to
    // resolve - nothing more. The real guarantee is the query test above.
    final probes = <String, void Function()>{
      'authService': () => container.read(authServiceProvider),
      'tokenStore': () => container.read(tokenStoreProvider),
      'sessionManager': () => container.read(sessionManagerProvider),
      'authState': () => container.read(authStateProvider),
      'dio': () => container.read(dioProvider),
      'campaignRepository': () => container.read(campaignRepositoryProvider),
      'appDatabase': () => container.read(appDatabaseProvider),
      'evidenceStore': () => container.read(evidenceStoreProvider),
      'noticeRepository': () => container.read(noticeRepositoryProvider),
      'secureStore': () => container.read(secureStoreProvider),
      'auditTransport': () => container.read(auditTransportProvider),
      'auditFlusher': () => container.read(auditFlusherProvider),
      'auditSink': () => container.read(auditSinkProvider),
      'evidenceKeyStore': () => container.read(evidenceKeyStoreProvider),
      'mediaEncryptor': () => container.read(mediaEncryptorProvider),
      'faceQualityChecker': () => container.read(faceQualityCheckerProvider),
      'captureSource': () => container.read(captureSourceProvider),
      'syncUploader': () => container.read(syncUploaderProvider),
      'verificationRepository': () =>
          container.read(verificationRepositoryProvider),
      'registrationRepository': () =>
          container.read(registrationRepositoryProvider),
      'sessionRepository': () => container.read(sessionRepositoryProvider),
      'importRepository': () => container.read(importRepositoryProvider),
      'connectivityStream': () => container.read(connectivityStreamProvider),
      'syncEngine': () => container.read(syncEngineProvider),
    };

    final failures = <String>[];
    probes.forEach((name, probe) {
      try {
        probe();
      } catch (error) {
        failures.add('$name: $error');
      }
    });

    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
```

- [ ] **Step 2: Run it**

Run: `flutter test test/app/di/composition_root_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 3: Probe that the query test is load-bearing**

Temporarily break the migration — in `app_database.dart` change `int get schemaVersion => 3;` to `=> 2;` — run the file, confirm the **first** test FAILS on the version assertion, then restore and confirm green. **Report the failure message.** Then confirm the second test still passes with the break in place, which demonstrates in one run why it is labelled weak.

- [ ] **Step 4: Run the full gate**

Expected: **373 passing / 29 skipped**.

- [ ] **Step 5: Commit**

```bash
git add test/app/di/composition_root_test.dart
git commit -m "test: exercise the real composition root, database included

Replacing appDatabaseProvider with a throw left all 368 tests passing: nothing
in the suite ever built the real graph. This overrides ONLY the two directory
seams and then QUERIES the database, so open() and the v1->v2->v3 chain
actually run and schema v3 is asserted on a real file.

The companion 'every provider builds' test is labelled weak on purpose: all 24
build today with only appConfigProvider overridden, because Riverpod
construction is lazy, so it catches dependency-cycle breakage and nothing more."
```

---

## Task 4: Guarded, testable bootstrap

**Files:**
- Create: `lib/app/boot_diagnostics.dart`, `lib/app/bootstrap.dart`, `test/app/bootstrap_test.dart`
- Modify: `lib/main.dart:36-84`, `lib/core/audit/audit_emitter.dart` (`_flushOnce`), `lib/core/auth/session_manager.dart` (`restore`)

**Interfaces:**
- Consumes: providers from `app/di/providers.dart`.
- Produces:
  - `class BootDiagnostics` with `List<BootFailure> get failures`, `bool get isClean`
  - `class BootFailure` with `final String step; final String error;`
  - `final bootDiagnosticsProvider = Provider<BootDiagnostics>(...)`
  - `Future<ProviderContainer> bootstrap({ProviderContainer? container})` — **never throws**

**The rule:** a blank screen is strictly worse than a degraded one — a user who cannot reach the app can neither sign in nor generate audit. So every pre-frame step degrades. But **"guarded" must not mean "silent"**: today `_flushOnce()` has no `try`/`catch` and runs via `unawaited(flush())` from a `Timer.periodic`, so a database failure becomes a recurring unhandled async error and no audit is ever flushed — invisible, continuous. That is the failure mode this task removes, so every degradation is recorded.

- [ ] **Step 1: Write the failing test**

Create `test/app/bootstrap_test.dart`:

```dart
import 'package:acsl_campaign/app/boot_diagnostics.dart';
import 'package:acsl_campaign/app/bootstrap.dart';
import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/app/flavors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_auth.dart';

void main() {
  const config = AppConfig(
    flavor: Flavor.dev,
    apiBaseUrl: 'https://example.invalid',
    mediaHost: 'https://example.invalid',
  );

  test('a clean boot records nothing', () async {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        tokenStoreProvider.overrideWithValue(FakeTokenStore()),
      ],
    );
    addTearDown(container.dispose);

    await bootstrap(container: container);

    expect(container.read(bootDiagnosticsProvider).isClean, isTrue);
  });

  test('a throwing database degrades the boot instead of killing it', () async {
    // This is the WEB case, exactly: AppDatabase.open() threw ArgumentError on
    // web, and main.dart resolved the database before runApp, so nothing
    // rendered. bootstrap() must reach the end regardless.
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        tokenStoreProvider.overrideWithValue(FakeTokenStore()),
        appDatabaseProvider.overrideWith(
          (ref) => throw StateError('database unavailable'),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(bootstrap(container: container), completes);

    // ...and the degradation is VISIBLE. A bare catch would pass the line above
    // while hiding the failure, which is precisely today's audit behaviour.
    final diagnostics = container.read(bootDiagnosticsProvider);
    expect(diagnostics.isClean, isFalse);
    expect(
      diagnostics.failures.map((f) => f.step),
      contains('auditFlusher.start'),
    );
  });

  test('a throwing token store leaves the user signed out, not stuck', () async {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        tokenStoreProvider.overrideWithValue(ThrowingTokenStore()),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(bootstrap(container: container), completes);

    expect(container.read(authStateProvider), isA<AuthSignedOut>());
    expect(
      container.read(bootDiagnosticsProvider).failures.map((f) => f.step),
      contains('sessionManager.restore'),
    );
  });
}
```

Add `ThrowingTokenStore` to `test/support/fake_auth.dart` (its `read()` throws `StateError('storage unavailable')`; `write`/`clear` are no-ops). Read that file first and match its existing style.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/app/bootstrap_test.dart`
Expected: FAIL to compile — `bootstrap.dart` and `boot_diagnostics.dart` do not exist.

- [ ] **Step 3: Write `boot_diagnostics.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One pre-frame step that degraded rather than aborting.
class BootFailure {
  const BootFailure(this.step, this.error);

  /// The step's name, e.g. `'sessionManager.restore'`. Stable enough to assert.
  final String step;

  /// The error, already rendered. No stack trace: this is read for "what came
  /// up degraded", not for debugging.
  final String error;

  @override
  String toString() => '$step: $error';
}

/// What degraded during [bootstrap]. Empty means a clean boot.
///
/// This exists so a guarded boot is OBSERVABLE. Guarding failures with a bare
/// catch is what `AuditFlusher.flush` used to do - silent, recurring, invisible -
/// and it is the failure mode P0.6 removes.
class BootDiagnostics {
  final List<BootFailure> _failures = [];

  List<BootFailure> get failures => List.unmodifiable(_failures);
  bool get isClean => _failures.isEmpty;

  void record(String step, Object error) =>
      _failures.add(BootFailure(step, error.toString()));
}

final bootDiagnosticsProvider = Provider<BootDiagnostics>(
  (ref) => BootDiagnostics(),
);
```

- [ ] **Step 4: Write `bootstrap.dart`**

```dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dev/e2e_seeder.dart';
import '../core/l10n/locale_controller.dart';
import 'boot_diagnostics.dart';
import 'di/providers.dart';

/// Everything that must happen before the first frame.
///
/// NEVER THROWS. A blank screen is strictly worse than a degraded one: a user
/// who cannot reach the app can neither sign in nor generate audit, so every
/// step below degrades and is recorded on [bootDiagnosticsProvider] instead of
/// aborting. Returns the container `runApp` should use.
Future<ProviderContainer> bootstrap({ProviderContainer? container}) async {
  final c = container ?? ProviderContainer();
  final diagnostics = c.read(bootDiagnosticsProvider);
  final config = c.read(appConfigProvider); // pure; cannot fail

  Future<void> step(String name, Future<void> Function() body) async {
    try {
      await body();
    } catch (error) {
      debugPrint('Boot step "$name" degraded: $error');
      diagnostics.record(name, error);
    }
  }

  // E2E-only fixtures. Already best-effort before this refactor: missing
  // fixtures make the Maestro flows fail loudly, which is correct for a test
  // build.
  if (config.e2e) {
    await step(
      'seedE2EData',
      () => seedE2EData(c.read(appDatabaseProvider), seed: config.e2eSeed),
    );
  }

  // Adopt the persisted language before the first frame so a Bengali device
  // does not flash English. LocaleController.load already swallows store
  // failures; the wrapper covers the provider read itself.
  await step(
    'localeController.load',
    () => c.read(localeControllerProvider.notifier).load(),
  );

  // Audit must flush regardless of which screen the user visits. Reading the
  // flusher resolves the database, which is where the web failure landed.
  await step('auditFlusher.start', () async => c.read(auditFlusherProvider).start());

  // Exchange any persisted refresh token before the first frame, so the router
  // sees AuthRestoring rather than AuthSignedOut and does not flash the login
  // screen on a cold start with a valid session. On failure the user simply
  // signs in again - far better than not rendering.
  await step(
    'sessionManager.restore',
    () => c.read(sessionManagerProvider).restore(),
  );

  // E2E signs in for real against FakeAuthService so Maestro drives the same
  // SessionManager path production does.
  if (config.e2e) {
    await step(
      'e2eSignIn',
      () => c.read(sessionManagerProvider).signIn(config.e2eRole, 'e2e'),
    );
  }

  return c;
}
```

- [ ] **Step 5: Reduce `main.dart` to binding + licences + bootstrap + runApp**

Replace `lib/main.dart` lines 36-84 with:

```dart
  final container = await bootstrap();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AcslCampaignApp(),
    ),
  );
}
```

and add `import 'app/bootstrap.dart';` (mind `directives_ordering`). Remove now-unused imports — `flutter analyze --fatal-infos` will name them.

- [ ] **Step 6: Guard `flush()` and `restore()`**

In `lib/core/audit/audit_emitter.dart`, wrap `_flushOnce`'s body so a database failure is caught and logged rather than escaping an `unawaited` call. The timer keeps retrying, which is the existing design — this only stops the unhandled async error:

```dart
  Future<void> _flushOnce() async {
    try {
      // ... existing body unchanged ...
    } catch (error) {
      // Reached when the database is unavailable (web without wasm assets, a
      // locked file). flush() is called via unawaited() from a Timer.periodic,
      // so without this the failure became a recurring UNHANDLED async error
      // and no audit event was ever flushed - silently. The timer retries.
      debugPrint('Audit flush failed ($error). Will retry.');
    }
  }
```

In `lib/core/auth/session_manager.dart`, wrap the token read in `restore()` (line ~211) so an unavailable store degrades to signed-out:

```dart
    final StoredTokens? stored;
    try {
      stored = await _tokens.read();
    } catch (error) {
      // On web SecureStore is localStorage, which can be unavailable. Degrade to
      // signed-out - the user signs in again - rather than throwing out of
      // restore() and, before bootstrap() existed, preventing runApp entirely.
      debugPrint('Token store unreadable ($error). Starting signed out.');
      _emit(const AuthSignedOut());
      return;
    }
```

Use the real type `_tokens.read()` returns — read the file; do not assume `StoredTokens`.

- [ ] **Step 7: Run the tests**

Run: `flutter test test/app/bootstrap_test.dart test/app/e2e_boot_test.dart`
Expected: PASS. `e2e_boot_test.dart` drives the same sequence and must still pass — if it breaks, the extraction changed behaviour.

- [ ] **Step 8: Probe that the guards are load-bearing**

Revert the `restore()` guard, run `bootstrap_test.dart`, confirm the third test FAILS with the escaping `StateError: storage unavailable`, then restore. **Report the message.** A guard nobody proved necessary is decoration.

- [ ] **Step 9: Run the full gate**

Expected: **376 passing / 29 skipped**.

- [ ] **Step 10: Commit**

```bash
git add lib/app/bootstrap.dart lib/app/boot_diagnostics.dart lib/main.dart lib/core/audit/audit_emitter.dart lib/core/auth/session_manager.dart test/app/bootstrap_test.dart test/support/fake_auth.dart
git commit -m "feat: bootstrap() never throws, and says what degraded

main.dart did five container reads before runApp and was covered by no test.
Two could abort startup: restore() did not wrap its token-store read (on web
SecureStore is localStorage), and resolving auditFlusherProvider builds the
database. Either one meant runApp was never reached - a blank screen, from
which a user can neither sign in nor generate audit.

Every step now degrades and is RECORDED on BootDiagnostics. Recording is the
point: guarding with a bare catch is what flush() already did - silent,
recurring, invisible - so the test asserts the recording, not just completion."
```

---

## Task 5: Shared test harness

**Files:**
- Create: `test/support/harness.dart`
- Modify: the 12 test files that hand-roll a `ProviderContainer`

**Interfaces:**
- Consumes: existing fakes in `test/support/`.
- Produces: `ProviderContainer buildTestContainer({Set<Permission>? permissions, AppConfig? config, List<Override> overrides = const []})`

**Why:** `authStateProvider` is currently overridden 13 times across files through **two different mechanisms** (`overrideWith` ×8, `overrideWithValue` ×5). That is how suites drift apart.

- [ ] **Step 1: Find the callers**

```bash
grep -rl "ProviderContainer(" test/
```

Expected: 12 files. List them in your report — the count is a checkpoint.

- [ ] **Step 2: Write the harness**

Create `test/support/harness.dart`:

```dart
import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/app/flavors.dart';
import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/auth/session.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth.dart';

/// One container builder for the whole suite, so a test writes only the
/// overrides it is actually ABOUT.
///
/// The database is deliberately in-memory here: feature tests should not pay
/// for real file I/O. Only `test/app/di/composition_root_test.dart` uses the
/// real one - the harness trades that guarantee for speed on purpose, which is
/// why both exist.
ProviderContainer buildTestContainer({
  Set<Permission>? permissions,
  AppConfig? config,
  List<Override> overrides = const [],
}) {
  final db = AppDatabase(NativeDatabase.memory());

  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        config ??
            const AppConfig(
              flavor: Flavor.dev,
              apiBaseUrl: 'https://example.invalid',
              mediaHost: 'https://example.invalid',
            ),
      ),
      appDatabaseProvider.overrideWithValue(db),
      tokenStoreProvider.overrideWithValue(FakeTokenStore()),
      if (permissions != null)
        authStateProvider.overrideWithValue(_signedIn(permissions)),
      // Caller overrides come LAST so they win over every default above.
      ...overrides,
    ],
  );

  addTearDown(container.dispose);
  addTearDown(db.close);
  return container;
}

AuthState _signedIn(Set<Permission> permissions) => AuthSignedIn(
  Session(
    userId: 'u-1',
    displayName: 'Rina Akter',
    scope: AccessScope(
      roles: const {AppRole.fieldUser},
      permissions: permissions,
      organizationId: 'ORG_1',
    ),
    accessToken: 'a',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  ),
);
```

Check every import path and constructor against the real files before running — `Session`, `AccessScope` and `AppRole` shapes must match `test/app/shell/app_shell_test.dart`'s existing `signedIn` helper, which is the pattern being consolidated.

- [ ] **Step 3: Prove the override precedence**

Add to `test/support/` a small test — `test/support/harness_test.dart`:

```dart
import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('a caller override wins over the harness default', () {
    // If defaults won, a test could silently exercise the wrong dependency -
    // the harness would be actively harmful rather than merely convenient.
    final mine = AppDatabase(NativeDatabase.memory());
    addTearDown(mine.close);

    final c = buildTestContainer(
      overrides: [appDatabaseProvider.overrideWithValue(mine)],
    );

    expect(c.read(appDatabaseProvider), same(mine));
  });
}
```

Run it. Expected: PASS. If it fails, `...overrides` is not last.

- [ ] **Step 4: Migrate the 12 files, one commit each**

For each file: replace the hand-rolled `ProviderContainer(...)` + `addTearDown` with `buildTestContainer(...)`, keeping only the overrides that file genuinely needs. After each file run `flutter test <that file>` and confirm the **same test count as before**. Commit per file, so a regression bisects to one migration.

Do **not** migrate a file whose container deliberately overrides nothing (the composition-root test from Task 3 is the obvious one) — using the harness there would defeat its purpose.

- [ ] **Step 5: Run the full gate**

Expected: **377 passing / 29 skipped** (Task 4's total plus the harness precedence test). Migrations must not change the count — if it moved, a migration dropped or duplicated a test.

- [ ] **Step 6: Final commit for the task**

```bash
git add test/support/harness.dart test/support/harness_test.dart
git commit -m "test: one container builder instead of 12 hand-rolled ones

authStateProvider was overridden 13 times across 12 files through two
different mechanisms. buildTestContainer gives sensible defaults - in-memory
database, fake token store, optional signed-in session - and puts caller
overrides last so they win, which is pinned by its own test.

The database is in-memory here on purpose: feature tests should not pay for
real I/O, and only the composition-root test uses the real one. The harness
trades that guarantee for speed, which is why both exist."
```

---

## Task 6: Storage tiers, and preferences off the evictable cache

**Files:**
- Create: `docs/architecture/storage-tiers.md`, `lib/core/storage/preference_store.dart`
- Modify: `lib/core/storage/app_database.dart` (schema v4 + `preferences` table), `lib/core/l10n/locale_store.dart`, `test/core/l10n/locale_store_test.dart`
- Create: `drift_schemas/drift_schema_v4.json`, `test/generated/schema_v4.dart` (generated)

**Interfaces:**
- Consumes: `AppDatabase`.
- Produces: `Preferences` Drift table (`key` text PK, `value` text); `AppDatabase.schemaVersion == 4`.

**Why:** `cached_reference` holds evictable server caches (`session:<id>:registrations`) **and** a preference that must never be evicted (`pref:locale`). P0.5 mitigated with a key prefix and documented the risk. P0.4.3 and P1.7 both imply a cache sweep, and a convention only a comment enforces will be broken by whoever writes it.

- [ ] **Step 1: Write the migration test first**

Append to `test/core/storage/migration_test.dart`:

```dart
  test('v3 to v4 moves the locale preference and keeps caches', () async {
    // The tier split must not cost a user their language. And a v3 device in
    // the field has a pref:locale row that has to survive.
    final connection = await verifier.schemaAt(3);

    final oldDb = v3.DatabaseAtV3(connection.newConnection());
    await oldDb.into(oldDb.cachedReferences).insert(
      v3.CachedReferencesData(
        key: 'pref:locale',
        valueJson: '{"languageCode":"bn"}',
        fetchedAt: DateTime.utc(2026, 8, 9),
      ),
    );
    await oldDb.into(oldDb.cachedReferences).insert(
      v3.CachedReferencesData(
        key: 'session:S1:registrations',
        valueJson: '[]',
        fetchedAt: DateTime.utc(2026, 8, 9),
      ),
    );
    await oldDb.close();

    final db = AppDatabase(connection.newConnection());
    await verifier.migrateAndValidate(db, 4);

    // The preference moved to its own table...
    final prefs = await db.select(db.preferences).get();
    expect(prefs.map((p) => p.key), contains('pref:locale'));

    // ...and the server cache stayed where it belongs.
    final cached = await db.select(db.cachedReferences).get();
    expect(cached.map((r) => r.key), contains('session:S1:registrations'));
    expect(cached.map((r) => r.key), isNot(contains('pref:locale')));

    await db.close();
  });
```

Add `import '../../generated/schema_v3.dart' as v3;`. **Warning from P0.5:** the generated v3 file's data-class names must match what `drift_dev schema generate --data-classes --companions` emits — read `schema_v3.dart` and use its real names rather than guessing `CachedReferencesData`.

Also append a sweep test:

```dart
  test('a cache sweep cannot delete preferences', () async {
    // The whole point of the split. Before it, a sweep over cached_reference
    // would have taken pref:locale with it.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.preferences).insert(
      PreferencesCompanion.insert(key: 'pref:locale', value: 'bn'),
    );
    await db.into(db.cachedReferences).insert(
      CachedReferencesCompanion.insert(
        key: 'session:S1:registrations',
        valueJson: '[]',
        fetchedAt: DateTime.utc(2026, 8, 9),
      ),
    );

    await db.delete(db.cachedReferences).go(); // the sweep

    expect(await db.select(db.cachedReferences).get(), isEmpty);
    expect(await db.select(db.preferences).get(), hasLength(1));
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/storage/migration_test.dart`
Expected: FAIL — `db.preferences` is undefined, `schema_v4` does not exist.

- [ ] **Step 3: Add the table and bump the schema**

In `lib/core/storage/app_database.dart`:

```dart
/// Device-scoped user preferences.
///
/// A SEPARATE table from `cached_reference` on purpose. That table is an
/// evictable cache of server-derived reads, and P0.4.3 (clear protected cached
/// media per policy) and P1.7 (retention execution) both imply a sweep over it.
/// P0.5 kept the locale preference there behind a `pref:` key prefix, which only
/// a comment enforced - so the first sweep would have deleted the user's
/// language. Preferences are NEVER evicted; see docs/architecture/storage-tiers.md.
class Preferences extends Table {
  TextColumn get key => text()(); // 'pref:locale'
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
```

Register `Preferences` in `@DriftDatabase(tables: [...])`, bump `schemaVersion` to `4`, and add the migration step:

```dart
        from3To4: (m, schema) async {
          await m.createTable(schema.preferences);
          // Carry existing preferences across. A v3 device in the field has a
          // pref:locale row; losing it would silently reset the language.
          await m.database.customStatement(
            "INSERT INTO preferences (key, value) "
            "SELECT key, value_json FROM cached_reference "
            "WHERE key LIKE 'pref:%'",
          );
          await m.database.customStatement(
            "DELETE FROM cached_reference WHERE key LIKE 'pref:%'",
          );
        },
```

Verify the real SQL table/column names from the generated code before running (`cached_reference` / `value_json` follow Drift's snake_case default, but confirm).

- [ ] **Step 4: Regenerate, in this proven order**

The plan's order matters — P0.5 established it, and the reverse fails:

```bash
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
dart run drift_dev schema dump lib/core/storage/app_database.dart drift_schemas/
dart run drift_dev schema steps drift_schemas/ lib/core/storage/schema_versions.dart
dart run build_runner build --delete-conflicting-outputs
dart run drift_dev schema generate --data-classes --companions drift_schemas/ test/generated/
```

Add `from3To4:` to `onUpgrade` only **after** `schema steps` has regenerated (the named argument does not exist until then). `--data-classes --companions` are **required**: without them, `schema generate` silently rewrites the committed `schema_v1/v2/v3.dart` files and strips their data classes.

- [ ] **Step 5: Move `LocaleStore` onto the new table**

Rewrite `lib/core/l10n/locale_store.dart`'s `DriftLocaleStore` to read/write `db.preferences` instead of `db.cachedReferences`, storing the bare language code in `value` rather than a JSON blob (`localePrefKey` stays `'pref:locale'` — renaming it would abandon the stored preference on every device). Keep every existing behaviour: unset → `null`, unsupported code → `null`, nothing throws out of `read()`. Update `test/core/l10n/locale_store_test.dart` accordingly; its 8 tests must all still pass, including the corrupt-value and unsupported-code cases.

- [ ] **Step 6: Write the storage plan doc**

Create `docs/architecture/storage-tiers.md` containing, verbatim from the spec's D-F: the five-tier table (durable outbound / evidence / evictable cache / preference / secret) with eviction, encryption and platform columns; the **rule** that a thing earns its own table when it is *searched, sorted or counted*, or has more than one access pattern; and the forward-flagged table listing each coming table against the feature that will build it. Include the note that **F8 — the roster stored as one JSON blob and filtered in Dart — is a required P0.14 fix**, citing the PRD line it violates ("return local search results quickly under offline field conditions").

- [ ] **Step 7: Probe the migration is load-bearing**

Drop the `INSERT INTO preferences ... SELECT` statement, run `migration_test.dart`, confirm the v3→v4 test FAILS because `pref:locale` is absent, then restore. **Report the message.** P0.5 established that `migrateAndValidate` compares *shapes only* and passes a migration that drops every row — so only the data assertion catches this.

- [ ] **Step 8: Run the full gate**

Expected: **379 passing / 29 skipped**.

- [ ] **Step 9: Commit**

```bash
git add lib/core/storage/ lib/core/l10n/locale_store.dart drift_schemas/ test/generated/ test/core/storage/migration_test.dart test/core/l10n/locale_store_test.dart docs/architecture/storage-tiers.md
git commit -m "feat: split preferences off the evictable cache as schema v4

cached_reference held both evictable server caches and a preference that must
never be evicted. P0.5 mitigated with a pref: key prefix that only a comment
enforced, and P0.4.3 and P1.7 both imply a sweep over that table - so the first
sweep would have deleted the user's language.

Preferences get their own table, with the migration carrying existing rows
across (a v3 device in the field has one). A sweep test asserts the split
holds, and the migration test asserts the row survives - necessary because
migrateAndValidate compares shapes only and will pass a migration that drops
every row.

docs/architecture/storage-tiers.md records the five tiers, the rule that a
thing earns a table when it is searched/sorted/counted, and the tables the
remaining PRDs imply - each assigned to the feature that will build it rather
than built speculatively here."
```

---

## Self-Review

**Spec coverage.** D1 → Task 1 (with the `tempDirectoryPath` correction). D2 → Task 2. D3, D4 → Task 4. D5 → Task 5. D6 → Task 6. D7 (web authoring drafts stay server-side) is a *decision to not build*, correctly absent. Deliverables D-A…D-F all map to a task. §5's test table: composition root → Task 3; bootstrap resilience → Task 4; web assets → Task 2; `restore()`/`flush()` guards → Task 4; seam default → Task 1; tier split → Task 6. All covered.

**Corrections to the spec, made deliberately:**
1. **`databaseDirectory` is `Future<Object> Function()?`**, not `Future<Directory> Function()?`.
2. **`tempDirectoryPath` must be seamed too** — the measured failure was `getTemporaryDirectory`, so the spec's single seam would not have worked. This is the most important correction in the plan.
3. Baseline is **368**, not the spec's 367.

**Placeholder scan:** the only intentional blanks are the two version cells in `DRIFT_ASSETS.md`, which Step 5 of Task 2 explicitly requires filling with the tags actually downloaded.

**Type consistency:** `BootDiagnostics.record(String, Object)` / `failures` / `isClean` and `BootFailure.step`/`.error` are used identically in Task 4's test and implementation. `buildTestContainer`'s signature matches its use in Task 5. `localePrefKey` stays `'pref:locale'` across Task 6.

**Running totals** (368 → 370 → 371 → 373 → 376 → 377 → 379) assume no test is removed. Report the real number at each gate; a mismatch means something was dropped.
