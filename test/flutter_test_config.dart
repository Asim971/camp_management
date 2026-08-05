import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled variable fonts for every test under `test/`.
///
/// Without this, `flutter test` renders all text in the placeholder font, where
/// every glyph is an identical box — which makes typography and Bangla
/// line-wrapping invisible to a golden baseline.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> load(String family, String path) async {
    final loader = FontLoader(family)
      ..addFont(
        File(path).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
      );
    await loader.load();
  }

  await load('Inter', 'assets/fonts/Inter-Variable.ttf');
  await load('NotoSansBengali', 'assets/fonts/NotoSansBengali-Variable.ttf');

  await testMain();
}
