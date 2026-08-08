import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;

import '../../l10n/generated/app_localizations.dart';
import '../storage/app_database.dart';

/// Reserved key for the device's language preference.
///
/// The `pref:` prefix marks rows in `cached_reference` that are user
/// preferences rather than cached server data, so a future cache-eviction
/// sweep can exclude them by prefix instead of silently wiping the user's
/// language choice. NEVER rename: a rename abandons the stored preference on
/// every installed device.
const String localePrefKey = 'pref:locale';

/// Languages this build can honour, derived from the generated localizations so
/// it cannot drift from the ARB files. A stored value outside this set is
/// treated as unset rather than applied — it is what a preference written by a
/// future build that supported more languages looks like to this one.
Set<String> get supportedLanguageCodes =>
    AppL10n.supportedLocales.map((l) => l.languageCode).toSet();

/// The device's language preference. `null` means "follow the system".
///
/// Persisted per device, not per user: a shared field phone in a
/// Bengali-speaking territory should stay Bengali regardless of who signs in
/// (spec D4).
abstract interface class LocaleStore {
  Future<Locale?> read();
  Future<void> write(Locale locale);
  Future<void> clear();
}

/// Drift-backed store over the existing `cached_reference` table.
///
/// Reuses that table rather than adding `shared_preferences` for one string:
/// Drift is already a dependency and the table's purpose is durable key-value
/// for non-authoritative data. The cost is that `fetchedAt` is a poor name for
/// a preference's write time — accepted deliberately over a new dependency or
/// a whole new table.
class DriftLocaleStore implements LocaleStore {
  DriftLocaleStore(this._db);

  final AppDatabase _db;

  @override
  Future<Locale?> read() async {
    try {
      final row = await (_db.select(
        _db.cachedReferences,
      )..where((t) => t.key.equals(localePrefKey))).getSingleOrNull();
      if (row == null) return null;

      final decoded = jsonDecode(row.valueJson);
      // Narrowed to `Object?` values rather than a raw `Map` so the lookup
      // below is statically typed instead of a dynamic call.
      if (decoded is! Map<String, Object?>) return null;
      final code = decoded['languageCode'];
      if (code is! String || !supportedLanguageCodes.contains(code)) {
        return null;
      }
      return Locale(code);
    } catch (error) {
      // A malformed row or a failed read must degrade to "follow the system",
      // never crash startup: this is a display preference, not a compliance
      // control.
      debugPrint('Stored locale could not be read ($error). Using system.');
      return null;
    }
  }

  @override
  Future<void> write(Locale locale) => _db
      .into(_db.cachedReferences)
      .insertOnConflictUpdate(
        CachedReferencesCompanion.insert(
          key: localePrefKey,
          valueJson: jsonEncode({'languageCode': locale.languageCode}),
          fetchedAt: DateTime.now().toUtc(),
        ),
      );

  @override
  Future<void> clear() => (_db.delete(
    _db.cachedReferences,
  )..where((t) => t.key.equals(localePrefKey))).go();
}
