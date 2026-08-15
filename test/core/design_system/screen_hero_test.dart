import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/core/design_system/screen_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: bmdTheme(brightness: Brightness.light),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('displayTitle role is 30px, w700 via fontVariations, tight '
      'tracking', (tester) async {
    late TextStyle style;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) {
            style = context.displayTitle;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(style.fontSize, 30);
    expect(style.fontVariations, contains(const FontVariation('wght', 700)));
    expect(style.letterSpacing, -0.5);
  });

  testWidgets('ScreenHero renders title in displayTitle size and every '
      'populated slot', (tester) async {
    await tester.pumpWidget(
      _host(
        const ScreenHero(
          title: 'Campaigns',
          subtitle: 'All campaigns in scope',
          summary: [Text('12 total')],
          actions: [Text('Create')],
          meter: Text('meter-slot'),
        ),
      ),
    );
    final title = tester.widget<Text>(find.text('Campaigns'));
    expect(title.style?.fontSize, 30);
    expect(find.text('All campaigns in scope'), findsOneWidget);
    expect(find.text('12 total'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('meter-slot'), findsOneWidget);
  });

  testWidgets('ScreenHero omits unpopulated slots', (tester) async {
    await tester.pumpWidget(_host(const ScreenHero(title: 'Queue')));
    expect(find.text('Queue'), findsOneWidget);
    // Only the title paints — no Wrap rows for empty summary/actions.
    expect(find.byType(Wrap), findsNothing);
  });
}
