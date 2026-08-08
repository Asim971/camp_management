# Epic P0.5 Localization & Versioned Consent Notice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make localization actually function — register the delegates, add per-device locale selection, and give every status enum a typed localized label — then build a versioned consent-notice model that proves what a carpenter was shown, and gate the epic on a green emulator E2E suite.

**Architecture:** `AppL10n`'s generated delegates get registered (they never were), and `LocaleController` drives `MaterialApp.router`'s `locale:` from a Drift-persisted per-device preference. Five typed `label(AppL10n)` extensions replace `status.dart`'s broken string-key seam, so a new status value becomes a compile error. `NoticeRepository` resolves a consent notice from the newest cached version or a bundled floor — never awaiting the network — and the record persisted with each capture carries a length-prefixed SHA-256 hash so it proves the text rather than pointing at it.

**Tech Stack:** Flutter 3.44.8 (web + Android), Dart 3 with `strict-casts`/`strict-raw-types`, `flutter_localizations` + `gen-l10n`, Drift 2.28.2, Riverpod, `cryptography` 2.9.0 (SHA-256), Maestro (CI only), GitHub Actions.

**Spec:** [`docs/superpowers/specs/2026-08-07-epic-p0-5-localization-consent-design.md`](../specs/2026-08-07-epic-p0-5-localization-consent-design.md)

## Global Constraints

- **Branch:** create a fresh branch off `origin/main` (P0.4 merged as `e5edd57`). Do **not** work on `feat/epic-p0-4-auth-rbac-routing` — it is merged and its PR is closed.
- **Lints are strict and CI-enforced.** `analysis_options.yaml` sets `strict-casts: true`, `strict-raw-types: true`, and enables `always_declare_return_types`, `avoid_dynamic_calls`, `avoid_print`, `directives_ordering`, `prefer_const_constructors`, `prefer_final_locals`, `require_trailing_commas`, `sort_child_properties_last`, `unawaited_futures`, `use_super_parameters`. `prefer_initializing_formals` is inherited from `flutter_lints` and **does** fire. `debugPrint` only, never `print` (`tool/**` is excluded from analysis).
- **`directives_ordering`:** `dart:` then `package:` then relative, each group alphabetical.
- **Generated code is gitignored.** `lib/l10n/generated/**` and `*.g.dart` are produced by `flutter gen-l10n` and `build_runner`. Run them after touching ARB files or Drift tables; never hand-edit the output.
- **Verification gates (every task):** `dart format --set-exit-if-changed .`, `flutter analyze --fatal-infos` (exit 0), `flutter test`. The final task adds `flutter build web`.
- **Do NOT run `flutter build apk`.** It fails in this sandbox with 61 TLS/PKIX errors fetching `io.flutter:*` artifacts — debug *and* release — independent of any code change. CI runs it.
- **Test baseline:** **256 passing / 29 skipped** locally at `e5edd57`. The 29 skips are Linux-gated goldens (`test/golden/`) and must stay at exactly 29; CI's total is 285.
- **ARB target: 45 keys in each file** (26 existing + 19 new). `en` and `bn` must always have identical key sets.
- **The existing 26 Bengali values are genuine human-authored translations** (`ক্যাম্পেইন ব্যবস্থাপনা`, `খসড়া`). The 19 new ones are machine drafts and must be marked as such per spec D6 — do not let them be mistaken for reviewed text.
- **The hash pre-image format is a contract.** Length-prefixed, fixed field order. Changing it invalidates every stored `contentHash`.
- **The epic does not close until CI's `e2e` job is green** (spec §7.1). It cannot be verified locally — Maestro is not installed and no APK can be built here. **Never claim E2E passes from a local run.**

---

## File Structure

**Created:**

| Path | Responsibility |
|---|---|
| `test/l10n/arb_parity_test.dart` | Asserts `en`/`bn` key-set identity and the 45-key count |
| `lib/domain/common/status_labels.dart` | Five typed `label(AppL10n)` extensions |
| `test/domain/status_labels_test.dart` | All 34 enum values resolve in both locales |
| `test/l10n/l10n_render_test.dart` | The chain-closing test: Bengali actually renders |
| `lib/core/l10n/locale_store.dart` | `LocaleStore` + Drift impl over `cached_reference` |
| `test/core/l10n/locale_store_test.dart` | Round-trip, unset, corrupt value |
| `lib/core/l10n/locale_controller.dart` | `Notifier<Locale?>`; `null` == follow system |
| `test/core/l10n/locale_controller_test.dart` | System default, persistence, survives sign-out |
| `lib/features/settings/presentation/language_screen.dart` | Language picker |
| `test/widget/language_screen_test.dart` | Selection persists and applies |
| `lib/core/consent/notice.dart` | `ConsentNotice`, `ConsentRecord`, `consentContentHash` |
| `test/core/consent/notice_hash_test.dart` | Pinned digest + injectivity |
| `lib/core/consent/notice_repository.dart` | Resolution, bundled loader, `DioNoticeSource` (🔒) |
| `test/core/consent/notice_repository_test.dart` | Newest-wins, floor fallback, never awaits network |
| `assets/consent/notice_v1.json` | The bundled floor, both languages |
| `.maestro/flows/locale_bengali.yaml` | E2E: launch with `LOCALE: bn`, assert Bengali renders |

**Modified:**

| Path | Change |
|---|---|
| `lib/app/app.dart` | Register `AppL10n.localizationsDelegates` / `supportedLocales`; drive `locale:` |
| `lib/domain/common/status.dart` | Delete the five `l10nKey` getters |
| `lib/l10n/app_en.arb`, `app_bn.arb` | +19 keys each |
| `lib/core/storage/app_database.dart` | Schema **v3**: `consent_notices` table + 4 columns on `attendance_drafts` |
| `lib/features/camera_capture/application/capture_controller.dart` | Resolve the notice; record the consent on submit |
| `lib/app/di/providers.dart` | `localeStoreProvider`, `localeControllerProvider`, `noticeRepositoryProvider` |
| `lib/app/flavors.dart` | `AppConfig.locale` from the `LOCALE` dart-define |
| `lib/app/shell/app_shell.dart` | Language entry in the account menu |
| `lib/app/router/route_table.dart`, `app_router.dart` | Register `/settings/language` |
| `pubspec.yaml` | Bundle `assets/consent/` |
| `.github/workflows/ci.yml` | New `e2e` job |
| `TASK_BREAKDOWN.md` | Close the epic; correct T-0.1.4's "cancelled, not deferred" |

**Verified API surface this plan builds on:**

- `AppL10n` (`lib/l10n/generated/app_localizations.dart`) exposes `static AppL10n of(BuildContext)`, `static const localizationsDelegates`, `static const supportedLocales`. `l10n.yaml` sets `output-class: AppL10n`, `nullable-getter: false`, `synthetic-package: false`.
- `CachedReferences` table: `key` (text, PK), `valueJson` (text), `fetchedAt` (dateTime).
- `AttendanceDraftsCompanion.insert(...)` is called in `capture_controller.submit()`.
- `CaptureState` has `step`, `noticeLanguage`, `quality`, `submitting`, `error`, `attendanceId`; `acceptNotice(String language)` is **synchronous** and sets `step: positioning`.
- `AppConfig.fromEnvironment()` reads `FLAVOR`, `API_BASE_URL`, `MEDIA_HOST`, `E2E`, `ROLE`, `QUALITY`, `SEED` — **not** `LOCALE`.
- Android `applicationId` is `com.acsl.campaign` with `.dev` suffix for the dev flavor → **`com.acsl.campaign.dev`**.

**A design gap in the spec this plan closes (flagged, not silently patched):** the spec says `acceptNotice` records the consent, but `acceptNotice` is **synchronous** and fires at the notice step, while the DB insert happens later in `submit()`. Resolving a notice is async I/O. So Task 10 resolves the notice when the controller builds, holds both the resolved `ConsentNotice` (to render) and the accepted `ConsentRecord` (to persist) in `CaptureState`, and `submit()` writes the record. Spec §4.5 under-specified this; the shape is set out in Task 10's Interfaces block.

---

## Task 1: ARB parity test and the 19 missing keys

**Files:**
- Create: `test/l10n/arb_parity_test.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb`

**Interfaces:**
- Consumes: nothing.
- Produces: 19 new ARB keys — `registrationStatus_{invited,registered,pendingProfileSync,ineligible,waitlisted,cancelled}`, `importStatus_{dryRun,readyToCommit,processing,completed,partiallyCompleted,failed,cancelled}`, `integrityFlag_{noReference,poorQuality,suspectedSpoof,duplicate,geofenceException,manualOverride}`. After `flutter gen-l10n`, `AppL10n` exposes a getter per key.

- [ ] **Step 1: Write the failing test**

Create `test/l10n/arb_parity_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reads an ARB file and returns only its translatable keys — `@@locale` and
/// the `@key` metadata blocks are not strings the user ever sees.
Set<String> _translatableKeys(String path) {
  final json = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  return json.keys.where((k) => !k.startsWith('@')).toSet();
}

void main() {
  const en = 'lib/l10n/app_en.arb';
  const bn = 'lib/l10n/app_bn.arb';

  test('en and bn have identical key sets', () {
    // This assertion PASSES today (both files hold the same 26 keys). It is
    // here to stop future drift, not to detect current drift — which is
    // exactly the failure that let three status families go missing while
    // status.dart advertised l10nKey getters for them.
    final enKeys = _translatableKeys(en);
    final bnKeys = _translatableKeys(bn);

    expect(
      enKeys.difference(bnKeys),
      isEmpty,
      reason: 'keys present in en but missing from bn',
    );
    expect(
      bnKeys.difference(enKeys),
      isEmpty,
      reason: 'keys present in bn but missing from en',
    );
  });

  test('both files hold all 45 expected keys', () {
    // 26 pre-existing + 19 added by this task. This is the assertion that
    // goes red before the keys land and green after.
    expect(_translatableKeys(en), hasLength(45));
    expect(_translatableKeys(bn), hasLength(45));
  });

  test('every status family the enums advertise has a full set of keys', () {
    // status.dart previously exposed l10nKey getters for five families while
    // the ARB carried only two. Pinning the per-family counts means adding an
    // enum value without its key fails here, not silently at runtime.
    final keys = _translatableKeys(en);
    int countPrefixed(String prefix) =>
        keys.where((k) => k.startsWith(prefix)).length;

    expect(countPrefixed('campaignStatus_'), 8);
    expect(countPrefixed('registrationStatus_'), 6);
    expect(countPrefixed('attendanceStatus_'), 7);
    expect(countPrefixed('importStatus_'), 7);
    expect(countPrefixed('integrityFlag_'), 6);
  });

  test('new machine-drafted bn values are marked unreviewed', () {
    // The 26 pre-existing bn values are genuine human translations. The 19
    // added here are machine drafts, and an unmarked draft is worse than an
    // obviously provisional one because it invites nobody to check it.
    final bnJson =
        jsonDecode(File(bn).readAsStringSync()) as Map<String, Object?>;
    const newKeys = [
      'registrationStatus_invited',
      'importStatus_dryRun',
      'integrityFlag_noReference',
    ];
    for (final key in newKeys) {
      final meta = bnJson['@$key'];
      expect(
        meta,
        isA<Map<String, Object?>>(),
        reason: '$key must carry @-metadata marking it unreviewed',
      );
      expect(
        (meta! as Map<String, Object?>)['description'],
        contains('UNREVIEWED'),
        reason: '$key metadata must say UNREVIEWED',
      );
    }
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/l10n/arb_parity_test.dart`

Expected: the *identity* test PASSES (both files already hold 26 identical keys). The 45-count test FAILS with `Expected: an object with length of <45> Actual: <26>`, the per-family test FAILS on `registrationStatus_`, and the metadata test FAILS. That split is expected and correct — see the Global Constraints note.

- [ ] **Step 3: Add the 19 English keys**

In `lib/l10n/app_en.arb`, after the `attendanceStatus_*` block:

```json
  "registrationStatus_invited": "Invited",
  "registrationStatus_registered": "Registered",
  "registrationStatus_pendingProfileSync": "Pending profile sync",
  "registrationStatus_ineligible": "Ineligible",
  "registrationStatus_waitlisted": "Waitlisted",
  "registrationStatus_cancelled": "Cancelled",

  "importStatus_dryRun": "Dry run",
  "importStatus_readyToCommit": "Ready to commit",
  "importStatus_processing": "Processing",
  "importStatus_completed": "Completed",
  "importStatus_partiallyCompleted": "Partially completed",
  "importStatus_failed": "Failed",
  "importStatus_cancelled": "Cancelled",

  "integrityFlag_noReference": "No reference photo",
  "integrityFlag_poorQuality": "Poor image quality",
  "integrityFlag_suspectedSpoof": "Suspected spoof",
  "integrityFlag_duplicate": "Duplicate",
  "integrityFlag_geofenceException": "Outside venue geofence",
  "integrityFlag_manualOverride": "Manual override",
```

