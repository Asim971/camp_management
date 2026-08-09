import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/locale_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'router/app_router.dart';
import 'theme/bmd_theme.dart';

/// Root widget. Wires the BMD theme (light/dark), localization (en/bn) and the
/// guarded router. Theme mode follows the system; the app is fully bilingual
/// (Guideline §4.3, §13).
class AcslCampaignApp extends ConsumerWidget {
  const AcslCampaignApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // null means "follow the system", which is exactly what a null `locale:`
    // means to MaterialApp — no special-casing needed for a first launch on a
    // Bengali device (spec D4). Watched, not read, so the language picker
    // changes the app without a restart.
    final locale = ref.watch(localeControllerProvider);

    return MaterialApp.router(
      title: 'ACSL Campaign Management',
      debugShowCheckedModeBanner: false,
      theme: bmdTheme(brightness: Brightness.light),
      darkTheme: bmdTheme(brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: router,
      locale: locale,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      // Codegen emits supportedLocales alphabetically ([bn, en]), and Flutter's
      // default resolution returns supportedLocales.first when the device locale
      // matches nothing supported — which would hand a French phone Bengali
      // purely because 'bn' sorts before 'en'. English is the deliberate
      // fallback; en and bn devices still resolve by exact language match here.
      // Named `preferred` rather than `deviceLocales` because `locale:` above
      // changes what WidgetsApp passes here: with an explicit locale set it
      // hands over [locale] instead of the platform's list, so the user's
      // stored choice resolves through this same code path.
      localeListResolutionCallback: (preferred, supported) {
        for (final wanted in preferred ?? const <Locale>[]) {
          for (final candidate in supported) {
            if (candidate.languageCode == wanted.languageCode) return candidate;
          }
        }
        return const Locale('en');
      },
    );
  }
}
