import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Registers a golden test that runs only on Linux.
///
/// Font rasterisation differs enough between platforms that a baseline
/// captured on one is not trustworthy on another, so CI's `ubuntu-latest`
/// runner is the single authority. On Windows and macOS these report as
/// skipped rather than failing, which keeps `flutter test` both green and
/// honest during local development.
void goldenTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, body, skip: !Platform.isLinux);
}