- [ ] **Step 4: Add the 19 Bengali keys, each marked unreviewed**

In `lib/l10n/app_bn.arb`, mirroring the same order. **Every one carries `@`-metadata marking it a machine draft** — the existing 26 values are genuine translations and these must not be mistaken for them:

```json
  "registrationStatus_invited": "আমন্ত্রিত",
  "@registrationStatus_invited": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
  "registrationStatus_registered": "নিবন্ধিত",
  "@registrationStatus_registered": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
  "registrationStatus_pendingProfileSync": "প্রোফাইল সিঙ্কের অপেক্ষায়",
  "@registrationStatus_pendingProfileSync": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
  "registrationStatus_ineligible": "অযোগ্য",
  "@registrationStatus_ineligible": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
  "registrationStatus_waitlisted": "অপেক্ষমাণ তালিকায়",
  "@registrationStatus_waitlisted": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
  "registrationStatus_cancelled": "বাতিল",
  "@registrationStatus_cancelled": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },

  "importStatus_dryRun": "ড্রাই রান",
  "@importStatus_dryRun": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
  "importStatus_readyToCommit": "সংরক্ষণের জন্য প্রস্তুত",
  "@importStatus_readyToCommit": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
  "importStatus_processing": "প্রক্রিয়াধীন",
  "@importStatus_processing": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
  "importStatus_completed": "সম্পন্ন",
  "@importStatus_completed": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
  "importStatus_partiallyCompleted": "আংশিকভাবে সম্পন্ন",
  "@importStatus_partiallyCompleted": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
  "importStatus_failed": "ব্যর্থ",
  "@importStatus_failed": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
  "importStatus_cancelled": "বাতিল",
  "@importStatus_cancelled": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },

  "integrityFlag_noReference": "রেফারেন্স ছবি নেই",
  "@integrityFlag_noReference": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
  "integrityFlag_poorQuality": "ছবির গুণমান খারাপ",
  "@integrityFlag_poorQuality": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
  "integrityFlag_suspectedSpoof": "সন্দেহজনক জাল ছবি",
  "@integrityFlag_suspectedSpoof": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
  "integrityFlag_duplicate": "ডুপ্লিকেট",
  "@integrityFlag_duplicate": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
  "integrityFlag_geofenceException": "ভেন্যুর নির্ধারিত সীমার বাইরে",
  "@integrityFlag_geofenceException": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
  "integrityFlag_manualOverride": "ম্যানুয়াল ওভাররাইড",
  "@integrityFlag_manualOverride": {
    "description": "UNREVIEWED machine draft — needs native Bengali review (P0.5 D6)"
  },
```

- [ ] **Step 5: Regenerate and run the test**

```bash
flutter gen-l10n
flutter test test/l10n/arb_parity_test.dart
```

Expected: PASS, 4 tests. If `gen-l10n` warns about untranslated messages, that is informational — the point of this task is that there are none.

- [ ] **Step 6: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: format clean, analyze exits 0, **260 passing / 29 skipped** (256 + 4).

- [ ] **Step 7: Commit**

```bash
git add lib/l10n/ test/l10n/
git commit -m "test: pin ARB parity and add the 19 missing status keys

status.dart advertised l10nKey getters for five status families while the
ARB carried keys for only two, and because l10nKey was never consumed
nothing noticed. The parity test now pins per-family counts, so adding an
enum value without its key fails a test rather than silently at runtime.

The 19 new Bengali values are machine drafts and carry @-metadata saying
so: the 26 pre-existing ones are genuine human translations, and an
unmarked draft sitting beside them would invite nobody to check it."
```

---

## Task 2: Typed status labels, replacing the broken seam

**Files:**
- Create: `lib/domain/common/status_labels.dart`
- Create: `test/domain/status_labels_test.dart`
- Modify: `lib/domain/common/status.dart` (delete five `l10nKey` getters)

**Interfaces:**
- Consumes: `AppL10n` (per-key getters from Task 1); the five enums in `lib/domain/common/status.dart` — `CampaignStatus` (8 values), `RegistrationStatus` (6), `AttendanceStatus` (7), `ImportStatus` (7), `IntegrityFlag` (6).
- Produces: five extensions, each with `String label(AppL10n l)` — `CampaignStatusL10n`, `RegistrationStatusL10n`, `AttendanceStatusL10n`, `ImportStatusL10n`, `IntegrityFlagL10n`.

- [ ] **Step 1: Write the failing test**

Create `test/domain/status_labels_test.dart`:

```dart
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/domain/common/status_labels.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Both locales are exercised, because a key present in en and empty in bn
  // would satisfy the compiler and still ship a blank label.
  final locales = {'en': AppL10nEn(), 'bn': AppL10nBn()};

  locales.forEach((code, l10n) {
    group('locale $code', () {
      test('every CampaignStatus resolves', () {
        for (final s in CampaignStatus.values) {
          expect(s.label(l10n), isNotEmpty, reason: '$code / ${s.name}');
        }
      });

      test('every RegistrationStatus resolves', () {
        for (final s in RegistrationStatus.values) {
          expect(s.label(l10n), isNotEmpty, reason: '$code / ${s.name}');
        }
      });

      test('every AttendanceStatus resolves', () {
        for (final s in AttendanceStatus.values) {
          expect(s.label(l10n), isNotEmpty, reason: '$code / ${s.name}');
        }
      });

      test('every ImportStatus resolves', () {
        for (final s in ImportStatus.values) {
          expect(s.label(l10n), isNotEmpty, reason: '$code / ${s.name}');
        }
      });

      test('every IntegrityFlag resolves', () {
        for (final f in IntegrityFlag.values) {
          expect(f.label(l10n), isNotEmpty, reason: '$code / ${f.name}');
        }
      });
    });
  });

  test('labels differ between locales', () {
    // Guards against a copy-paste that points bn at the en getters, which
    // would pass every "isNotEmpty" assertion above.
    expect(
      CampaignStatus.draft.label(AppL10nEn()),
      isNot(CampaignStatus.draft.label(AppL10nBn())),
    );
  });

}
```

Import the per-locale classes: `AppL10nEn` lives in `lib/l10n/generated/app_localizations_en.dart` and `AppL10nBn` in `..._bn.dart`. Add both imports.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/domain/status_labels_test.dart`

Expected: FAIL at compile time — `Target of URI doesn't exist: 'package:acsl_campaign/domain/common/status_labels.dart'`.

- [ ] **Step 3: Write the extensions**

Create `lib/domain/common/status_labels.dart`:

```dart
import '../../l10n/generated/app_localizations.dart';
import 'status.dart';

/// Localized labels for the typed status vocabulary (Guideline Appendix B).
///
/// Exhaustive `switch` expressions with no `default` and no `_` wildcard, so
/// adding a value to any of these enums is a COMPILE ERROR here until it has a
/// label. That is deliberate: the previous design exposed `l10nKey` getters
/// returning a runtime String, which could not resolve against `gen-l10n`'s
/// named getters and silently advertised keys for three families the ARB never
/// contained.
extension CampaignStatusL10n on CampaignStatus {
  String label(AppL10n l) => switch (this) {
    CampaignStatus.draft => l.campaignStatus_draft,
    CampaignStatus.pendingApproval => l.campaignStatus_pendingApproval,
    CampaignStatus.returned => l.campaignStatus_returned,
    CampaignStatus.approved => l.campaignStatus_approved,
    CampaignStatus.active => l.campaignStatus_active,
    CampaignStatus.paused => l.campaignStatus_paused,
    CampaignStatus.completed => l.campaignStatus_completed,
    CampaignStatus.cancelled => l.campaignStatus_cancelled,
  };
}

extension RegistrationStatusL10n on RegistrationStatus {
  String label(AppL10n l) => switch (this) {
    RegistrationStatus.invited => l.registrationStatus_invited,
    RegistrationStatus.registered => l.registrationStatus_registered,
    RegistrationStatus.pendingProfileSync =>
      l.registrationStatus_pendingProfileSync,
    RegistrationStatus.ineligible => l.registrationStatus_ineligible,
    RegistrationStatus.waitlisted => l.registrationStatus_waitlisted,
    RegistrationStatus.cancelled => l.registrationStatus_cancelled,
  };
}

extension AttendanceStatusL10n on AttendanceStatus {
  String label(AppL10n l) => switch (this) {
    AttendanceStatus.notCaptured => l.attendanceStatus_notCaptured,
    AttendanceStatus.pendingSync => l.attendanceStatus_pendingSync,
    AttendanceStatus.matchProcessing => l.attendanceStatus_matchProcessing,
    AttendanceStatus.crmReview => l.attendanceStatus_crmReview,
    AttendanceStatus.approved => l.attendanceStatus_approved,
    AttendanceStatus.rejected => l.attendanceStatus_rejected,
    AttendanceStatus.returned => l.attendanceStatus_returned,
  };
}

extension ImportStatusL10n on ImportStatus {
  String label(AppL10n l) => switch (this) {
    ImportStatus.dryRun => l.importStatus_dryRun,
    ImportStatus.readyToCommit => l.importStatus_readyToCommit,
    ImportStatus.processing => l.importStatus_processing,
    ImportStatus.completed => l.importStatus_completed,
    ImportStatus.partiallyCompleted => l.importStatus_partiallyCompleted,
    ImportStatus.failed => l.importStatus_failed,
    ImportStatus.cancelled => l.importStatus_cancelled,
  };
}

extension IntegrityFlagL10n on IntegrityFlag {
  String label(AppL10n l) => switch (this) {
    IntegrityFlag.noReference => l.integrityFlag_noReference,
    IntegrityFlag.poorQuality => l.integrityFlag_poorQuality,
    IntegrityFlag.suspectedSpoof => l.integrityFlag_suspectedSpoof,
    IntegrityFlag.duplicate => l.integrityFlag_duplicate,
    IntegrityFlag.geofenceException => l.integrityFlag_geofenceException,
    IntegrityFlag.manualOverride => l.integrityFlag_manualOverride,
  };
}
```

If any enum value name differs from the above, the compiler will say so — the enum is the source of truth, not this plan.

- [ ] **Step 4: Delete the five `l10nKey` getters**

In `lib/domain/common/status.dart`, remove all five `String get l10nKey => '…';` lines (at roughly lines 30, 41, 54, 66, 79) and any doc comment that refers to them. They have **zero consumers** — verified by grep — so nothing breaks.

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/domain/status_labels_test.dart`

Expected: PASS, 11 tests (5 families × 2 locales + the cross-locale check).

- [ ] **Step 6: Confirm the dead seam is gone**

```bash
grep -rn "l10nKey" lib test || echo "clean"
```

Expected: `clean`.

- [ ] **Step 7: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: **271 passing / 29 skipped** (260 + 11). The skip count must stay 29 — that invariant is how a broken golden gets noticed, so nothing in this epic may add a deliberate skip.

- [ ] **Step 8: Commit**

```bash
git add lib/domain/common/ test/domain/status_labels_test.dart
git commit -m "feat: give status enums typed localized labels

Exhaustive switches with no default, so adding a status value is a compile
error until it has a label. Replaces five l10nKey getters that returned a
runtime String - which could never resolve against gen-l10n's named
getters, and which advertised keys for three families the ARB never had.
They had zero consumers, so deleting them breaks nothing.

