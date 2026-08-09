import 'dart:io';

import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the seams default to null, so production behaviour is unchanged', () {
    // If either default were non-null, a test directory could ship to a device.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(databaseDirectoryProvider), isNull);
    expect(container.read(tempDirectoryPathProvider), isNull);
  });

  test('open() honours an injected directory and can be queried', () async {
    // The point of the seam: a REAL AppDatabase.open() - not
    // NativeDatabase.memory() - running open() and the whole v1->v2->v3
    // migration chain against a real file on disk.
    final dir = await Directory.systemTemp.createTemp('acsl_seam_');
    addTearDown(() => dir.delete(recursive: true));

    final db = AppDatabase.open(
      databaseDirectory: () async => dir.path,
      // Required as well: drift_flutter otherwise calls
      // getTemporaryDirectory(), which has no plugin under flutter_test.
      tempDirectoryPath: () async => dir.path,
    );
    addTearDown(db.close);

    final row = await db.customSelect('PRAGMA user_version;').getSingle();
    expect(row.data.values.first, 3);
    expect(File('${dir.path}/acsl_campaign.sqlite').existsSync(), isTrue);
  });
}
