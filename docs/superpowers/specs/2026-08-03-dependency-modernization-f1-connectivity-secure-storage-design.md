# Design — Dependency Modernization, Piece F1: `connectivity_plus` 7 + `flutter_secure_storage` 10

**Status:** Approved (design)
**Date:** 2026-08-03
**Origin:** Piece F of the decomposition in [`2026-08-03-dependency-modernization-a-unused-bumps-design.md`](2026-08-03-dependency-modernization-a-unused-bumps-design.md) §1. Piece A's execution reshaped F; see §1 below.
**Toolchain:** Flutter 3.44.8 · Dart 3.12.2 · AGP 9.0.1 · Gradle wrapper 9.1.0 · Kotlin 2.3.20 · minSdk 24 · `analyze --fatal-infos` clean · 37 tests · CI `gate` green and required on `main`

---

## 1. Why piece F split three ways

F was scoped as "native plugins plus the `sqlite3_flutter_libs` EOL question", with piece A's execution suggesting the `android.builtInKotlin` migration as its prerequisite. Investigating that prerequisite showed most of F is blocked on things outside this repo.

**The built-in-Kotlin migration cannot be done on this SDK.** Flutter's migration guide states plainly: *"Enabling built-in Kotlin requires Flutter 3.47 or later."* This project is on 3.44.8, so `android.builtInKotlin=true` is not settable at all.

**Even on 3.47+, it would fail on arrival.** The same guide states that enabling built-in Kotlin while depending on plugins that apply the Kotlin Gradle Plugin causes build failure, and directs app developers to report the issue upstream and wait. Three of this project's plugins apply KGP, confirmed by reading their Android build scripts in the pub cache:

| Plugin (resolved version) | Applies KGP | Has AGP-9 branch |
|---|---|---|
| `camera_android_camerax` 0.6.30 | yes | no |
| `google_mlkit_commons` 0.12.0 | yes | no |
| `workmanager_android` 0.9.0+2 | yes | no |
| `workmanager_android` 0.10.4 | yes | yes |
| `connectivity_plus` 6.1.5 | **no** | no |
| `flutter_secure_storage` 9.2.4 | **no** | no |
| `sqlite3_flutter_libs` 0.5.42 | **no** | no |

**`sqlite3_flutter_libs` is genuinely end-of-life, and its replacement is not an F problem.** Its changelog: *"Deprecate this package. Starting from versions 3.x of the `sqlite3` package, `sqlite3_flutter_libs` is no longer necessary."* But `drift_flutter` 0.2.7 pins both `sqlite3: ^2.4.6` and `sqlite3_flutter_libs: ^0.5.24`, so removing it requires `drift_flutter` 0.3.x — which is the drift bump in piece C. The storage stack is one piece, and that piece is C.

### Resulting split

| | Scope | State |
|---|---|---|
| **F1 (this spec)** | `connectivity_plus` 6→7, `flutter_secure_storage` 9→10 | Doable now — neither applies KGP nor carries an AGP-9 branch |
| **F2** | `android.builtInKotlin` migration, `camera` 0.12, `google_mlkit` follow-ups, `workmanager` 0.10 | **Blocked on upstream.** Trigger condition: Flutter ≥3.47 adopted **and** `camera_android_camerax`, `google_mlkit_commons` and `workmanager_android` have all migrated off KGP. Not a task anyone can pick up before then. |
| **F3** | Drop `sqlite3_flutter_libs`, move to `sqlite3` 3.x | **Reassigned to piece C**, gated on `drift_flutter` 0.3.x |

A Flutter SDK upgrade (3.44.8 → 3.47+) is the gate on F2. It is deliberately out of scope here: it touches the CI pin, `environment.flutter`, and every build, which makes it its own piece of work rather than a step inside a dependency bump.

## 2. Decisions taken