Both locales are asserted, because a key present in en and blank in bn
would satisfy the compiler and still ship an empty label."
```

---

## Task 3: Register the delegates — the chain-closing test

**Files:**
- Modify: `lib/app/app.dart:26-33`
- Create: `test/l10n/l10n_render_test.dart`

**Interfaces:**
- Consumes: `AppL10n.localizationsDelegates`, `AppL10n.supportedLocales`; `CampaignStatusL10n.label` (Task 2).
- Produces: a localized `MaterialApp.router`. Every later task's locale work depends on this.

- [ ] **Step 1: Write the failing test**

Create `test/l10n/l10n_render_test.dart`:

```dart
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/domain/common/status_labels.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // This is the test whose absence let commented-out delegates survive since
  // P0.2. "The delegates are registered" is a claim about wiring; only a
  // rendered Bengali glyph proves the chain ARB -> codegen -> delegate ->
  // widget actually closes. The bundled Noto Sans Bengali font (loaded for the
  // whole tree by test/flutter_test_config.dart) is what makes these real
  // glyphs rather than Ahem boxes.
  Widget harness(Locale locale) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    home: Builder(
      builder: (context) =>
          Text(CampaignStatus.draft.label(AppL10n.of(context))),
    ),
  );

  testWidgets('renders English for Locale(en)', (tester) async {
    await tester.pumpWidget(harness(const Locale('en')));
    expect(find.text('Draft'), findsOneWidget);
  });

  testWidgets('renders Bengali for Locale(bn)', (tester) async {
    await tester.pumpWidget(harness(const Locale('bn')));
    expect(find.text('খসড়া'), findsOneWidget);
    expect(find.text('Draft'), findsNothing);
  });

  testWidgets('AppL10n.supportedLocales offers exactly en and bn', (
    tester,
  ) async {
    expect(
      AppL10n.supportedLocales.map((l) => l.languageCode).toSet(),
      {'en', 'bn'},
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/l10n/l10n_render_test.dart`

Expected: the Bengali test FAILS. Depending on how `AppL10n.of` behaves without a registered delegate it either throws or returns the English fallback — either way the `খসড়া` expectation is unmet. That failure is the point: it is the proof the chain was open.

- [ ] **Step 3: Register the delegates**

In `lib/app/app.dart`, replace lines 26–33 (the two commented lines plus the `Global*`-only list) with:

```dart
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
```

`AppL10n.localizationsDelegates` already includes the three `Global*` delegates, so listing them separately is redundant — check the generated file to confirm before deleting them. Add `import '../l10n/generated/app_localizations.dart';` in the correct `directives_ordering` position.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/l10n/l10n_render_test.dart`

Expected: PASS, 3 tests.

- [ ] **Step 5: Verify nothing regressed — watch the goldens**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: **274 passing / 29 skipped**.

**Registering delegates can change Material/Cupertino string rendering**, and the 29 Linux-gated goldens render the component gallery. They skip locally, so a regression surfaces only in CI. If CI later reports a golden failure, **investigate it — do not regenerate baselines** (they regenerate only via the `goldens` workflow on Linux).

- [ ] **Step 6: Commit**

```bash
git add lib/app/app.dart test/l10n/l10n_render_test.dart
git commit -m "fix: actually register the generated localizations

AppL10n.localizationsDelegates had been commented out since P0.2, so only
the Global* delegates were registered and the ARB files were decorative -
a Bengali user got English everywhere. Nothing consumed AppL10n either, so
no test noticed.

The new render test is the guard: it asserts a real Bengali glyph appears,
because 'the delegates are registered' is a claim about wiring while only a
rendered glyph proves the ARB -> codegen -> delegate -> widget chain closes."
```

---

## Task 4: `LocaleStore` — per-device persistence

**Files:**
- Create: `lib/core/l10n/locale_store.dart`
- Create: `test/core/l10n/locale_store_test.dart`

**Interfaces:**
- Consumes: `AppDatabase` and its `cachedReferences` table (`key` text PK, `valueJson` text, `fetchedAt` dateTime); `AppDatabase(NativeDatabase.memory())` is the established in-memory test pattern (see `test/core/sync_engine_test.dart`).
- Produces:
  - `abstract interface class LocaleStore` — `Future<Locale?> read()`, `Future<void> write(Locale locale)`, `Future<void> clear()`.
  - `class DriftLocaleStore implements LocaleStore` — `DriftLocaleStore(AppDatabase db)`.
  - `const String localePrefKey = 'pref:locale'`.

- [ ] **Step 1: Write the failing test**

Create `test/core/l10n/locale_store_test.dart`:

```dart
import 'package:acsl_campaign/core/l10n/locale_store.dart';
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('the preference key is reserved and frozen', () {
    // The `pref:` prefix marks rows that are user preferences rather than
    // cached server data, so a future cache-eviction sweep can exclude them by
    // prefix instead of wiping the user's language choice.
    expect(localePrefKey, 'pref:locale');
    expect(localePrefKey.startsWith('pref:'), isTrue);
  });

  test('unset returns null, meaning follow the system', () async {
    expect(await DriftLocaleStore(db).read(), isNull);
  });

  test('round-trips a written locale', () async {
    final store = DriftLocaleStore(db);

    await store.write(const Locale('bn'));

    expect(await store.read(), const Locale('bn'));
  });

  test('overwrites rather than duplicating', () async {
    final store = DriftLocaleStore(db);

    await store.write(const Locale('bn'));
    await store.write(const Locale('en'));

    expect(await store.read(), const Locale('en'));
    final rows = await db.select(db.cachedReferences).get();
    expect(rows.where((r) => r.key == localePrefKey), hasLength(1));
  });

  test('clear removes the preference', () async {
    final store = DriftLocaleStore(db);
    await store.write(const Locale('bn'));

    await store.clear();

    expect(await store.read(), isNull);
  });

  test('a corrupt stored value returns null instead of throwing', () async {
    // A malformed row must degrade to "follow the system", not crash startup.
    // Locale is a display preference, not a compliance control (spec D7).
    await db
        .into(db.cachedReferences)
        .insert(
          CachedReferencesCompanion.insert(
            key: localePrefKey,
            valueJson: 'not-json{{{',
            fetchedAt: DateTime.utc(2026, 8, 7),
          ),
        );

    expect(await DriftLocaleStore(db).read(), isNull);
  });

  test('an unsupported language code returns null', () async {
    // Guards against a stored value from a future build that supported more
    // languages than this one does.
    await db
        .into(db.cachedReferences)
        .insert(
          CachedReferencesCompanion.insert(
            key: localePrefKey,
            valueJson: '{"languageCode":"fr"}',
            fetchedAt: DateTime.utc(2026, 8, 7),
          ),
        );

    expect(await DriftLocaleStore(db).read(), isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/l10n/locale_store_test.dart`

Expected: FAIL at compile time — `Target of URI doesn't exist: 'package:acsl_campaign/core/l10n/locale_store.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/l10n/locale_store.dart`:

```dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;

import '../storage/app_database.dart';

/// Reserved key for the device's language preference.
///
/// The `pref:` prefix marks rows in `cached_reference` that are user
/// preferences rather than cached server data, so a future cache-eviction
/// sweep can exclude them by prefix instead of silently wiping the user's
/// language choice. NEVER rename: a rename abandons the stored preference on
/// every installed device.
const String localePrefKey = 'pref:locale';

/// Languages this build can honour. A stored value outside this set is
/// treated as unset rather than applied.
const Set<String> supportedLanguageCodes = {'en', 'bn'};

/// The device's language preference. `null` means "follow the system".
///
/// Persisted per device, not per user: a shared field phone in a
/// Bengali-speaking territory should stay Bengali regardless of who signs in
/// (spec D4).
abstract interface class LocaleStore {
  Future<Locale?> read();
  Future<void> write(Locale locale);
  Future<void> clear();
}

/// Drift-backed store over the existing `cached_reference` table.
///
/// Reuses that table rather than adding `shared_preferences` for one string:
/// Drift is already a dependency and the table's purpose is durable key-value
/// for non-authoritative data. The cost is that `fetchedAt` is a poor name for
/// a preference's write time — accepted deliberately over a new dependency or
/// a whole new table.
class DriftLocaleStore implements LocaleStore {
  DriftLocaleStore(this._db);

  final AppDatabase _db;

  @override
  Future<Locale?> read() async {
    final row =
        await (_db.select(_db.cachedReferences)
              ..where((t) => t.key.equals(localePrefKey)))
            .getSingleOrNull();
    if (row == null) return null;

    try {
      final decoded = jsonDecode(row.valueJson);
      if (decoded is! Map) return null;
      final code = decoded['languageCode'];
      if (code is! String || !supportedLanguageCodes.contains(code)) {
        return null;
      }
      return Locale(code);
    } catch (error) {
      // A malformed row must degrade to "follow the system", never crash
      // startup: this is a display preference, not a compliance control.
      debugPrint('Stored locale could not be read ($error). Using system.');
      return null;
    }
  }

  @override
  Future<void> write(Locale locale) => _db
      .into(_db.cachedReferences)
      .insertOnConflictUpdate(
        CachedReferencesCompanion.insert(
          key: localePrefKey,
          valueJson: jsonEncode({'languageCode': locale.languageCode}),
          fetchedAt: DateTime.now().toUtc(),
        ),
      );

  @override
  Future<void> clear() => (_db.delete(
    _db.cachedReferences,
  )..where((t) => t.key.equals(localePrefKey))).go();
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/l10n/locale_store_test.dart`

Expected: PASS, 7 tests. If `insertOnConflictUpdate` is not available on this Drift version, use `into(...).insert(..., mode: InsertMode.insertOrReplace)` — the generated API is the source of truth.

- [ ] **Step 5: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: **281 passing / 29 skipped**.

- [ ] **Step 6: Commit**

```bash
git add lib/core/l10n/locale_store.dart test/core/l10n/locale_store_test.dart
git commit -m "feat: persist the language preference per device

Stored in cached_reference under a reserved pref: prefix so a future cache
sweep can exclude preferences by prefix rather than wiping the user's
language. Reuses that table instead of adding shared_preferences for one
string; the cost is that fetchedAt is a poor name for a preference's write
time, accepted over a new dependency.

A corrupt or unsupported stored value degrades to 'follow the system'
rather than throwing - locale is a display preference, not a compliance
control, so crashing startup over it would be absurd."
```

---

## Task 5: `LocaleController` and wiring `locale:`

**Files:**
- Create: `lib/core/l10n/locale_controller.dart`
- Create: `test/core/l10n/locale_controller_test.dart`
- Modify: `lib/app/di/providers.dart`, `lib/app/app.dart`

**Interfaces:**
- Consumes: `LocaleStore`, `DriftLocaleStore`, `localePrefKey`, `supportedLanguageCodes` (Task 4); `appDatabaseProvider` from `lib/app/di/providers.dart`.
- Produces:
  - `class LocaleController extends Notifier<Locale?>` with `Future<void> load()`, `Future<void> select(Locale? locale)`.
  - `final localeStoreProvider = Provider<LocaleStore>(...)`, `final localeControllerProvider = NotifierProvider<LocaleController, Locale?>(...)`.

- [ ] **Step 1: Write the failing test**

Create `test/core/l10n/locale_controller_test.dart`:

```dart
import 'package:acsl_campaign/core/l10n/locale_controller.dart';
import 'package:acsl_campaign/core/l10n/locale_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory [LocaleStore] so the controller is tested without a database.
class _FakeLocaleStore implements LocaleStore {
  _FakeLocaleStore([this.value]);
  Locale? value;
  int writes = 0;
  int clears = 0;

  @override
  Future<Locale?> read() async => value;

  @override
  Future<void> write(Locale locale) async {
    writes++;
    value = locale;
  }

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }
}

void main() {
  ProviderContainer containerWith(_FakeLocaleStore store) {
    final c = ProviderContainer(
      overrides: [localeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('starts null, meaning follow the system', () {
    final c = containerWith(_FakeLocaleStore());

    expect(c.read(localeControllerProvider), isNull);
  });

  test('load adopts a persisted preference', () async {
    final c = containerWith(_FakeLocaleStore(const Locale('bn')));

    await c.read(localeControllerProvider.notifier).load();

    expect(c.read(localeControllerProvider), const Locale('bn'));
  });

  test('load leaves null when nothing is persisted', () async {
    final c = containerWith(_FakeLocaleStore());

    await c.read(localeControllerProvider.notifier).load();

    expect(c.read(localeControllerProvider), isNull);
  });

  test('select persists and applies', () async {
    final store = _FakeLocaleStore();
    final c = containerWith(store);

    await c.read(localeControllerProvider.notifier).select(const Locale('bn'));

    expect(c.read(localeControllerProvider), const Locale('bn'));
    expect(store.value, const Locale('bn'));
    expect(store.writes, 1);
  });

  test('selecting null clears the preference and returns to system', () async {
    final store = _FakeLocaleStore(const Locale('bn'));
    final c = containerWith(store);
    await c.read(localeControllerProvider.notifier).load();

    await c.read(localeControllerProvider.notifier).select(null);

    expect(c.read(localeControllerProvider), isNull);
    expect(store.value, isNull);
    expect(store.clears, 1);
  });

  test('a store read failure leaves the system locale rather than throwing',
      () async {
    // Spec D7: locale faults degrade and continue.
    final c = containerWith(_ThrowingLocaleStore());

    await expectLater(
      c.read(localeControllerProvider.notifier).load(),
      completes,
    );
    expect(c.read(localeControllerProvider), isNull);
  });
}

class _ThrowingLocaleStore implements LocaleStore {
  @override
  Future<Locale?> read() async => throw StateError('storage unavailable');

  @override
  Future<void> write(Locale locale) async {}

  @override
  Future<void> clear() async {}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/l10n/locale_controller_test.dart`

Expected: FAIL at compile time — `locale_controller.dart` does not exist.

- [ ] **Step 3: Write the controller**

Create `lib/core/l10n/locale_controller.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di/providers.dart';
import 'locale_store.dart';

final localeStoreProvider = Provider<LocaleStore>(
  (ref) => DriftLocaleStore(ref.watch(appDatabaseProvider)),
);

/// The app's current locale. `null` means follow the system, which is exactly
/// what a null `locale:` means to `MaterialApp` — so a Bengali-configured
/// device with nothing persisted is correct on first launch with no
/// special-casing (spec D4).
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() => null;

  /// Adopts any persisted preference. Called once at boot.
  Future<void> load() async {
    try {
      state = await ref.read(localeStoreProvider).read();
    } catch (error) {
      // A display preference must never block startup (spec D7).
      debugPrint('Locale preference could not be loaded ($error).');
      state = null;
    }
  }

  /// Applies [locale] and persists it. `null` returns to the system locale
  /// and clears the stored preference.
  Future<void> select(Locale? locale) async {
    state = locale;
    final store = ref.read(localeStoreProvider);
    try {
      if (locale == null) {
        await store.clear();
      } else {
        await store.write(locale);
      }
    } catch (error) {
      // The choice still applies for this session; it just will not survive
      // a restart. Honouring the user's immediate intent is the right call.
      debugPrint('Locale preference could not be saved ($error).');
    }
  }
}

final localeControllerProvider = NotifierProvider<LocaleController, Locale?>(
  LocaleController.new,
);
```

- [ ] **Step 4: Wire `locale:` into the app**

In `lib/app/app.dart`, inside `build`, add `final locale = ref.watch(localeControllerProvider);` and pass `locale: locale,` to `MaterialApp.router`. Add the import.

In `lib/main.dart`, after `SessionManager.restore()` and before `runApp`:

```dart
  // Adopt the persisted language before the first frame, so a Bengali device
  // does not flash English.
  await container.read(localeControllerProvider.notifier).load();
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/core/l10n/`

Expected: PASS — 7 store tests + 6 controller tests.

- [ ] **Step 6: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: **287 passing / 29 skipped**.

- [ ] **Step 7: Commit**

```bash
git add lib/core/l10n/locale_controller.dart lib/app/ lib/main.dart test/core/l10n/locale_controller_test.dart
git commit -m "feat: drive the app locale from a persisted preference

null means follow the system, which is what a null locale: already means to
MaterialApp - so a Bengali-configured device is correct on first launch with
no special-casing. main() adopts the persisted choice before the first frame
so a Bengali device does not flash English.

A store failure degrades to the system locale and, on write, still applies
for the session: the user's immediate intent is honoured even when it cannot
be saved."
```

---

## Task 6: Language picker screen

**Files:**
- Create: `lib/features/settings/presentation/language_screen.dart`
- Create: `test/widget/language_screen_test.dart`
- Modify: `lib/app/router/route_table.dart`, `lib/app/router/app_router.dart`, `lib/app/shell/app_shell.dart`

**Interfaces:**
- Consumes: `localeControllerProvider` (Task 5); `AppShell({required String title, required Widget body, List<Widget> actions, List<String> breadcrumb})`; `Access`/`Authenticated`/`RouteEntry`/`routeTable` from `lib/app/router/route_table.dart`; `registeredRoutePaths({required bool devRoutesEnabled})` from `app_router.dart`.
- Produces: `class LanguageScreen extends ConsumerWidget`; route `/settings/language` with `Authenticated()` access.

- [ ] **Step 1: Write the failing test**

Create `test/widget/language_screen_test.dart`:

```dart
import 'package:acsl_campaign/core/l10n/locale_controller.dart';
import 'package:acsl_campaign/core/l10n/locale_store.dart';
import 'package:acsl_campaign/features/settings/presentation/language_screen.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLocaleStore implements LocaleStore {
  Locale? value;

  @override
  Future<Locale?> read() async => value;

  @override
  Future<void> write(Locale locale) async => value = locale;

  @override
  Future<void> clear() async => value = null;
}

void main() {
  testWidgets('choosing Bengali applies and persists it', (tester) async {
    final store = _FakeLocaleStore();
    final container = ProviderContainer(
      overrides: [localeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            locale: ref.watch(localeControllerProvider),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: const LanguageScreenBody(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('বাংলা'));
    await tester.pumpAndSettle();

    expect(container.read(localeControllerProvider), const Locale('bn'));
    expect(store.value, const Locale('bn'));
  });

  testWidgets('offers a follow-the-system option that clears the choice', (
    tester,
  ) async {
    final store = _FakeLocaleStore()..value = const Locale('bn');
    final container = ProviderContainer(
      overrides: [localeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await container.read(localeControllerProvider.notifier).load();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            locale: ref.watch(localeControllerProvider),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: const LanguageScreenBody(),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('locale_system')));
    await tester.pumpAndSettle();

    expect(container.read(localeControllerProvider), isNull);
    expect(store.value, isNull);
  });
}
```

Note the test targets `LanguageScreenBody` — the body without `AppShell`, so it needs no router ancestor. `LanguageScreen` wraps it in `AppShell`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widget/language_screen_test.dart`

Expected: FAIL at compile time — `language_screen.dart` does not exist.

- [ ] **Step 3: Write the screen**

Create `lib/features/settings/presentation/language_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_shell.dart';
import '../../../core/l10n/locale_controller.dart';

/// Language preference (spec D4 — per device, not per user).
///
/// Each option is labelled in its OWN language ("English", "বাংলা") rather
/// than translated into the current one: a user who has landed in a language
/// they cannot read must still be able to find their way out.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const AppShell(title: 'Language', body: LanguageScreenBody());
}

/// The picker itself, without the shell — so it can be tested without a
/// router ancestor.
class LanguageScreenBody extends ConsumerWidget {
  const LanguageScreenBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeControllerProvider);
    final controller = ref.read(localeControllerProvider.notifier);

    return ListView(
      children: [
        RadioListTile<String?>(
          key: const Key('locale_system'),
          value: null,
          groupValue: current?.languageCode,
          title: const Text('Use device language'),
          onChanged: (_) => controller.select(null),
        ),
        RadioListTile<String?>(
          key: const Key('locale_en'),
          value: 'en',
          groupValue: current?.languageCode,
          title: const Text('English'),
          onChanged: (_) => controller.select(const Locale('en')),
        ),
        RadioListTile<String?>(
          key: const Key('locale_bn'),
          value: 'bn',
          groupValue: current?.languageCode,
          title: const Text('বাংলা'),
          onChanged: (_) => controller.select(const Locale('bn')),
        ),
      ],
    );
  }
}
```

If `RadioListTile`'s `groupValue`/`onChanged` are deprecated on Flutter 3.44.8 in favour of `RadioGroup`, follow whatever `crm_case_screen.dart` already does — `TASK_BREAKDOWN` T-0.1.3 records a `RadioGroup`/`groupValue` hand-migration there, so that file is the in-repo precedent.

- [ ] **Step 4: Register the route**

In `lib/app/router/route_table.dart`, add to `routeTable`:

```dart
  RouteEntry('/settings/language', Authenticated()),
