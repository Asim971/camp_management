import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    return MaterialApp.router(
      title: 'ACSL Campaign Management',
      debugShowCheckedModeBanner: false,
      theme: bmdTheme(brightness: Brightness.light),
      darkTheme: bmdTheme(brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: router,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      // Codegen emits supportedLocales alphabetically ([bn, en]), and Flutter's
      // default resolution returns supportedLocales.first when the device locale
      // matches nothing supported — which would hand a French phone Bengali
      // purely because 'bn' sorts before 'en'. English is the deliberate
      // fallback; en and bn devices still resolve by exact language match here.
      localeListResolutionCallback: (deviceLocales, supported) {
        for (final device in deviceLocales ?? const <Locale>[]) {
          for (final candidate in supported) {
            if (candidate.languageCode == device.languageCode) return candidate;
          }
        }
        return const Locale('en');
      },
    );
  }
}
