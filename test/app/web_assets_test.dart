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
    expect(wasm.readAsBytesSync().take(4).toList(), [0x00, 0x61, 0x73, 0x6d]);
    expect(worker.lengthSync(), greaterThan(1000));
    expect(worker.readAsStringSync(), isNot(startsWith('<')));
  });
}