```

In `lib/app/router/app_router.dart`, add the `GoRoute` and add `'/settings/language'` to `registeredRoutePaths`. **`route_table_test.dart` asserts those two sets are identical, so missing either fails the build** — which is the guarantee P0.4 built.

In `lib/app/shell/app_shell.dart`'s account menu, add a `PopupMenuItem<String>(value: 'language', child: Text('Language'))` above the sign-out item and handle `'language'` in `onSelected` with `context.go('/settings/language')`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/widget/language_screen_test.dart test/app/router/`

Expected: PASS — 2 language tests, and the router suite still green including the exhaustiveness assertions with dev routes on and off.

- [ ] **Step 6: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: **289 passing / 29 skipped**.

- [ ] **Step 7: Commit**

```bash
git add lib/features/settings/ lib/app/ test/widget/language_screen_test.dart
git commit -m "feat: add a language picker reachable from the account menu

Each option is labelled in its own language rather than translated into the
current one: a user who has landed in a language they cannot read must still
be able to find their way out.

Registering /settings/language required adding it to BOTH routeTable and
registeredRoutePaths - the exhaustiveness test P0.4 added asserts those sets
are identical, so an ungated route cannot ship."
```

---

## Task 7: `ConsentNotice`, `ConsentRecord` and the hash

**Files:**
- Create: `lib/core/consent/notice.dart`
- Create: `test/core/consent/notice_hash_test.dart`

**Interfaces:**
- Consumes: `cryptography` ^2.7.0 (resolved 2.9.0), which exposes `Sha256()`.
- Produces:
  - `class ConsentNotice` — `ConsentNotice({required int version, required String language, required String title, required String body})`, with `String get contentHash`.
  - `class ConsentRecord` — `ConsentRecord({required int version, required String language, required DateTime shownAt, required String contentHash})`, plus `factory ConsentRecord.of(ConsentNotice notice, DateTime shownAt)`.
  - `Future<String> consentContentHash({required int version, required String language, required String title, required String body})`.

**Three related names, deliberately distinct — do not consolidate them:**

| Name | What it is |
|---|---|
| `consentContentHash(...)` | the top-level **function** that computes a digest |
| `ConsentNotice.hash()` | a **convenience** calling that function with the notice's own fields |
| `ConsentRecord.contentHash` / the `consentContentHash` **column** | the **stored value** on a record and on `attendance_drafts` |

The function and the column share a name but live in different scopes (top-level versus a Drift table getter), so there is no collision — but a reader skimming `consentContentHash: Value(consent.contentHash)` in Task 10 should know the left side is a column and the right side is a stored string, not a call.

- [ ] **Step 1: Write the failing test**

Create `test/core/consent/notice_hash_test.dart`:

```dart
import 'package:acsl_campaign/core/consent/notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('consentContentHash', () {
    test('a known input hashes to a pinned digest', () async {
      // The pre-image format is a CONTRACT: changing it invalidates every
      // stored contentHash, so a golden digest is what makes such a change
      // loud instead of silent. If this fails after an intentional format
      // change, that is the signal to migrate stored hashes - not to update
      // the literal.
      final hash = await consentContentHash(
        version: 1,
        language: 'en',
        title: 'Notice',
        body: 'Body',
      );

      // Pre-image: 1:1|2:en|6:Notice|4:Body
      expect(hash, hasLength(64)); // hex SHA-256
      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
      // Pin the exact value once observed — see Step 4.
    });

    test('is deterministic for identical input', () async {
      final a = await consentContentHash(
        version: 2,
        language: 'bn',
        title: 'শিরোনাম',
        body: 'বিষয়বস্তু',
      );
      final b = await consentContentHash(
        version: 2,
        language: 'bn',
        title: 'শিরোনাম',
        body: 'বিষয়বস্তু',
      );

      expect(a, b);
    });

    test('differs when the body differs', () async {
      final a = await consentContentHash(
        version: 1,
        language: 'en',
        title: 'T',
        body: 'one',
      );
      final b = await consentContentHash(
        version: 1,
        language: 'en',
        title: 'T',
        body: 'two',
      );

      expect(a, isNot(b));
    });

    test('differs for the same text in another language', () async {
      final en = await consentContentHash(
        version: 1,
        language: 'en',
        title: 'T',
        body: 'B',
      );
      final bn = await consentContentHash(
        version: 1,
        language: 'bn',
        title: 'T',
        body: 'B',
      );

      expect(en, isNot(bn));
    });

    test('is injective where naive delimiter-joining would collide', () async {
      // Length prefixes are the whole point. Under a naive "join with |"
      // scheme these two would produce the same pre-image; they must not
      // produce the same hash.
      final a = await consentContentHash(
        version: 1,
        language: 'en',
        title: 'A|B',
        body: 'C',
      );
      final b = await consentContentHash(
        version: 1,
        language: 'en',
        title: 'A',
        body: 'B|C',
      );

      expect(a, isNot(b));
    });

    test('handles multi-byte content by BYTE length, not rune count', () async {
      // 'শিরোনাম' is far longer in UTF-8 bytes than in runes. Prefixing with
      // rune count would make the encoding ambiguous again.
      final hash = await consentContentHash(
        version: 1,
        language: 'bn',
        title: 'শিরোনাম',
        body: 'B',
      );

      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });

  group('ConsentRecord', () {
    test('of() copies the notice identity and the shown time', () async {
      final notice = ConsentNotice(
        version: 3,
        language: 'bn',
        title: 'শিরোনাম',
        body: 'বিষয়বস্তু',
      );
      final at = DateTime.utc(2026, 8, 7, 12);

      final record = ConsentRecord.of(notice, at, await notice.hash());

      expect(record.version, 3);
      expect(record.language, 'bn');
      expect(record.shownAt, at);
      expect(record.contentHash, await notice.hash());
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/consent/notice_hash_test.dart`

