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
    // Frozen because it is the literal key stored on every device that ran
    // P0.5, and the v3->v4 migration carries the row across by that key. The
    // `pref:` prefix is kept for the same reason: renaming it would abandon the
    // stored preference on every installed device. The prefix is no longer the
    // thing protecting the preference from a cache sweep - a separate table is.
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
    final rows = await db.select(db.preferences).get();
    expect(rows.where((r) => r.key == localePrefKey), hasLength(1));
  });

  test('the preference does not land in the evictable cache', () async {
    // The tier split, asserted at the write site. If this ever regresses, the
    // first cache sweep deletes the user's language (spec F9).
    await DriftLocaleStore(db).write(const Locale('bn'));

    expect(await db.select(db.cachedReferences).get(), isEmpty);
    expect(await db.select(db.preferences).get(), hasLength(1));
  });

  test("a v3 device's migrated JSON value is still honoured", () async {
    // P0.5 stored `{"languageCode":"bn"}` in cached_references.value_json, and
    // the v3->v4 migration copies that value verbatim. If read() understood
    // only the bare code it now writes, every upgrading device would silently
    // fall back to the system language - the exact loss this epic prevents.
    await db
        .into(db.preferences)
        .insert(
          PreferencesCompanion.insert(
            key: localePrefKey,
            value: '{"languageCode":"bn"}',
          ),
        );

    expect(await DriftLocaleStore(db).read(), const Locale('bn'));
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
    //
    // Both malformed shapes are covered because they take different paths now
    // that `value` holds a bare code: a value starting with `{` is parsed as
    // P0.5's legacy blob and can THROW out of jsonDecode (only the try/catch
    // saves it), while unparseable garbage is simply an unsupported code.
    Future<void> store(String value) => db
        .into(db.preferences)
        .insertOnConflictUpdate(
          PreferencesCompanion.insert(key: localePrefKey, value: value),
        );

    await store('{"languageCode":"bn"'); // truncated legacy blob
    expect(await DriftLocaleStore(db).read(), isNull);

    await store('not-json{{{');
    expect(await DriftLocaleStore(db).read(), isNull);
  });

  test('an unsupported language code returns null', () async {
    // Guards against a stored value from a future build that supported more
    // languages than this one does. Asserted in both stored encodings.
    await db
        .into(db.preferences)
        .insert(PreferencesCompanion.insert(key: localePrefKey, value: 'fr'));
    expect(await DriftLocaleStore(db).read(), isNull);

    await db
        .into(db.preferences)
        .insertOnConflictUpdate(
          PreferencesCompanion.insert(
            key: localePrefKey,
            value: '{"languageCode":"fr"}',
          ),
        );
    expect(await DriftLocaleStore(db).read(), isNull);
  });
}
