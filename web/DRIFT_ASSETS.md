# Drift web assets

`sqlite3.wasm` and `drift_worker.js` are binary/generated artifacts that Drift
needs to run on web. They are committed rather than fetched at build time so
`flutter run -d chrome` works with no extra setup, which is drift's own
documented approach.

| Asset | Source | Version |
|---|---|---|
| `sqlite3.wasm` | <https://github.com/simolus3/sqlite3.dart/releases/tag/sqlite3-2.9.4> | `sqlite3-2.9.4` (matches the installed `sqlite3` Dart package, pinned via `sqlite3` in `pubspec.lock`) |
| `drift_worker.js` | <https://github.com/simolus3/drift/releases/tag/drift-2.28.2> | `drift-2.28.2` (matches the installed `drift` package in `pubspec.lock`) |

**Refresh them whenever `drift` is upgraded.** `test/app/web_assets_test.dart`
catches deletion or a truncated download; it cannot detect a version mismatch,
so this file is the checkpoint. A mismatch typically shows up as a runtime
failure in the browser, not a build error.