Expected: FAIL at compile time — `notice.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/core/consent/notice.dart`:

```dart
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// A consent/purpose notice as shown to a carpenter (Guideline §10.3).
class ConsentNotice {
  const ConsentNotice({
    required this.version,
    required this.language,
    required this.title,
    required this.body,
  });

  /// Monotonic integer, deliberately not a version string: "newest held
  /// version wins" needs an unambiguous comparison, and semver-style strings
  /// invite `'10' < '9'`.
  final int version;

  final String language; // 'en' | 'bn'
  final String title;
  final String body;

  Future<String> hash() => consentContentHash(
    version: version,
    language: language,
    title: title,
    body: body,
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'language': language,
    'title': title,
    'body': body,
  };

  static ConsentNotice fromJson(Map<String, Object?> json) => ConsentNotice(
    version: (json['version']! as num).toInt(),
    language: json['language']! as String,
    title: json['title']! as String,
    body: json['body']! as String,
  );
}

/// What was actually shown, recorded with each capture.
///
/// Stores the hash rather than the text, so the record PROVES the wording
/// instead of merely pointing at a version — on a dispute, fetch version N in
/// language L and verify the hash matches.
class ConsentRecord {
  const ConsentRecord({
    required this.version,
    required this.language,
    required this.shownAt,
    required this.contentHash,
  });

  factory ConsentRecord.of(
    ConsentNotice notice,
    DateTime shownAt,
    String contentHash,
  ) => ConsentRecord(
    version: notice.version,
    language: notice.language,
    shownAt: shownAt,
    contentHash: contentHash,
  );

  final int version;
  final String language;
  final DateTime shownAt;
  final String contentHash;
}

/// SHA-256 over a LENGTH-PREFIXED pre-image.
///
/// "Join the fields with a delimiter that cannot appear in the content" is not
/// a real guarantee — any byte can appear in a title or body, so a notice
/// containing the delimiter would collide with a different notice that splits
/// differently. Each field is therefore written as its UTF-8 BYTE length, a
/// colon, then its bytes:
///
///     1:1|2:en|6:Notice|4:Body
///
/// Byte length, not rune count: a Bengali title is far longer in bytes than in
/// runes, and prefixing with runes would reintroduce the ambiguity.
///
/// THIS FORMAT IS A CONTRACT. Changing it invalidates every previously written
/// `contentHash`, which is why a test pins a known input to a known digest.
Future<String> consentContentHash({
  required int version,
  required String language,
  required String title,
  required String body,
}) async {
  final buffer = <int>[];
  for (final field in [version.toString(), language, title, body]) {
    final bytes = utf8.encode(field);
    buffer.addAll(utf8.encode('${bytes.length}:'));
    buffer.addAll(bytes);
    buffer.addAll(utf8.encode('|'));
  }

  final digest = await Sha256().hash(buffer);
  return digest.bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}
```

- [ ] **Step 4: Run the test, then pin the digest**

Run: `flutter test test/core/consent/notice_hash_test.dart`

Expected: PASS, 7 tests. Then **pin the golden digest**: print the value produced for `version: 1, language: 'en', title: 'Notice', body: 'Body'`, and replace the placeholder comment in the first test with a real literal assertion:

```dart
      expect(hash, '<the observed 64-char hex digest>');
```

Re-run and confirm it still passes. A format test with no pinned value does not guard the contract.

- [ ] **Step 5: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: **296 passing / 29 skipped**.

- [ ] **Step 6: Commit**

```bash
git add lib/core/consent/notice.dart test/core/consent/notice_hash_test.dart
git commit -m "feat: hash consent notices over a length-prefixed pre-image

'Join with a delimiter that cannot appear in the content' is not a real
guarantee - any byte can appear in a title, so a notice containing the
delimiter would collide with a different notice that splits differently.
Each field is written as its UTF-8 byte length, a colon, then its bytes,
which is injective regardless of content. Byte length rather than rune
count, because a Bengali title is much longer in bytes than in runes.

The format is a contract: changing it invalidates every stored hash, so a
test pins a known input to a known digest to make such a change loud."
```

---

## Task 8: `NoticeRepository`, the bundled floor, and the 🔒 source

**Files:**
- Create: `assets/consent/notice_v1.json`
- Create: `lib/core/consent/notice_repository.dart`
- Create: `test/core/consent/notice_repository_test.dart`
- Modify: `pubspec.yaml` (bundle `assets/consent/`)

**Interfaces:**
- Consumes: `ConsentNotice`, `consentContentHash` (Task 7); `AppDatabase`; `Result`/`Ok`/`Err`/`Failure`/`FailureKind` from `lib/core/result/result.dart`; `mapDioError` from `lib/core/network/dio_client.dart`.
- Produces:
  - `abstract interface class NoticeSource` — `Future<Result<List<ConsentNotice>>> fetchLatest()`.
  - `class DioNoticeSource implements NoticeSource` — `DioNoticeSource(Dio dio)` (🔒).
  - `class NoticeRepository` — `NoticeRepository({required AppDatabase db, required NoticeSource source, Future<String> Function(String) loadAsset})`, with `Future<Result<ConsentNotice>> resolve(String language)` and `Future<void> refreshInBackground()`.

**Note:** the `consent_notices` Drift table arrives in Task 9. Until then `NoticeRepository` takes its cached notices through a narrow seam so this task is testable on its own — Task 9 swaps the seam for the real table. That ordering is deliberate: the repository's *resolution rule* is the risky part and deserves its own review gate, separate from a schema migration.

- [ ] **Step 1: Write the bundled floor**

Create `assets/consent/notice_v1.json`:

```json
{
  "version": 1,
  "notices": [
    {
      "version": 1,
      "language": "en",
      "title": "Attendance photo and identity verification",
      "body": "PLACEHOLDER — pending Legal sign-off (🔒 T-0.5.2). We will take your photograph to confirm your attendance at this session. The photograph is reviewed by our team to verify your identity against your registered profile. It is stored securely, is not shared outside this programme, and is retained only for the period set by our retention policy. You may decline; declining means your attendance cannot be recorded for this session."
    },
    {
      "version": 1,
      "language": "bn",
      "title": "উপস্থিতির ছবি এবং পরিচয় যাচাই",
      "body": "প্লেসহোল্ডার — আইনি অনুমোদনের অপেক্ষায় (🔒 T-0.5.2)। এই সেশনে আপনার উপস্থিতি নিশ্চিত করার জন্য আমরা আপনার ছবি তুলব। আপনার নিবন্ধিত প্রোফাইলের সাথে পরিচয় যাচাই করতে আমাদের দল ছবিটি পর্যালোচনা করে। ছবিটি নিরাপদে সংরক্ষণ করা হয়, এই কর্মসূচির বাইরে শেয়ার করা হয় না, এবং শুধুমাত্র আমাদের নীতিতে নির্ধারিত সময় পর্যন্ত রাখা হয়। আপনি অস্বীকার করতে পারেন; অস্বীকার করলে এই সেশনের জন্য আপনার উপস্থিতি নথিভুক্ত করা যাবে না।"
    }
  ]
}
```

Both bodies are **placeholders pending Legal** and say so in-text, so nobody mistakes them for approved wording. The Bengali is a machine draft on the same footing as Task 1's.

In `pubspec.yaml`, under `flutter:` → `assets:`, add `- assets/consent/`.

- [ ] **Step 2: Write the failing test**

Create `test/core/consent/notice_repository_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:acsl_campaign/core/consent/notice.dart';
import 'package:acsl_campaign/core/consent/notice_repository.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Source whose result is scripted, recording whether it was called at all.
class _ScriptedSource implements NoticeSource {
  _ScriptedSource([this._result]);
  final Result<List<ConsentNotice>>? _result;
  int calls = 0;
  Completer<void>? gate;

  @override
  Future<Result<List<ConsentNotice>>> fetchLatest() async {
    calls++;
    if (gate != null) await gate!.future;
    return _result ?? const Ok(<ConsentNotice>[]);
  }
}

String _bundledJson({int version = 1}) => jsonEncode({
  'version': version,
  'notices': [
    {
      'version': version,
      'language': 'en',
      'title': 'Bundled EN',
      'body': 'Bundled body EN',
    },
    {
      'version': version,
      'language': 'bn',
      'title': 'Bundled BN',
      'body': 'Bundled body BN',
    },
  ],
});

void main() {
  NoticeRepository build({
    _ScriptedSource? source,
    List<ConsentNotice> cached = const [],
    String? assetJson,
    bool assetThrows = false,
  }) => NoticeRepository(
    source: source ?? _ScriptedSource(),
    readCached: () async => cached,
    writeCached: (_) async {},
    loadAsset: (_) async {
      if (assetThrows) throw StateError('asset missing');
      return assetJson ?? _bundledJson();
    },
  );

  group('resolve', () {
    test('falls back to the bundled floor when nothing is cached', () async {
      final result = await build().resolve('en');

      final notice = result.fold((n) => n, (_) => null)!;
      expect(notice.version, 1);
      expect(notice.title, 'Bundled EN');
    });

    test('prefers a newer cached version over the bundled floor', () async {
      final result = await build(
        cached: const [
          ConsentNotice(
            version: 5,
            language: 'en',
            title: 'Cached EN v5',
            body: 'b',
          ),
        ],
      ).resolve('en');

      expect(result.fold((n) => n.version, (_) => null), 5);
      expect(result.fold((n) => n.title, (_) => null), 'Cached EN v5');
    });

    test('keeps the bundled floor when the cache is OLDER', () async {
      // A stale cached row must never beat a newer bundled version shipped by
      // an app update.
      final result = await build(
        assetJson: _bundledJson(version: 7),
        cached: const [
          ConsentNotice(version: 3, language: 'en', title: 'old', body: 'b'),
        ],
      ).resolve('en');

      expect(result.fold((n) => n.version, (_) => null), 7);
    });

    test('picks the highest cached version, not the first', () async {
      final result = await build(
        cached: const [
          ConsentNotice(version: 4, language: 'en', title: 'v4', body: 'b'),
          ConsentNotice(version: 9, language: 'en', title: 'v9', body: 'b'),
          ConsentNotice(version: 6, language: 'en', title: 'v6', body: 'b'),
        ],
      ).resolve('en');

      expect(result.fold((n) => n.version, (_) => null), 9);
    });

    test('resolves per language, not globally', () async {
      final result = await build(
        cached: const [
          ConsentNotice(version: 9, language: 'en', title: 'v9 en', body: 'b'),
        ],
      ).resolve('bn');

      // No cached bn row, so bn falls back to the bundled floor even though a
      // newer en version exists.
      expect(result.fold((n) => n.title, (_) => null), 'Bundled BN');
    });

    test('NEVER awaits the network', () async {
      // The guarantee that makes offline capture possible. The gate is held
      // shut for the whole call; if resolve awaited the source it would hang
      // and this test would time out.
      final source = _ScriptedSource()..gate = Completer<void>();

      final result = await build(source: source).resolve('en');

      expect(result.isOk, isTrue);
      expect(source.calls, 0);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('returns Err when no notice can be resolved at all', () async {
      // Spec D7: consent fails CLOSED. A missing bundled asset with an empty
      // cache must not yield a null notice that a caller might render as blank
      // — capture has to be blocked.
      final result = await build(assetThrows: true).resolve('en');

      expect(result.isOk, isFalse);
      expect(result.fold((_) => null, (f) => f.kind), FailureKind.unknown);
    });

    test('returns Err for a language the bundle does not contain', () async {
      final result = await build().resolve('fr');

      expect(result.isOk, isFalse);
    });
  });

  group('refreshInBackground', () {
    test('calls the source and does not throw when it fails', () async {
      final source = _ScriptedSource(
        const Err(Failure(FailureKind.network)),
      );

      await expectLater(
        build(source: source).refreshInBackground(),
        completes,
      );
      expect(source.calls, 1);
    });
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/core/consent/notice_repository_test.dart`