| # | Decision | Rejected alternative |
|---|---|---|
| F1-1 | **Bump both, two commits, ordered `connectivity_plus` then `flutter_secure_storage`.** Separate commits keep a native regression attributable to one revertible change. | One commit. Rejected for the same reason as piece A: bundling forces guesswork about which plugin broke Gradle. |
| F1-2 | **Make the evidence-key hazard visible and testable** as part of the `flutter_secure_storage` commit. It is a direct consequence of that bump, not unrelated work. | Bump and record the hazard in docs only. Rejected: it leaves a silent-data-loss path in code with no signal, and the change is a few lines in a file already being edited. |
| F1-3 | **Keep the existing recovery behaviour** — an unreadable key is still regenerated so capture keeps working. Only its *visibility* changes. | Throw and block capture. Rejected: that is a product decision about field behaviour, not something a dependency bump should decide. |
| F1-4 | **Do not rename the storage key** to `evidence_aes_key_v2`. | Rejected: renaming guarantees abandoning the old key even where v10 can still read it. |
| F1-5 | **Do not route the signal to an audit event.** `lib/core/audit/audit.dart` defines only the `AuditSink` interface and an `AuditAction` enum with no suitable value, and it is not wired into DI. That work is task T-0.3.6 / backlog P0.4.2. | Emit a durable audit event now. Rejected as out of scope: it needs a concrete sink in DI plus a correlation ID. |

## 3. Scope

Every usage of both packages lives in **one file**, `lib/app/di/providers.dart`.

### Commit 1 — `connectivity_plus`

`pubspec.yaml:44`: `connectivity_plus: ^6.0.3` → `^7.3.1`.

Expected to be constraint-only. The changelog documents no API breaks for 7.0.0; the breaking changes it lists are build-tool floors — AGP ≥8.12.1, Gradle wrapper ≥8.13, Kotlin ≥2.2.0 — and this project already exceeds all three (AGP 9.0.1, wrapper 9.1.0, Kotlin 2.3.20). Both call sites already use the List-based API introduced in v6:

- `providers.dart:154-155` — `Connectivity().onConnectivityChanged.map((results) => results.any((r) => r != ConnectivityResult.none))`
- `providers.dart:165-166` — `final results = await Connectivity().checkConnectivity(); return results.any(...)`

If the compile is clean this commit touches only `pubspec.yaml` and `pubspec.lock`.

### Commit 2 — `flutter_secure_storage` and the evidence key

`pubspec.yaml:36`: `flutter_secure_storage: ^9.2.2` → `^10.3.1`, plus the three coupled changes in §4.

## 4. The evidence-key change

### Why it is needed

`flutter_secure_storage` 10.0.0 *"migrated from deprecated Jetpack Crypto library to custom cipher implementation"*, changed its default key and storage ciphers, and made **`ResetOnError` default to true** — meaning a value it cannot decrypt is silently deleted rather than raising.

The value at stake is the AES key for attendance evidence. `mediaEncryptorProvider` (`providers.dart:96`) currently contains, at lines 99-100 and following:

```dart
const key = 'evidence_aes_key_v1';
final existing = await storage.read(key: key);
if (existing != null) return base64Decode(existing);
// ... otherwise generate a fresh 32-byte key and write it
```

"No key yet" and "a key exists but cannot be decrypted" are indistinguishable: both yield `null` and mint a new key. Under v10's cipher change the second case becomes reachable, and when it happens every piece of queued evidence encrypted under the old key becomes permanently undecryptable — with no error, no log, and no user-visible signal. That directly contradicts the architecture's stance that committed capture outcomes are never silently lost.

### The three changes

**(a) Opt out of the silent reset.** `secureStorageProvider` passes Android options with `resetOnError` disabled, carrying a comment naming the consequence. **The exact parameter name must be verified against the installed v10 API before writing it** — it is `aOptions` in v9, and the changelog asserts API stability without enumerating the constructor. Verify, do not assume.

