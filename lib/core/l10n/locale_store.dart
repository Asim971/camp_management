import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;

import '../../l10n/generated/app_localizations.dart';
import '../storage/app_database.dart';

/// Reserved key for the device's language preference.
///
/// The `pref:` prefix is retained even though preferences now have their own
/// table: it is the literal key stored on every device that ran P0.5, and the
/// v3→v4 migration carries the row across by that key. NEVER rename — a rename
/// abandons the stored preference on every installed device.
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

/// Drift-backed store over the `preferences` table.
///
/// Deliberately NOT `cached_references`, which is where P0.5 put it. That table
/// is an evictable cache of server-derived reads, and the cache sweeps P0.4.3
/// and P1.7 imply would have deleted the user's language. The `pref:` key
/// prefix that was supposed to prevent that was enforced by a comment only;
/// a separate table makes the mistake unrepresentable (spec D6, F9).
class DriftLocaleStore implements LocaleStore {
  DriftLocaleStore(this._db);

  final AppDatabase _db;

  @override
  Future<Locale?> read() async {
    try {
      final row = await (_db.select(
        _db.preferences,
      )..where((t) => t.key.equals(localePrefKey))).getSingleOrNull();
      if (row == null) return null;

      final code = _languageCodeOf(row.value);
      if (code == null || !supportedLanguageCodes.contains(code)) return null;
      return Locale(code);
    } catch (error) {
      // A malformed row or a failed read must degrade to "follow the system",
      // never crash startup: this is a display preference, not a compliance
      // control.
      debugPrint('Stored locale could not be read ($error). Using system.');
      return null;
    }
  }

  /// The language code in a stored preference value, or null if there is none.
  ///
  /// Accepts two encodings on purpose:
  /// - the bare code (`bn`), which is what [write] stores;
  /// - P0.5's `{"languageCode":"bn"}` blob, which is what the v3→v4 migration
  ///   carries across verbatim from `cached_references.value_json`.
  ///
  /// Dropping the second would mean every device that upgrades from v3 silently
  /// loses its language — the exact loss the tier split exists to prevent. The
  /// row is normalised to the bare code the next time [write] runs.
  String? _languageCodeOf(String value) {
    if (!value.startsWith('{')) return value;
    final Object? decoded = jsonDecode(value);
    // Narrowed to `Object?` values rather than a raw `Map` so the lookup below
    // is statically typed instead of a dynamic call.
    if (decoded is! Map<String, Object?>) return null;
    final code = decoded['languageCode'];
    return code is String ? code : null;
  }

  @override
  Future<void> write(Locale locale) => _db
      .into(_db.preferences)
      .insertOnConflictUpdate(
        PreferencesCompanion.insert(
          key: localePrefKey,
          value: locale.languageCode,
        ),
      );

  @override
  Future<void> clear() => (_db.delete(
    _db.preferences,
  )..where((t) => t.key.equals(localePrefKey))).go();
}
