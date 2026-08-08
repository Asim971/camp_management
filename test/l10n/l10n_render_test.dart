import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/domain/common/status_labels.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // This is the test whose absence let commented-out delegates survive since
  // P0.2. "The delegates are registered" is a claim about wiring; only a
  // rendered Bengali glyph proves the chain ARB -> codegen -> delegate ->
  // widget actually closes. The bundled Noto Sans Bengali font (loaded for the
  // whole tree by test/flutter_test_config.dart) is what makes these real
  // glyphs rather than Ahem boxes.
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

  testWidgets('AppL10n.supportedLocales offers exactly en and bn', (
    tester,
  ) async {
    expect(AppL10n.supportedLocales.map((l) => l.languageCode).toSet(), {
      'en',
      'bn',
    });
  });
}