**(b) Extract the loader into a named, testable function.** The key-loading logic moves out of the inline closure inside `mediaEncryptorProvider` into a top-level function taking the storage as a parameter:

```dart
Future<List<int>> loadOrCreateEvidenceKey(FlutterSecureStorage storage)
```

One responsibility, injectable, and testable — which the inline closure was not. `mediaEncryptorProvider` then simply calls it.

**(c) Distinguish the two cases.** Inside that function, a `PlatformException` from `read` is caught separately from the null case and reported with `debugPrint` before regenerating, with a comment stating that evidence under the previous key is now undecryptable. Recovery behaviour is unchanged (see decision F1-3); only its visibility changes.

## 5. Testing

Unlike piece A, **this piece gets real tests**, because these packages are genuinely used. Piece A's "no new tests" rule was a consequence of its packages being unimported and does not carry over.

With the loader extracted, two tests assert real behaviour using a fake `FlutterSecureStorage`:

1. **An unreadable key regenerates rather than crashing** — a fake whose `read` throws `PlatformException` must yield a fresh 32-byte key, and must not propagate the exception.
2. **An existing readable key is reused, not replaced** — a fake holding a stored base64 value must yield exactly those bytes, with no write occurring.

Both assert observable outcomes rather than restating the implementation. Test count rises from 37 to 39.

## 6. Verification

Per commit, in order:

```bash
flutter pub get
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
flutter build web --release
flutter build apk --flavor dev --debug
```

The APK build is mandatory for **both** commits — both packages are native plugins, so both can regress the Android build.

Environment note: this machine's Norton antivirus intercepts TLS and can break Gradle artifact downloads with `SSLHandshakeException`/PKIX errors when a bump pulls previously-uncached Gradle plugin artifacts. The workaround — exporting Norton's root certificate into a **scratch copy** of the JDK's `cacerts` and pointing `JAVA_OPTS`/`GRADLE_OPTS` at it for the build shell only — is documented in the piece A workspace's `task-2-report.md`. It never modifies the real JDK, Android Studio, Norton configuration, or `android/`.

## 7. Risks and stop rules

| Risk | Likelihood | Stop rule |
|---|---|---|
| `connectivity_plus` 7 changed an API the changelog did not document | Low | The compile catches it. Adapt only the two call sites in `providers.dart`; if the change is larger than adapting those, stop and report. |
| The v10 Android-options parameter was renamed | Medium | Verify against the installed API and use the real name. Not a blocker, but do not guess. |
| Either bump demands `minSdk`, `compileSdk`, manifest or Gradle changes | Medium | **Stop and report.** Do not raise `minSdk` — it targets a corporate Android fleet. This is the rule that correctly halted `workmanager` 0.10.x. |
| v10 raises minSdk above 24 | Low | Changelog says 19→23; we are at 24. If Gradle disagrees, the rule above applies. |
| Existing dev-device secure-storage data becomes unreadable | Expected | Accepted. The app is unshipped, unsigned and pre-pilot, so no device holds real evidence. This is the cheapest possible moment to absorb a cipher change. |

**Rollback:** two isolated commits, each one `git revert` away.

## 8. Done criteria

1. `pubspec.yaml` shows `connectivity_plus: ^7.3.1` and `flutter_secure_storage: ^10.3.1`, and `pubspec.lock` resolves both.
2. `flutter pub get --enforce-lockfile` succeeds at **each** commit, not only at the end.
3. `loadOrCreateEvidenceKey` exists as a top-level function, and `secureStorageProvider` disables `resetOnError`.
4. `flutter analyze --fatal-infos` exits 0; `dart format --set-exit-if-changed .` exits 0; `flutter test` passes **39**.
5. `flutter build web --release` and `flutter build apk --flavor dev --debug` both succeed at each commit.
6. No file outside `pubspec.yaml`, `pubspec.lock`, `lib/app/di/providers.dart` and the new test file is modified.
7. `android/` is untouched.
