# Drift web assets

`sqlite3.wasm` and `drift_worker.js` are binary/generated artifacts that Drift
needs to run on web. They are committed rather than fetched at build time so
`flutter run -d chrome` works with no extra setup, which is drift's own
documented approach.

| Asset | Source | Version | Bytes | sha256 |
|---|---|---|---|---|
| `sqlite3.wasm` | <https://github.com/simolus3/sqlite3.dart/releases/tag/sqlite3-2.9.4> | `sqlite3-2.9.4` (matches the installed `sqlite3` Dart package, pinned via `sqlite3` in `pubspec.lock`) | 730,989 | `922a76b182b6af69b030c8e2fdd3283ecc8e827248b20e4b1f3f3db170b52117` |
| `drift_worker.js` | <https://github.com/simolus3/drift/releases/tag/drift-2.28.2> | `drift-2.28.2` (matches the installed `drift` package in `pubspec.lock`) | 355,547 | `6372cb95370e8698afbc594011c2d91cf6d8afea8c9122c25da60013c4eac610` |

**Refresh them whenever `drift` is upgraded.** `test/app/web_assets_test.dart`
catches deletion or a truncated download; it cannot detect a version mismatch,
so this file is the checkpoint. A mismatch typically shows up as a runtime
failure in the browser, not a build error.

The hashes above are the committed bytes, and were confirmed against the
`web-build` artifact of the CI run that merged PR #4 — the two files ship into
`build/web` unchanged. They are verifiable on any platform only because
`.gitattributes` marks both `-text`; without that pin, a Windows checkout
double-converts `drift_worker.js`'s existing CRLF endings to CRCRLF and every
hash here fails locally while passing in CI. See `.gitattributes` for why the
repo's own size tripwire cannot catch that.
