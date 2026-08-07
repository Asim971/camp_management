# Design — Dependency Modernization, Piece A: bump the unused dependencies

**Status:** Approved (design)
**Date:** 2026-08-03
**Origin:** Follow-up item 1 of [`../plans/2026-07-30-epic-p0-1-outcome.md`](../plans/2026-07-30-epic-p0-1-outcome.md) §3 — dependency modernization was not in any backlog item.
**Toolchain:** Flutter 3.44.8 · Dart 3.12.2 · `analyze --fatal-infos` clean · 37 tests · CI `gate` required on `main`

---

## 1. Why this is one piece of six, not the whole job

The original request was "bring the stale Dart-only majors current": `go_router` 14→17, `flutter_riverpod` 2→3, `freezed` 2→3, `fl_chart` 0.68→1.2, `drift` 2.28→2.34, `flutter_lints` 4→6, `csv` 6→8. Measuring first changed the shape of it in two ways.

**Two of the seven are declared but never imported.** Verified across `lib`, `test` and `tool`: zero imports and zero symbol usage for `fl_chart` and `csv`. Analytics (A-02) is still a placeholder, and bulk import ships bytes to the server rather than parsing CSV client-side. The same is true of two dependencies the request did not mention — `google_mlkit_face_detection` (T-2.2.2 unbuilt) and `workmanager` (T-2.1.3 unbuilt).

**The request omitted the riskier half.** The native plugins are equally stale — `camera` 0.11→0.12, `connectivity_plus` 6→7, `flutter_secure_storage` 9→10 — and Epic P0.1 demonstrated that native plugin changes are where the pain lives (a removed v1 embedding, an AGP-9 Kotlin plugin gate). One needs investigation rather than a bump: **`sqlite3_flutter_libs`'s latest published version is `0.6.0+eol`**, an end-of-life marker in the version string, on the package providing the SQLite binaries behind the offline Drift database. pub.dev's `isDiscontinued` flag is not set, so the signal is soft, but it warrants its own look.

Measured blast radius of the real migrations: `flutter_riverpod` **26 files**, `go_router` **7** (including the RBAC redirect guards), `drift` **5**, `freezed` **8** generated files.

### Agreed decomposition

| Piece | Contents | Character |
|---|---|---|
| **A (this spec)** | `fl_chart`, `csv`, `google_mlkit_face_detection`, `workmanager` | No code changes; unused packages |
| B | `flutter_lints` 4→6 | New rules against a repo just brought to zero issues |
| C | `freezed` 2→3, `json_serializable`, `build_runner`, `drift` 2.28→2.34 | Codegen cluster; interact via `build_runner`, must move together |
| D | `go_router` 14→17 | 7 files; touches RBAC route guards, so security-relevant |
| E | `flutter_riverpod` 2→3 | 26 files; the dominant piece |
| F | Native plugins + the `sqlite3_flutter_libs` EOL question | Android build risk; investigation before bumping |

Each piece gets its own spec → plan → execution cycle. **A is first** because it reduces seven migrations to three with no code change, and because it is the cheapest way to confirm the toolchain accepts current majors at all.

## 2. Decisions taken

| # | Decision | Rejected alternative |
|---|---|---|
| A1 | **Bump all four, including the two native ones.** The CI `gate` already builds `app-dev-debug.apk`, so a native regression cannot merge silently — the mechanism that would catch it in piece F runs on every push already. | Split: bump the pure-Dart pair now, defer the native pair to piece F. Rejected — it buys caution already paid for, and F will be dominated by the EOL investigation, a different class of problem. |
| A2 | **Keep all four; do not remove them.** `PRIORITIZED_TASK_BREAKDOWN.md` P0.15 requires replacing `PassthroughQualityChecker` with real face-count/blur/light checks (ML Kit) and P0.16 requires background resume for durable sync (workmanager). Both sit in the P0 band, Iteration 2. | Remove the unused four per YAGNI and re-add at the then-current version. Rejected as near-term churn: two of the four are needed within the next iteration. |
| A3 | **Three commits, not one.** The gate runs per push, not per commit, so isolating each native bump makes a red APK build attributable and revertible without surgery. | One commit for all four. Rejected — bundling forces guesswork about which plugin broke Gradle, the exact guessing that cost hours in P0.1. |