Expected: FAIL at compile time — `notice_repository.dart` does not exist.

- [ ] **Step 4: Write the implementation**

Create `lib/core/consent/notice_repository.dart`:

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../network/dio_client.dart';
import '../result/result.dart';
import 'notice.dart';

/// Transport seam for newer notice versions.
///
/// 🔒 The notice contract (endpoint, payload shape, versioning semantics) is
/// unresolved. Keeping it behind one method means the resolution rule, the
/// cache and the consent record are all transport-agnostic when it lands.
abstract interface class NoticeSource {
  Future<Result<List<ConsentNotice>>> fetchLatest();
}

/// Dio-backed source. Endpoint and shape are placeholders pending the 🔒
/// contract, exactly as `DioAuthService` and `DioAuditTransport` are.
class DioNoticeSource implements NoticeSource {
  DioNoticeSource(this._dio);

  final Dio _dio;

  @override
  Future<Result<List<ConsentNotice>>> fetchLatest() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/consent/notices');
      final list = (res.data!['notices'] as List)
          .map((e) => ConsentNotice.fromJson((e as Map).cast<String, Object?>()))
          .toList();
      return Ok(list);
    } catch (e) {
      return Err(mapDioError(e));
    }
  }
}

/// Resolves which consent notice to show.
///
/// The rule: the highest version this device ACTUALLY HOLDS for the requested
/// language, cached or bundled. [resolve] never awaits the network — capture
/// happens offline in the field, and blocking it on a fetch would make the
/// bundled floor pointless. Fetching is [refreshInBackground]'s job and is
/// entirely off the capture path.
class NoticeRepository {
  NoticeRepository({
    required NoticeSource source,
    required Future<List<ConsentNotice>> Function() readCached,
    required Future<void> Function(List<ConsentNotice>) writeCached,
    Future<String> Function(String key)? loadAsset,
  }) : _source = source,
       _readCached = readCached,
       _writeCached = writeCached,
       _loadAsset = loadAsset ?? rootBundle.loadString;

  static const String bundledAssetKey = 'assets/consent/notice_v1.json';

  final NoticeSource _source;
  final Future<List<ConsentNotice>> Function() _readCached;
  final Future<void> Function(List<ConsentNotice>) _writeCached;
  final Future<String> Function(String) _loadAsset;

  /// The notice to show for [language], or `Err` if none can be resolved.
  ///
  /// `Err` rather than a null notice on purpose: spec D7 has consent failing
  /// CLOSED, so a caller cannot accidentally render a blank notice and proceed.
  Future<Result<ConsentNotice>> resolve(String language) async {
    final candidates = <ConsentNotice>[];

    try {
      candidates.addAll(
        (await _readCached()).where((n) => n.language == language),
      );
    } catch (error) {
      // A cache fault must not prevent the bundled floor from being used.
      debugPrint('Cached notices unreadable ($error); using the bundle.');
    }

    try {
      candidates.addAll(
        (await _bundled()).where((n) => n.language == language),
      );
    } catch (error) {
      debugPrint('Bundled notice unreadable ($error).');
    }

    if (candidates.isEmpty) {
      return Err(
        Failure(
          FailureKind.unknown,
          message: 'No consent notice is available in "$language".',
        ),
      );
    }

    candidates.sort((a, b) => b.version.compareTo(a.version));
    return Ok(candidates.first);
  }

  /// Opportunistic. Never called from the capture path, never surfaced.
  Future<void> refreshInBackground() async {
    final result = await _source.fetchLatest();
    if (result case Ok(:final value) when value.isNotEmpty) {
      try {
        await _writeCached(value);
      } catch (error) {
        debugPrint('Fetched notices could not be cached ($error).');
      }
    }
  }

  Future<List<ConsentNotice>> _bundled() async {
    final json =
        jsonDecode(await _loadAsset(bundledAssetKey)) as Map<String, Object?>;
    return (json['notices']! as List)
        .map((e) => ConsentNotice.fromJson((e as Map).cast<String, Object?>()))
        .toList();
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/core/consent/notice_repository_test.dart`

Expected: PASS, 9 tests.

- [ ] **Step 6: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: **305 passing / 29 skipped**.

- [ ] **Step 7: Commit**

```bash
git add assets/consent/ lib/core/consent/notice_repository.dart pubspec.yaml test/core/consent/notice_repository_test.dart
git commit -m "feat: resolve consent notices without ever awaiting the network

resolve() returns the highest version the device actually holds for the
requested language, cached or bundled, and never touches the source - a test
holds the source's gate shut for the whole call and asserts zero calls.
Capture happens offline in the field, so blocking it on a fetch would make
the bundled floor pointless.

Failure returns Err rather than a null notice, so a caller cannot render a
blank notice and proceed: spec D7 has consent failing closed. Both bundled
bodies say PLACEHOLDER in-text, pending Legal sign-off."
```

---

## Task 9: Schema v3 — the cache table and the consent columns

**Files:**
- Modify: `lib/core/storage/app_database.dart`
- Modify: `lib/core/consent/notice_repository.dart` (wire the real cache)
- Modify: `test/core/storage/migration_test.dart`
- Create: `drift_schemas/drift_schema_v3.json`, `test/generated/schema_v3.dart` (generated)

**Interfaces:**
- Consumes: `ConsentNotice` (Task 7); `NoticeRepository`'s `readCached`/`writeCached` seams (Task 8).
- Produces: `ConsentNotices` table (`version` int, `language` text, `title`, `body`, `contentHash`, `fetchedAt`; PK `{version, language}`); four columns on `AttendanceDrafts` — `consentVersion` (int, nullable), `consentLanguage` (text, nullable), `consentShownAt` (dateTime, nullable), `consentContentHash` (text, nullable); `AppDatabase.schemaVersion == 3`; `driftNoticeCacheReaders(AppDatabase)` helpers.

**The consent columns are nullable.** Existing queued `attendance_draft` rows on real devices predate consent capture and have no values to backfill — a non-null column would make the migration impossible without inventing data. Task 10 enforces presence at the write site instead, which is where the requirement actually belongs.

- [ ] **Step 1: Confirm the v2 baseline exists before touching the schema**

```bash
ls drift_schemas/
grep -n "schemaVersion" lib/core/storage/app_database.dart
```

Expected: `drift_schema_v1.json` and `drift_schema_v2.json` are present, and `schemaVersion => 2`. If v2's dump is missing, **stop** — dump it before bumping, exactly as P0.3's Task 1 did for v1. The baseline is unrecoverable afterwards without a git checkout.

- [ ] **Step 2: Write the failing test**

Append to `test/core/storage/migration_test.dart`:

```dart
  test('migrates v2 to v3', () async {
    final connection = await verifier.schemaAt(2);
    final db = AppDatabase(connection.newConnection());

    await verifier.migrateAndValidate(db, 3);

    await db.close();
  });

  test('v2 to v3 preserves queued field data and audit rows', () async {
    // The assertion that protects users. A migration that drops a queued
    // attendance capture loses field evidence that cannot be recaptured — the
    // carpenter has left the venue.
    final connection = await verifier.schemaAt(2);

    final oldDb = v2.DatabaseAtV2(connection.newConnection());
    await oldDb.into(oldDb.syncTasks).insert(
      v2.SyncTasksData(
        id: 'task-1',
        type: 'attendance',
        payloadJson: '{"sessionId":"s1"}',
        status: 'pendingSync',
        retryCount: 2,
        createdAt: DateTime.utc(2026, 8, 1, 9, 30),
        lastError: 'connection refused',
      ),
    );
    await oldDb.into(oldDb.attendanceDrafts).insert(
      v2.AttendanceDraftsData(
        id: 'task-1',
        sessionId: 's1',
        carpenterId: 'c1',
        encryptedMediaPath: '/enc/task-1.bin',
        capturedAt: DateTime.utc(2026, 8, 1, 9, 29),
        capturedBy: 'field-user-1',
      ),
    );
    await oldDb.close();

    final db = AppDatabase(connection.newConnection());
    await verifier.migrateAndValidate(db, 3);

    final tasks = await db.select(db.syncTasks).get();
    expect(tasks, hasLength(1));
    expect(tasks.single.retryCount, 2);
    expect(tasks.single.lastError, 'connection refused');

    final drafts = await db.select(db.attendanceDrafts).get();
    expect(drafts, hasLength(1));
    expect(drafts.single.encryptedMediaPath, '/enc/task-1.bin');
    expect(drafts.single.capturedBy, 'field-user-1');
    // Pre-existing rows have no consent — the columns must be nullable.
    expect(drafts.single.consentVersion, isNull);
    expect(drafts.single.consentContentHash, isNull);

    expect(await db.select(db.consentNotices).get(), isEmpty);

    await db.close();
  });

  test('the consent columns round-trip', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.attendanceDrafts).insert(
      AttendanceDraftsCompanion.insert(
        id: 'a-1',
        sessionId: 's1',
        carpenterId: 'c1',
        encryptedMediaPath: '/enc/a-1.bin',
        capturedAt: DateTime.utc(2026, 8, 7, 12),
        capturedBy: 'u-1',
        consentVersion: const Value(4),
        consentLanguage: const Value('bn'),
        consentShownAt: Value(DateTime.utc(2026, 8, 7, 11, 59)),
        consentContentHash: const Value('deadbeef'),
      ),
    );

    final row = await db.select(db.attendanceDrafts).getSingle();
    expect(row.consentVersion, 4);
    expect(row.consentLanguage, 'bn');
    expect(row.consentShownAt?.toUtc(), DateTime.utc(2026, 8, 7, 11, 59));
    expect(row.consentContentHash, 'deadbeef');
  });

  test('consent_notices is keyed on version AND language', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    Future<void> put(int version, String language) =>
        db.into(db.consentNotices).insert(
          ConsentNoticesCompanion.insert(
            version: version,
            language: language,
            title: 't',
            body: 'b',
            contentHash: 'h',
            fetchedAt: DateTime.utc(2026, 8, 7),
          ),
        );

    // Same version in two languages must coexist.
    await put(1, 'en');
    await put(1, 'bn');

    expect(await db.select(db.consentNotices).get(), hasLength(2));
  });
```

Add `import '../../generated/schema_v2.dart' as v2;` to that file. Note the existing v1→v2 test uses `v1.DatabaseAtV1`; follow whatever constructor form the generated file actually declares (P0.3's Task 6 found `DatabaseAtV1(QueryExecutor)` with `InitializedSchema.newConnection()`).

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/core/storage/migration_test.dart`

Expected: FAIL at compile time — `schema_v3.dart` does not exist and `consentNotices` is undefined.

- [ ] **Step 4: Add the table and columns**

In `lib/core/storage/app_database.dart`, add the table:

```dart
/// Durable cache of fetched consent-notice versions (Guideline §10.3).
///
/// Keyed on `(version, language)` because the same version exists once per
/// language, and both must be able to coexist.
@DataClassName('ConsentNoticeRow')
class ConsentNotices extends Table {
  IntColumn get version => integer()();
  TextColumn get language => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();

  /// The hash of this exact text, so a consent record can be verified against
  /// the version it names.
  TextColumn get contentHash => text()();

  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {version, language};
}
```

Add four columns to `AttendanceDrafts`:

```dart
  /// The consent notice shown before this capture (T-0.5.2).
  ///
  /// Nullable because rows queued by a pre-P0.5 build have no consent to
  /// backfill — inventing values would be worse than recording their absence.
  /// Presence is enforced at the write site in `capture_controller`, which is
  /// where the requirement actually belongs.
  IntColumn get consentVersion => integer().nullable()();
  TextColumn get consentLanguage => text().nullable()();
  DateTimeColumn get consentShownAt => dateTime().nullable()();
  TextColumn get consentContentHash => text().nullable()();
```

Add `ConsentNotices` to the `@DriftDatabase(tables: [...])` list, bump `schemaVersion` to `3`, and extend the migration:

```dart
      onUpgrade: stepByStep(
        from1To2: (m, schema) async => m.createTable(schema.auditEvents),
        from2To3: (m, schema) async {
          await m.createTable(schema.consentNotices);
          await m.addColumn(
            schema.attendanceDrafts,
            schema.attendanceDrafts.consentVersion,
          );
          await m.addColumn(
            schema.attendanceDrafts,
            schema.attendanceDrafts.consentLanguage,
          );
          await m.addColumn(
            schema.attendanceDrafts,
            schema.attendanceDrafts.consentShownAt,
          );
          await m.addColumn(
            schema.attendanceDrafts,
            schema.attendanceDrafts.consentContentHash,
          );
        },
      ),
```

