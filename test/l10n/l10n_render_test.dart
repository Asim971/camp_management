import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/domain/common/status_labels.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // These tests cover the chain ARB -> codegen -> delegate -> widget: only a
  // rendered Bengali glyph proves it actually closes, and the bundled Noto Sans
  // Bengali font (loaded for the whole tree by test/flutter_test_config.dart)
  // is what makes these real glyphs rather than Ahem boxes.
  //
  // They deliberately register the delegates on their own MaterialApp, so they
  // say nothing about whether `lib/app/app.dart` registers them — which is the
  // wiring that sat commented out from P0.2 through P0.4. That claim belongs to
  // test/app/l10n_wiring_test.dart, which pumps the real AcslCampaignApp.
  Widget harness(Locale locale) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    home: Builder(
      builder: (context) =>
          Text(CampaignStatus.draft.label(AppL10n.of(context))),
    ),
  );

  testWidgets('renders English for Locale(en)', (tester) async {
    await tester.pumpWidget(harness(const Locale('en')));
    expect(find.text('Draft'), findsOneWidget);
  });

  testWidgets('renders Bengali for Locale(bn)', (tester) async {
    await tester.pumpWidget(harness(const Locale('bn')));
    expect(find.text('খসড়া'), findsOneWidget);
    expect(find.text('Draft'), findsNothing);
  });

  testWidgets('AppL10n.supportedLocales offers exactly bn then en', (
    tester,
  ) async {
    // Ordered, not a Set: codegen emits these alphabetically, and the order is
    // load-bearing because Flutter's default resolution returns
    // supportedLocales.first for an unsupported device locale. What keeps that
    // fallback English rather than Bengali is the localeListResolutionCallback
    // in lib/app/app.dart — see test/app/l10n_wiring_test.dart. If a new ARB
    // ever sorts ahead of 'bn', this assertion is the tripwire.
    expect(AppL10n.supportedLocales, const [Locale('bn'), Locale('en')]);
  });
}
