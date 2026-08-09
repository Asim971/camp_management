import 'dart:io';

import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/app/flavors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('acsl_root_');
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            flavor: Flavor.dev,
            apiBaseUrl: 'https://example.invalid',
            mediaHost: 'https://example.invalid',
          ),
        ),
        // ONLY the two directory seams. Everything else - the database, the
        // secure store, dio, the audit stack, the sync engine - is built for
        // real, which is the entire point of this file.
        databaseDirectoryProvider.overrideWithValue(() async => dir.path),
        tempDirectoryPathProvider.overrideWithValue(() async => dir.path),
      ],
    );
  });

  tearDown(() async {
    // Explicitly await the close before disposing the container. `ref.onDispose
    // (db.close)` in providers.dart hands ProviderContainer.dispose() a
    // Future<void> Function() where it expects void Function(); Dart accepts
    // the assignment (return-type covariance to void) but dispose() then never
    // awaits the Future, so the native sqlite handle can still be open when
    // dir.delete() runs immediately after. POSIX allows unlinking an open
    // file, which hides this; Windows does not, and throws
    // PathAccessException here without this explicit await. drift's close()
    // is idempotent, so onDispose calling it again during container.dispose()
    // below is a safe no-op.
    await container.read(appDatabaseProvider).close();
    container.dispose();
    await dir.delete(recursive: true);
  });

  test('the real database opens, migrates and answers a query', () async {
    // THE load-bearing assertion. Resolving appDatabaseProvider proves almost
    // nothing (Riverpod construction is lazy and drift defers the open), so this
    // QUERIES it: open() runs, the v1->v2->v3 chain runs, schema v3 is reached.
    final db = container.read(appDatabaseProvider);

    final version = await db.customSelect('PRAGMA user_version;').getSingle();
    expect(version.data.values.first, 3);

    // And the v3 tables are really there, not merely the version number.
    expect(await db.select(db.consentNotices).get(), isEmpty);
    expect(await db.select(db.syncTasks).get(), isEmpty);
  });

  test('every core provider builds against the real graph', () {
    // DELIBERATELY WEAK, and labelled so no future reader mistakes it for
    // coverage: all 24 of these build today with only appConfigProvider
    // overridden, because construction is lazy. It catches a broken dependency
    // or the authService -> dio -> authState -> sessionManager cycle failing to
    // resolve - nothing more. The real guarantee is the query test above.
    final probes = <String, void Function()>{
      'authService': () => container.read(authServiceProvider),
      'tokenStore': () => container.read(tokenStoreProvider),
      'sessionManager': () => container.read(sessionManagerProvider),
      'authState': () => container.read(authStateProvider),
      'dio': () => container.read(dioProvider),
      'campaignRepository': () => container.read(campaignRepositoryProvider),
      'appDatabase': () => container.read(appDatabaseProvider),
      'evidenceStore': () => container.read(evidenceStoreProvider),
      'noticeRepository': () => container.read(noticeRepositoryProvider),
      'secureStore': () => container.read(secureStoreProvider),
      'auditTransport': () => container.read(auditTransportProvider),
      'auditFlusher': () => container.read(auditFlusherProvider),
      'auditSink': () => container.read(auditSinkProvider),
      'evidenceKeyStore': () => container.read(evidenceKeyStoreProvider),
      'mediaEncryptor': () => container.read(mediaEncryptorProvider),
      'faceQualityChecker': () => container.read(faceQualityCheckerProvider),
      'captureSource': () => container.read(captureSourceProvider),
      'syncUploader': () => container.read(syncUploaderProvider),
      'verificationRepository': () =>
          container.read(verificationRepositoryProvider),
      'registrationRepository': () =>
          container.read(registrationRepositoryProvider),
      'sessionRepository': () => container.read(sessionRepositoryProvider),
      'importRepository': () => container.read(importRepositoryProvider),
      'connectivityStream': () => container.read(connectivityStreamProvider),
      'syncEngine': () => container.read(syncEngineProvider),
    };

    final failures = <String>[];
    probes.forEach((name, probe) {
      try {
        probe();
      } catch (error) {
        failures.add('$name: $error');
      }
    });

    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
