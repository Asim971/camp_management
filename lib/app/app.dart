import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      // Generated from lib/l10n/*.arb once `flutter gen-l10n` runs.
      // localizationsDelegates: AppL10n.localizationsDelegates,
      // supportedLocales: AppL10n.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('bn')],
    );
  }
}
