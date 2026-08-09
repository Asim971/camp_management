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
    expect(
      worker.existsSync(),
      isTrue,
      reason: 'web/drift_worker.js is missing',
    );

    // A wasm module starts with the magic bytes \0asm. A downloaded 404 page
    // would satisfy existsSync() and fail here.
    final wasmBytes = wasm.readAsBytesSync();
    expect(wasmBytes.take(4).toList(), [0x00, 0x61, 0x73, 0x6d]);
    // The committed file is 730,989 bytes. A network-truncated download keeps
    // the magic-byte header intact but cuts the body short, which the magic
    // byte check above cannot catch. 500,000 is comfortably below the real
    // size (so a genuine future sqlite3 version bump won't trip this) and
    // comfortably above what a truncated/aborted download would leave behind.
    expect(wasmBytes.length, greaterThan(500000));

    expect(worker.lengthSync(), greaterThan(1000));
    // Assert what the file actually is (compiled Dart, emitted by dart2js/
    // dart2wasm tooling), not merely what it isn't. A JSON error body or a
    // plain-text CDN error longer than 1000 bytes would slip past a check
    // that only excludes strings starting with '<'.
    expect(worker.readAsStringSync(), startsWith('(function dartProgram(){'));
  });
}
