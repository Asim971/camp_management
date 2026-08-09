# Storage tiers

**Status:** adopted in Epic P0.6 (T-0.6.1), spec decision **D6**, deliverable **D-F**.
**Source:** `docs/superpowers/specs/2026-08-09-epic-p0-6-composition-root-design.md` §2, §4 D-F.

This document exists because storage on this project was being planned around the
five tables that happened to exist, rather than around what the 32 feature PRDs
require. The schema will roughly double. What is needed before that happens is
not the tables — most of their contracts are still blocked — but the **tiering
and the conventions**, so each feature adds its table without reinventing the
rules.

---

## The five tiers

Every persisted thing belongs to **exactly one** tier.

| Tier | Contents | Eviction | Encrypted | Platform |
|---|---|---|---|---|
| **Durable outbound** | `sync_tasks`, `audit_events` | never automatically; only after server confirmation, or after the documented permanent-rejection rule | payload-level where it carries personal data | both |
| **Evidence** | encrypted capture files + `attendance_drafts` rows | only after server confirmation **and** retention policy (P0.4.3 owner: media/security) | yes, at rest (Keystore key) | mobile |
| **Evictable cache** | server-derived reads: rosters, assignments, configuration versions | freely, with a freshness stamp so staleness is visible | no | both |
| **Preference** | device settings such as `pref:locale` | **never** | no | both |
| **Secret** | tokens, evidence keys — `SecureStore`, never Drift | on sign-out per the existing generation rules | platform-backed | both |

Tier is a property of the **table**, not of the row. That is the whole lesson of
the split below: a tier enforced by a key-prefix convention inside a shared
table is enforced by nothing.

---

## Rule: table or blob?

> A thing earns its own Drift table when it is **searched, sorted, or counted**,
> or when more than one access pattern reads it. Otherwise a `cached_references`
> row is enough.

**F8 is exactly this rule violated, and fixing it is a required P0.14 change.**
`lib/data/registration/registration_repository_impl.dart` stores an entire
session roster as **one JSON blob** in `cached_references`, and `searchCached`
decodes that whole blob and filters in Dart on every query. P0.14 requires
search "by name, carpenter ID and approved phone suffix" and requires the app to

> "return local search results quickly under offline field conditions"

— which a full parse per keystroke with no index will not do at session scale.
The roster is searched by three fields, so it needed a table from the start.
An indexed roster table replacing the blob is **a required P0.14 fix**, not an
optimisation, and it is listed as such below.

---

## The split, as built in P0.6

`cached_references` now keeps **evictable server caches only**.