- [ ] **Step 5: Regenerate everything, in this order**

```bash
dart run build_runner build --delete-conflicting-outputs
dart run drift_dev schema steps drift_schemas/ lib/core/storage/schema_versions.dart
dart run drift_dev schema dump lib/core/storage/app_database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated/
```

The `steps` regeneration is what makes `from2To3` available. Confirm `drift_schemas/drift_schema_v3.json` and `test/generated/schema_v3.dart` appear.

- [ ] **Step 6: Wire the real cache into `NoticeRepository`**

In `lib/core/consent/notice_repository.dart`, add Drift-backed implementations of the two seams — keep the seams so the Task 8 tests still run without a database:

```dart
/// Drift-backed cache readers for [NoticeRepository]'s seams.
Future<List<ConsentNotice>> Function() driftNoticeReader(AppDatabase db) =>
    () async => (await db.select(db.consentNotices).get())
        .map(
          (r) => ConsentNotice(
            version: r.version,
            language: r.language,
            title: r.title,
            body: r.body,
          ),
        )
        .toList();

Future<void> Function(List<ConsentNotice>) driftNoticeWriter(AppDatabase db) =>
    (notices) async => db.batch((b) {
      for (final n in notices) {
        b.insert(
          db.consentNotices,
          ConsentNoticesCompanion.insert(
            version: n.version,
            language: n.language,
            title: n.title,
            body: n.body,
            contentHash: '', // filled by the caller that has the hash
            fetchedAt: DateTime.now().toUtc(),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
```

`contentHash` is computed by the caller because it is async and a batch callback is not. Have `refreshInBackground` compute each hash before writing, and pass it through — adjust the writer signature to take pre-hashed rows if that reads more cleanly. **Do not leave an empty hash in the table**; a stored row whose hash is blank would defeat the verification the column exists for.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/core/storage/migration_test.dart test/core/consent/`

Expected: PASS — the migration file's existing 2 tests plus 4 new, and Task 8's 9 still green.

- [ ] **Step 8: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: **309 passing / 29 skipped**. `test/core/sync_engine_test.dart` opens `AppDatabase(NativeDatabase.memory())` directly and now runs `onCreate` at v3 — confirm it is still green.

- [ ] **Step 9: Commit**

```bash
git add lib/core/storage/ lib/core/consent/ drift_schemas/ test/generated/ test/core/storage/migration_test.dart
git commit -m "feat: add the consent cache and consent columns as schema v3

consent_notices is keyed on (version, language) because the same version
exists once per language and both must coexist. The four columns on
attendance_drafts are nullable: rows queued by a pre-P0.5 build have no
consent to backfill, and inventing values would be worse than recording
their absence. Presence is enforced at the write site instead.

The migration test asserts queued sync_task, attendance_draft and
audit_events rows survive intact - a migration that drops a queued capture
loses field evidence nobody can recapture."
```

---

## Task 10: Record the consent with each capture

**Files:**
- Modify: `lib/features/camera_capture/application/capture_controller.dart`
- Modify: `lib/features/camera_capture/presentation/capture_flow_screen.dart`
- Modify: `lib/app/di/providers.dart`
- Create: `test/features/capture_consent_test.dart`

**Interfaces:**
- Consumes: `ConsentNotice`, `ConsentRecord`, `consentContentHash` (Task 7); `NoticeRepository.resolve` (Task 8); the four `AttendanceDrafts` columns (Task 9); `localeControllerProvider` (Task 5).
- Produces: `noticeRepositoryProvider`; `CaptureState` gains `ConsentNotice? notice`, `ConsentRecord? consent`, `bool noticeBlocked`; `CaptureController` gains `Future<void> loadNotice(String language)`, `Future<void> acceptNotice()`, and `selectNoticeLanguage(String)`.

**This task closes the spec gap named in File Structure.** `acceptNotice(String language)` is currently synchronous and only sets `noticeLanguage`, but resolving a notice is async and the DB insert happens later in `submit()`. So:

- The notice is **resolved** when the notice step is entered (async), into `CaptureState.notice` — the text has to exist before it can be shown, let alone accepted.
- **`acceptNotice()` takes no argument** and records a `ConsentRecord` built from `state.notice`. The old signature invited recording a language that did not match the text displayed.
- **Language is switched by `selectNoticeLanguage(String)`**, which re-resolves. Notice language is independent of app locale (T-2.3.3): the carpenter must understand the notice, and the field user's UI preference is irrelevant to that. The app locale is only the *default*.
- If resolution fails, `noticeBlocked` is set and **capture cannot proceed** (spec D7).

- [ ] **Step 1: Write the failing test**

Create `test/features/capture_consent_test.dart`:

```dart
import 'package:acsl_campaign/core/consent/notice.dart';
import 'package:acsl_campaign/core/consent/notice_repository.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/features/camera_capture/application/capture_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const notice = ConsentNotice(
    version: 4,
    language: 'bn',
    title: 'শিরোনাম',
    body: 'বিষয়বস্তু',
  );

  test('accepting records version, language, timestamp AND hash', () async {
    // The existing TODO said "version + language + timestamp" and omitted the
    // hash — the one field that makes the record PROVE the text rather than
    // point at it.
    final record = ConsentRecord.of(
      notice,
      DateTime.utc(2026, 8, 7, 12),
      await notice.hash(),
    );

    expect(record.version, 4);
    expect(record.language, 'bn');
    expect(record.shownAt, DateTime.utc(2026, 8, 7, 12));
    expect(record.contentHash, await notice.hash());
    expect(record.contentHash, isNotEmpty);
  });

  test('the recorded hash matches the text that was displayed', () async {
    // Resolution and recording must read the SAME object, or the record could
    // attest to text nobody saw.
    final displayed = notice;
    final record = ConsentRecord.of(
      displayed,
      DateTime.utc(2026, 8, 7),
      await displayed.hash(),
    );

    final recomputed = await consentContentHash(
      version: displayed.version,
      language: displayed.language,
      title: displayed.title,
      body: displayed.body,
    );

    expect(record.contentHash, recomputed);
  });

  test('a different language produces a different recorded hash', () async {
    const en = ConsentNotice(
      version: 4,
      language: 'en',
      title: 'শিরোনাম',
      body: 'বিষয়বস্তু',
    );

    expect(await en.hash(), isNot(await notice.hash()));
  });
}
```

**Also add a controller-level test** in the same file, driving `CaptureController` through a `ProviderContainer` with `noticeRepositoryProvider` overridden by a fake returning `Ok(notice)`, asserting: `loadNotice` populates `state.notice`; `acceptNotice()` populates `state.consent` and advances to `CaptureStep.positioning`; a repository `Err` sets `noticeBlocked` and leaves `step` at `purposeNotice`; and `selectNoticeLanguage('en')` re-resolves. Follow `test/core/auth/session_manager_test.dart`'s `ProviderContainer` + fake pattern.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/capture_consent_test.dart`

Expected: FAIL — `ConsentRecord.of` exists (Task 7) but `CaptureState.notice` / `consent` / `noticeBlocked` and the new controller methods do not.

- [ ] **Step 3: Expand `CaptureState`**

Add to `CaptureState` (and to `copyWith`): `final ConsentNotice? notice;`, `final ConsentRecord? consent;`, `final bool noticeBlocked;` (defaulting to `false`). **Remove `noticeLanguage`** — it is now `notice?.language`, and keeping both invites them to disagree.

- [ ] **Step 4: Rewrite the notice methods**

```dart
  /// Resolves the notice to show. Called when the notice step is entered and
  /// again when the language is switched.
  Future<void> loadNotice(String language) async {
    final result = await ref.read(noticeRepositoryProvider).resolve(language);
    if (result case Err()) {
      // Spec D7: consent fails CLOSED. Without a notice there is nothing to
      // show, and photographing someone without showing them one is a legal
      // defect — so capture stops here rather than proceeding blank.
      state = state.copyWith(noticeBlocked: true, notice: null);
      return;
    }
    state = state.copyWith(
      notice: result.fold((n) => n, (_) => null),
      noticeBlocked: false,
    );
  }

  /// Switches the notice's language. Independent of the app locale: the
  /// carpenter must understand the notice, and the field user's UI preference
  /// is irrelevant to that (T-2.3.3).
  Future<void> selectNoticeLanguage(String language) => loadNotice(language);

  /// Records consent for the notice currently displayed, then advances.
  ///
  /// Takes no language argument on purpose: the old signature let a caller
  /// record a language that did not match the text on screen.
  Future<void> acceptNotice() async {
    final shown = state.notice;
    if (shown == null) return; // nothing was displayed; nothing to consent to
    state = state.copyWith(
      step: CaptureStep.positioning,
      consent: ConsentRecord.of(shown, DateTime.now().toUtc(), await shown.hash()),
    );
  }
```

In `submit()`, add the four columns to `AttendanceDraftsCompanion.insert(...)`:

```dart
              consentVersion: Value(consent.version),
              consentLanguage: Value(consent.language),
              consentShownAt: Value(consent.shownAt),
              consentContentHash: Value(consent.contentHash),
```

and guard at the top of `submit()`: `final consent = state.consent; if (consent == null) return;` — a capture with no consent record must never reach the queue.

- [ ] **Step 5: Add the provider and update the screen**

In `lib/app/di/providers.dart`:

```dart
final noticeRepositoryProvider = Provider<NoticeRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return NoticeRepository(
    source: DioNoticeSource(ref.watch(dioProvider)),
    readCached: driftNoticeReader(db),
    writeCached: driftNoticeWriter(db),
  );
});
```

In `capture_flow_screen.dart`, have `_PurposeNotice` render `state.notice!.title` / `.body` instead of hardcoded text, call `loadNotice` on first build (defaulting to the app locale via `localeControllerProvider`, falling back to `'en'`), offer a language toggle wired to `selectNoticeLanguage`, and render a blocking message when `noticeBlocked` is true — with **no** path to the camera from that state.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/capture_consent_test.dart`

Expected: PASS. Then `flutter test test/widget/` to confirm no capture-flow widget test broke on the `noticeLanguage` removal.

- [ ] **Step 7: Confirm the TODO is gone**

```bash
grep -rn "TODO(T-0.5.2)" lib || echo "clean"
```

Expected: `clean`.

- [ ] **Step 8: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: all green; report the true count.

- [ ] **Step 9: Commit**

```bash
git add lib/features/camera_capture/ lib/app/di/providers.dart test/features/capture_consent_test.dart
git commit -m "feat: record the consent notice shown with each capture

acceptNotice() no longer takes a language: the old signature let a caller
record a language that did not match the text on screen. It now records a
ConsentRecord built from the notice actually displayed, including the hash -
the field the old TODO omitted, and the one that makes the record prove the
wording rather than point at a version.

