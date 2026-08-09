import 'package:acsl_campaign/core/l10n/locale_store.dart';
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
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

  test(
    'supported codes derive from the generated localizations, not a literal',
    () {
      // Guards the drift this deliberately avoids: a hardcoded {'en','bn'} would
      // silently ignore a third language's stored preference after it ships.
      expect(
        supportedLanguageCodes,
        AppL10n.supportedLocales.map((l) => l.languageCode).toSet(),
      );
      expect(supportedLanguageCodes, {'en', 'bn'});
    },
  );

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
