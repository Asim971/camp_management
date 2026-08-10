import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di/providers.dart';
import 'locale_store.dart';

final localeStoreProvider = Provider<LocaleStore>(
  (ref) => DriftLocaleStore(ref.watch(appDatabaseProvider)),
);

/// The app's current locale. `null` means follow the system, which is exactly
/// what a null `locale:` means to `MaterialApp` — so a Bengali-configured
/// device with nothing persisted is correct on first launch with no
/// special-casing (spec D4).
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() => null;

  /// Adopts any persisted preference. Called once at boot.
  ///
  /// Precedence is stored choice, then the `LOCALE` dart-define, then the
  /// system: a user's explicit selection must beat a build-time default, and a
  /// build-time default must beat the device.
  ///
  /// [onDegraded] is called if the stored preference could not be read. It
  /// exists because this method never throws (spec D7: a display preference
  /// must not block startup), which means `bootstrap`'s `step()` wrapper - whose
  /// only signal is a thrown error - cannot see this failure at all. Without a
  /// channel out, a user's persisted Bengali choice is silently discarded and
  /// nothing is recorded: guarded but silent, the shape P0.6 removes. Callers
  /// that do not care may omit it; `bootstrap` records it on `BootDiagnostics`.
  Future<void> load({void Function(Object error)? onDegraded}) async {
    try {
      final persisted = await ref.read(localeStoreProvider).read();
      if (persisted != null) {
        state = persisted;
        return;
      }
    } catch (error) {
      // A display preference must never block startup (spec D7). Falling
      // through rather than returning is deliberate: a storage fault should
      // still leave a LOCALE-provisioned build in its intended language.
      debugPrint('Locale preference could not be loaded ($error).');
      onDegraded?.call(error);
    }

    // No stored choice: honour --dart-define=LOCALE if it names a language we
    // support, else stay null and follow the system. `supportedLanguageCodes`
    // is derived from the ARB-generated supportedLocales, so an absent define
    // ('') and an unsupported one ('fr') both correctly fall through.
    final fromDefine = ref.read(appConfigProvider).locale;
    state = supportedLanguageCodes.contains(fromDefine)
        ? Locale(fromDefine)
        : null;
  }

  /// Applies [locale] and persists it. `null` returns to the system locale
  /// and clears the stored preference.
  Future<void> select(Locale? locale) async {
    state = locale;
    try {
      // Read inside the try: localeStoreProvider builds a DriftLocaleStore over
      // appDatabaseProvider, and opening that database can itself throw (web
      // without the Drift wasm assets, a corrupt file). Outside the try that
      // would escape as an unhandled async error to whoever called select() —
      // the language picker — after `state` had already been mutated.
      final store = ref.read(localeStoreProvider);
      if (locale == null) {
        await store.clear();
      } else {
        await store.write(locale);
      }
    } catch (error) {
      // The choice still applies for this session; it just will not survive
      // a restart. Honouring the user's immediate intent is the right call.
      debugPrint('Locale preference could not be saved ($error).');
    }
  }
}

final localeControllerProvider = NotifierProvider<LocaleController, Locale?>(
  LocaleController.new,
);