Preferences moved to their own `preferences` table (`key` TEXT PK, `value` TEXT)
at **schema v4**, so a future cache sweep — which P0.4.3 (*"clear protected
cached media according to policy"*) and P1.7 (retention execution) both imply —
cannot delete a user's settings.

Why a table rather than the `pref:` key prefix P0.5 used (F9): the prefix was
enforced by a comment. With configuration caches, assignment snapshots and
rosters all arriving in `cached_references`, whoever writes the first
`DELETE FROM cached_references` would have taken the user's chosen language with
it. A separate table makes that mistake unrepresentable.

**What the migration does.** `from3To4` creates `preferences`, copies every
`pref:%` row across, then deletes those rows from `cached_references`. The value
is copied **verbatim**, so `DriftLocaleStore` reads P0.5's
`{"languageCode":"bn"}` blob as well as the bare code it now writes; without
that, every device upgrading from v3 would have silently reverted to the system
language. `localePrefKey` remains the literal `'pref:locale'` — renaming it
would abandon the stored preference on every installed device.

**What the tests assert** (`test/core/storage/migration_test.dart`):

- a cache sweep (`DELETE FROM cached_references`) leaves `preferences` intact;
- `pref:locale` survives v3→v4 **with its value**, and still resolves to
  `Locale('bn')` through `DriftLocaleStore`;
- a queued capture and its sync task survive v3→v4 — this is the first
  migration that deletes rows at all;
- the step **survives being re-run** over its own half-finished output.

The value and `read()` assertions are not decoration. `migrateAndValidate`
compares **shapes only**: with the `INSERT` removed, the shape test
`migrates v3 to v4` still passes while the preference is gone. Only the data
assertion catches it. Any future migration in this repo needs its own
data-survival assertion for the same reason.

### Every migration step must be idempotent

Drift does **not** wrap migration steps in a transaction:
`VersionedSchema.stepByStepHelper` calls `runMigrationSteps` bare, and drift's own
doc comment there shows the transaction as something the *caller* adds. And
`user_version` is bumped only after the whole `onUpgrade` returns. So each
statement in a step autocommits alone, and a process kill part-way through leaves
the device **durably on the old version with the work so far already committed**.
The next launch starts the step over. Web-wasm makes a mid-migration reload
likelier still.

The consequence is worse than losing a row. `from3To4` originally used a plain
`INSERT INTO preferences … SELECT`; re-run over its own already-inserted row it
raises `SqliteException(1555): UNIQUE constraint failed: preferences.key`, which
throws out of `beforeOpen` — so the database fails to open on that launch **and
every launch after**, because the version never advances. Queued attendance
evidence becomes *unreachable* rather than deleted, with no in-app recovery path.

It uses `INSERT OR REPLACE` instead. `ON CONFLICT(key) DO UPDATE` would work too,
but OR REPLACE has no SQLite version floor (upsert needs 3.24+) and no
INSERT-SELECT/ON-CONFLICT parse ambiguity, and the statement has to hold on
Android, iOS and web-wasm alike.

So: `createTable` is safe already (drift emits `CREATE TABLE IF NOT EXISTS`),
`DELETE … WHERE` is safe by construction, and any `INSERT`, `ALTER` or backfill
needs to be made re-runnable on purpose. Do not rely on transaction semantics
inside `beforeOpen`.

---

## Forward-flagged, not built here

Each lands with its feature, against the tiers above. Their contracts are still
blocked, so building them now would mean guessing their shapes.

| Coming | Tier | Owner | Requirement it must satisfy |
|---|---|---|---|
| Session assignment / readiness snapshot | evictable cache | P0.13 | offline-ready rather than blocked with no network |
| **Indexed roster table (replacing the blob)** | evictable cache | P0.14 | searchable by name / ID / phone suffix, fast offline — **fixes F8; required, not optional** |
| Notice outcome: refusal + manual route | evidence | P0.3.3 / P0.15 | every capture resolves to the exact version *and outcome* presented |
| Attempt lineage | evidence | P0.19 | remaining-attempt count and new-attempt lineage |
| Configuration version cache + event pinning | evictable cache | P1.5 | historical resolution of the effective version |
| Audit reconciliation status | durable outbound | P0.4.2 | buffered events reconcile with the server |
| Media retention / cleanup | evidence | P0.4.3 | protected cached media cleared per policy |

---

## Adding a table: the checklist

1. **Name its tier** in the class doc comment. If it does not fit one of the
   five, the tier list is wrong — fix this document, do not improvise a sixth.
2. **Apply the table-or-blob rule.** Searched, sorted, counted, or read by more
   than one access pattern → its own table.
3. **Bump `schemaVersion`** and add a `fromNToM` step. Regenerate in this order
   (`schema steps` builds from the JSON dumps on disk, so the dump must come
   first, and `fromNToM` does not exist as a named argument until after it):

   ```
   dart run build_runner clean
   dart run build_runner build --delete-conflicting-outputs
   dart run drift_dev schema dump lib/core/storage/app_database.dart drift_schemas/
   dart run drift_dev schema steps drift_schemas/ lib/core/storage/schema_versions.dart
   dart run build_runner build --delete-conflicting-outputs
   dart run drift_dev schema generate --data-classes --companions drift_schemas/ test/generated/
   ```

   `--data-classes --companions` are **required**: without them `schema generate`
   rewrites the committed `test/generated/schema_v1..vN.dart` files and strips
   their data classes, breaking every existing migration test.
4. **Write a data-survival assertion**, not just `migrateAndValidate`. Probe it
   by deleting the data-carrying statement from your migration and confirming
   the test fails.
5. **Make every statement idempotent and test the retry** — construct the
   half-applied state and assert the step recovers. See
   "Every migration step must be idempotent" above; drift gives you no
   transaction, so a kill mid-step can otherwise brick the database permanently.
6. **Update both `PRAGMA user_version` assertions** —
   `test/app/di/composition_root_test.dart` and
   `test/core/storage/database_seam_test.dart`. They are the two places that
   notice a migration step was never wired up.