If no notice can be resolved, capture is blocked with no path to the camera.
Photographing someone without showing them a notice is a legal defect, so
this is the one place in the epic where blocking the user is correct."
```

---

## Task 11: `AppConfig.locale` — the argument the flows always passed

**Files:**
- Modify: `lib/app/flavors.dart`
- Modify: `lib/core/l10n/locale_controller.dart`
- Create: `test/app/locale_dart_define_test.dart`

**Interfaces:**
- Consumes: `AppConfig`; `LocaleController.load()` (Task 5); `supportedLanguageCodes` (Task 4).
- Produces: `AppConfig.locale` (`String` — empty means unset); `LocaleController.load()` prefers a persisted choice, then the `LOCALE` dart-define, then the system.

- [ ] **Step 1: Write the failing test**

Create `test/app/locale_dart_define_test.dart`:

```dart
import 'package:acsl_campaign/app/flavors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppConfig exposes a locale from the LOCALE dart-define', () {
    // Every Maestro flow has always passed LOCALE as a launch argument and
    // AppConfig never read it — the harness was configuring something the app
    // ignored. P0.5 is the epic that makes it mean something.
    final config = AppConfig.fromEnvironment();

    // With no --dart-define=LOCALE at test time this is empty, which the
    // controller treats as "not specified".
    expect(config.locale, isA<String>());
    expect(config.locale, isEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/app/locale_dart_define_test.dart`

Expected: FAIL to compile — `AppConfig` has no `locale` member.

- [ ] **Step 3: Add the field**

In `lib/app/flavors.dart`, add `this.locale = ''` to the constructor, `final String locale;` as a field with a doc comment, and to `fromEnvironment()`:

```dart
      locale: const String.fromEnvironment('LOCALE'),
```

Document it: *"Language for E2E and provisioning (`--dart-define=LOCALE=bn`). Every Maestro flow already passes this; it was ignored until P0.5. A persisted user choice takes precedence."*

- [ ] **Step 4: Use it as the fallback in `LocaleController.load()`**

```dart
  Future<void> load() async {
    try {
      final persisted = await ref.read(localeStoreProvider).read();
      if (persisted != null) {
        state = persisted;
        return;
      }
    } catch (error) {
      debugPrint('Locale preference could not be loaded ($error).');
    }

    // No stored choice: honour --dart-define=LOCALE if it names a language we
    // support, else stay null and follow the system.
    final fromDefine = ref.read(appConfigProvider).locale;
    state = supportedLanguageCodes.contains(fromDefine)
        ? Locale(fromDefine)
        : null;
  }
```

Precedence is deliberate: a user's explicit choice beats a build-time define, which beats the system.

- [ ] **Step 5: Extend the controller test**

Add to `test/core/l10n/locale_controller_test.dart` a case overriding `appConfigProvider` with a config whose `locale` is `'bn'` and an empty store, asserting `load()` yields `Locale('bn')`; and another where the store holds `'en'` and the define says `'bn'`, asserting the **store wins**.

- [ ] **Step 6: Run and verify**

Run: `flutter test test/app/locale_dart_define_test.dart test/core/l10n/ && dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: all green; report the true count.

- [ ] **Step 7: Commit**

```bash
git add lib/app/flavors.dart lib/core/l10n/locale_controller.dart test/app/locale_dart_define_test.dart test/core/l10n/locale_controller_test.dart
git commit -m "feat: honour the LOCALE dart-define the E2E flows already pass

Every Maestro flow has passed LOCALE as a launch argument since it was
written, and AppConfig never read it - the harness was configuring something
the app ignored. Precedence is stored choice, then define, then system: a
user's explicit selection must beat a build-time default."
```

---

## Task 12: The `e2e` CI job — the epic's exit criterion

**Files:**
- Modify: `.github/workflows/ci.yml`
- Create: `.maestro/flows/locale_bengali.yaml`
- Modify: `.maestro/config.yaml`
- Modify: `TASK_BREAKDOWN.md`

**Interfaces:**
- Consumes: `AppConfig.locale` (Task 11); the `dev_launcher` semantics id the existing subflows assert; Android `applicationId` `com.acsl.campaign.dev`.
- Produces: a CI job named `e2e`; a new `android`-tagged flow.

**This task cannot be verified locally.** The sandbox produces 61 TLS errors building any APK and has no Maestro. **CI is the sole authority.** Do not claim the suite passes from a local run — report exactly what CI says.

- [ ] **Step 1: Write the Bengali flow**

Create `.maestro/flows/locale_bengali.yaml`:

```yaml
# P0.5: proves the localization chain closes in a REAL app process on a real
# Android surface, with the real font stack — which no widget test can do.
# Registering AppL10n's delegates was commented out from P0.2 until P0.5 and
# nothing noticed, so this is the guard at the outermost layer.
appId: ${APP_ID}
tags:
  - localization
  - android
---
- clearState
- launchApp:
    arguments:
      E2E: true
      LOCALE: bn
      ROLE: campaign_creator
- assertVisible:
    id: "dev_launcher"

# The app title comes from app_en.arb / app_bn.arb. In Bengali it must be the
# Bengali string, and the English one must be absent.
- assertVisible: "ক্যাম্পেইন ব্যবস্থাপনা"
- assertNotVisible: "Campaign Management"
```

Add `- flows/locale_bengali.yaml` to `.maestro/config.yaml`'s list.

Confirm against the running app that the Bengali `appTitle` is actually rendered somewhere reachable from `/dev`; if it is not, assert a status label that is, rather than weakening the flow to a trivial check.

- [ ] **Step 2: Add the `e2e` job**

In `.github/workflows/ci.yml`, after the `gate` job:

```yaml
  e2e:
    name: e2e (emulator)
    runs-on: ubuntu-latest
    # Only after the gate passes: booting an emulator to test code that does
    # not compile wastes ~15 minutes per run.
    needs: gate
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4

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

      - name: Generate localizations
        run: flutter gen-l10n

      - name: Run code generation
        run: dart run build_runner build --delete-conflicting-outputs

      - name: Install Maestro
        run: |
          curl -Ls "https://get.maestro.mobile.dev" | bash
          echo "$HOME/.maestro/bin" >> "$GITHUB_PATH"

      # KVM lets the emulator run with hardware acceleration; without it a
      # cold boot on a hosted runner is slow enough to hit the timeout.
      - name: Enable KVM
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' \
            | sudo tee /etc/udev/rules.d/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm

      - name: Run the Maestro suite on an emulator
        uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: 34
          arch: x86_64
          target: google_apis
          disable-animations: true
          script: |
            flutter build apk --debug --flavor dev --dart-define=E2E=true
            adb install -r build/app/outputs/flutter-apk/app-dev-debug.apk
            APP_ID=com.acsl.campaign.dev maestro test \
              --include-tags=android \
              .maestro/config.yaml

      # A red E2E run that leaves nothing to inspect is nearly impossible to
      # act on — the same reason the gate uploads golden diffs.
      - name: Upload Maestro output
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: maestro-output
          path: ~/.maestro/tests
          retention-days: 7
          if-no-files-found: ignore
```

Verify the APK path against what the build actually emits — the dev flavor's debug artifact name is what `adb install` needs, and guessing it wrong fails the job late.

- [ ] **Step 3: Correct `TASK_BREAKDOWN.md`'s T-0.1.4 row**

That row currently says the Maestro/emulator E2E job and a nightly suite were **"cancelled, not deferred."** Adding `e2e` reverses that, so append:

```markdown
**Correction (2026-08-07, P0.5):** the E2E job cancellation is **reversed**. P0.5 adds an `e2e` job that boots an Android emulator, installs the dev debug APK and runs the `android`-tagged Maestro flows; a green `e2e` is a hard exit criterion for that epic. The nightly suite remains cancelled.
```

Leaving both statements would make the document contradict itself — the same correction pattern P0.4 applied to this row's branch-protection claim.

- [ ] **Step 4: Push and let CI run**

```bash
git add .github/workflows/ci.yml .maestro/ TASK_BREAKDOWN.md
git commit -m "ci: gate P0.5 on a green emulator E2E suite

Adds an e2e job that boots an Android emulator, installs the dev debug APK
and runs the android-tagged Maestro flows. It runs after gate, because
booting an emulator to test code that does not compile wastes 15 minutes.

This reverses T-0.1.4's recorded 'cancelled, not deferred' decision, so that
row is corrected in the same commit rather than left contradicting this one.

The new locale_bengali flow asserts Bengali renders in a real app process on
a real Android surface with the real font stack - which no widget test can
do, and which is the outermost guard against the delegates being unregistered
as they were from P0.2 until now."
git push
```

- [ ] **Step 5: Report exactly what CI says**

Watch the run. Report the `e2e` job's true result — pass or fail, with the failing flow named if red. **Do not claim it passed without seeing it pass.**

If it is red, iterate: emulator boot races, install timing and animation waits are tuned against a real run, not predicted. Expect 10–15 minutes per attempt and expect the first attempt to need adjustment. A flow that proves irreducibly flaky is fixed or **explicitly quarantined with a recorded reason** — never silently dropped, and never by deleting the job.

- [ ] **Step 6: Close the epic once `e2e` is green**

Update the Epic P0.5 table in `TASK_BREAKDOWN.md` and add a closing note covering: the delegates were unregistered from P0.2 until now and nothing noticed; `l10nKey`'s five getters advertised keys for three families the ARB never had and could not have resolved against `gen-l10n` anyway; the 19 new Bengali values are **unreviewed machine drafts** needing native review; the notice hash's pre-image format is a contract; a published notice version must be **immutable** (a requirement on Legal/backend); locale is per-device; consent fails closed while locale degrades; and the ~150 screen-specific strings remain deferred to T-4.2.

```bash
git add TASK_BREAKDOWN.md
git commit -m "docs: close Epic P0.5"
git push
```

---

## Self-Review

**Spec coverage.** Every section maps to a task:

| Spec section | Task |
|---|---|
| §1 verified state (5 defects) | 1, 2, 3, 5 |
| §2 D1 scope | plan-wide; §9 records the deferral |
| §2 D2 bundled floor + override | 8 |
| §2 D3 record shape | 7, 9, 10 |
| §2 D4 per-device locale | 4, 5, 11 |
| §2 D5 typed extensions | 2 |
| §2 D6 marked machine drafts | 1 (test asserts the metadata) |
| §2 D7 fail-closed vs fail-open | 8, 10 (consent), 4, 5 (locale) |
| §3 deliverables 1–11 | 1–12 |
| §4.1 delegates, `null` == system, `pref:locale` | 3, 4, 5 |
| §4.2 five extensions, 19 keys | 1, 2 |
| §4.3 shapes, monotonic version, length-prefixed hash | 7 |
| §4.4 resolution, never-await, 🔒 seam, immutability | 8 |
| §4.5 schema v3, capture seam, language independence | 9, 10 |
| §5 error-handling table | 8, 10 (consent); 4, 5 (locale) |
| §6 all nine test files | 1–11 |
| §7 twelve sequence steps | Tasks 1–12 |
| §7.1 e2e exit criterion | 12 |
| §8 risks | mitigations embedded (Task 3 Step 5 goldens; Task 9 Step 1 v2-dump gate; Task 12 Steps 3, 5) |
| §9 out of scope | untouched |

**Type consistency verified across tasks.** ARB key names (1→2); `label(AppL10n)` on all five extensions (2→3, and available to any screen); `AppL10n.localizationsDelegates`/`supportedLocales`/`of` (3→6, 12); `LocaleStore.read/write/clear` + `localePrefKey` + `supportedLanguageCodes` (4→5, 11); `localeStoreProvider`/`localeControllerProvider`/`LocaleController.load/select` (5→6, 10, 11); `ConsentNotice(version/language/title/body)` + `.hash()` + `.toJson`/`fromJson`, `ConsentRecord.of(notice, shownAt, hash)`, `consentContentHash({version, language, title, body})` (7→8, 9, 10); `NoticeSource.fetchLatest`, `NoticeRepository({source, readCached, writeCached, loadAsset})` + `.resolve` + `.refreshInBackground` + `bundledAssetKey` (8→9, 10); `ConsentNotices` table and the four nullable `AttendanceDrafts` columns, `driftNoticeReader`/`driftNoticeWriter` (9→10); `noticeRepositoryProvider` (10); `AppConfig.locale` (11→12 via `--dart-define=LOCALE`); `APP_ID=com.acsl.campaign.dev` (12).

**Running test totals.** Baseline 256 passing / 29 skipped. T1 +4 → 260; T2 +11 → 271; T3 +3 → 274; T4 +7 → 281; T5 +6 → 287; T6 +2 → 289; T7 +7 → 296; T8 +9 → 305; T9 +4 → 309; T10 and T11 add tests whose exact count depends on the controller cases written, so **report the real number rather than trusting these**. My per-task counts have been wrong four times across previous epics; treat every figure as an expectation to verify.

**Three places where existing code, not this plan, is authoritative** — each has an explicit reconciliation step: Drift's generated `DatabaseAtV2` constructor form and companion parameter names (Task 9 Steps 2, 5); `RadioListTile`'s `groupValue`/`onChanged` versus `RadioGroup` on Flutter 3.44.8, where `crm_case_screen.dart` is the in-repo precedent (Task 6 Step 3); and the dev-flavor debug APK's emitted filename (Task 12 Step 2).

**One spec gap this plan closes rather than inherits:** §4.5 says `acceptNotice` records the consent, but that method is synchronous while resolution is async and the insert happens later in `submit()`. Task 10 resolves on entering the notice step, holds the resolved notice and the accepted record in `CaptureState`, drops `noticeLanguage` (which could disagree with the notice actually shown), and changes `acceptNotice()` to take no argument. That is a deliberate interface change, flagged in File Structure and in Task 10's preamble.

**One deliberate ordering choice:** `NoticeRepository` (Task 8) precedes schema v3 (Task 9) and takes its cache through function seams, so the resolution rule — the risky part — gets its own review gate separate from a migration. Task 9 then wires the real table into those seams.