## 3. Scope

Four one-line edits to `pubspec.yaml`, preserving the existing comment grouping:

| Line | From | To | Nature |
|---|---|---|---|
| 40 | `google_mlkit_face_detection: ^0.11.0` | `^0.14.0` | native plugin |
| 45 | `workmanager: ^0.9.0` | `^0.10.5` | native plugin |
| 55 | `fl_chart: ^0.68.0` | `^1.2.0` | pure Dart |
| 59 | `csv: ^6.0.0` | `^8.0.0` | pure Dart |

All four are toolchain-compatible; the highest requirement is `workmanager` 0.10.5's Flutter ≥3.38.0.

`pubspec.lock` is regenerated and committed **in the same commit as the pubspec change that caused it** — so with three commits, the lockfile is updated three times, once per commit. This is not stylistic: the gate runs `flutter pub get --enforce-lockfile`, so a lockfile lagging its pubspec fails the build immediately, and it must therefore hold true at *every* commit, not just at the end of the sequence.

### Commit structure

1. `fl_chart` + `csv` — the pure-Dart pair, zero risk
2. `google_mlkit_face_detection` — native
3. `workmanager` — native, major bump, previously broke this build

### Explicitly not in scope

- **No code changes.** Nothing imports these packages, so there is nothing to migrate.
- **No documentation changes.** Verified by grep across `ARCHITECTURE_Flutter.md`, `TASK_BREAKDOWN.md` and `README.md`: every reference to these four packages names the package without a version constraint (the architecture package tables, the offline key-packages paragraph, and the T-1.6.1 / T-2.1.3 / T-3.3.1 task rows). Nothing to update. This is the only piece of this epic with no doc surface.
- **No test changes.** See §5.
- **No `minSdk`, `compileSdk`, manifest or Gradle changes.** If a bump demands one, that is an escalation (§6), not part of this piece.

## 4. Verification

In order:

```bash
flutter pub get
flutter pub get --enforce-lockfile        # proves the committed lockfile is self-consistent
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos             # must exit 0
flutter test                              # 37 passing
flutter build web --release
flutter build apk --flavor dev --debug    # the only step that can catch a native regression
```

The APK build is slow and is not optional here — it is the entire reason this piece is considered to carry any risk at all. After the local chain passes, the push exercises the same APK build in CI on a clean Linux checkout.

## 5. Testing

**No new tests, deliberately.** All four packages are unused; a test asserting anything about them would assert nothing real. The build succeeding is the verification. Stating this explicitly is preferable to inventing coverage that would pass regardless of whether the bump worked.

## 6. Risks and stop rules

| Risk | Likelihood | Stop rule |
|---|---|---|
| **ML Kit 0.14 raises its Android minSdk above 24.** `android/app/build.gradle.kts:25-26` pins `minSdk = 24` with a comment citing the older 21 floor. | Medium | **Stop and surface it.** The minSdk targets a corporate Android fleet; raising it is a product decision, not a number to adjust quietly. |
| **`workmanager` 0.10 changed its Android setup.** 0.9→0.10 is a major bump. Nothing imports it, so only the build matters, not the API — but it may want manifest entries or Gradle changes. | Medium | **Stop and surface it.** Absorbing this class of creep is what turned P0.1's Task 1 into four rounds. |
| A pure-Dart bump breaks the build. | Very low | Unused and tree-shaken; if it happens, revert commit 1 and investigate separately. |

**Rollback:** three isolated commits, each one `git revert` away.

## 7. Done criteria

1. `pubspec.yaml` shows all four target constraints, and `pubspec.lock` resolves them.
2. `flutter pub get --enforce-lockfile` succeeds from a clean state.
3. `flutter analyze --fatal-infos` exits 0; `flutter test` passes 37; `dart format --set-exit-if-changed .` exits 0.
4. `flutter build web --release` and `flutter build apk --flavor dev --debug` both succeed locally.
5. The CI `gate` job is green on the pushed branch, with the APK artifact present.
6. No file outside `pubspec.yaml` and `pubspec.lock` is modified.
