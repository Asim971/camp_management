import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/app/theme/tokens.dart';
import 'package:acsl_campaign/core/design_system/bmd_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child, {double width = 1280}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: bmdTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

void main() {
  group('BmdField', () {
    testWidgets('a required field says so in its accessible name', (
      tester,
    ) async {
      // An asterisk glyph is decoration; a screen-reader user needs the word.
      await _pump(
        tester,
        const BmdField(label: 'Campaign name', required: true),
      );

      final label = tester
          .getSemantics(find.byType(TextField))
          .label
          .toLowerCase();
      expect(label, contains('campaign name'));
      expect(label, contains('required'));
    });

    testWidgets('errorText overrides validator output', (tester) async {
      // A server rejection or an async duplicate check has to be able to beat
      // whatever a synchronous validator currently thinks. Driving validate()
      // explicitly is what actually exercises the precedence: without it,
      // the validator is never invoked and this test would pass even if the
      // errorText/validator guard were deleted.
      final formKey = GlobalKey<FormState>();
      await _pump(
        tester,
        Form(
          key: formKey,
          child: BmdField(
            label: 'Campaign name',
            errorText: 'A campaign with this name already exists',
            validator: (_) => 'Locally this looks fine',
          ),
        ),
      );

      formKey.currentState!.validate();
      await tester.pump();

      expect(
        find.text('A campaign with this name already exists'),
        findsOneWidget,
      );
      expect(find.text('Locally this looks fine'), findsNothing);
    });

    testWidgets('a multiline field is at least 96px tall', (tester) async {
      await _pump(tester, const BmdField.multiline(label: 'Objective'));

      // Assert the constraint itself, not just a rendered height that could
      // coincidentally land on 96px for other reasons (e.g. minLines: 3's
      // natural line-box height at this test's width).
      final decoration = tester
          .widget<TextField>(find.byType(TextField))
          .decoration;
      expect(decoration?.constraints?.minHeight, BmdSize.textareaMin);

      final height = tester
          .getSize(
            find.descendant(
              of: find.byType(BmdField),
              matching: find.byType(InputDecorator),
            ),
          )
          .height;
      expect(height, greaterThanOrEqualTo(96));
    });

    testWidgets('a masked field never shows the full value unrevealed', (
      tester,
    ) async {
      const full = '1990123456789';
      await _pump(
        tester,
        BmdField.masked(
          label: 'National ID',
          maskedValue: '•••••••••4821',
          onReveal: () async => full,
        ),
      );

      expect(find.text('•••••••••4821'), findsOneWidget);
      expect(find.text(full), findsNothing);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      expect(find.text(full), findsOneWidget);
    });

    testWidgets('with no reveal callback the affordance is absent', (
      tester,
    ) async {
      // Not disabled — a disabled reveal button advertises data the user
      // cannot have (§10.2).
      await _pump(
        tester,
        const BmdField.masked(
          label: 'National ID',
          maskedValue: '•••••••••4821',
        ),
      );

      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    });
  });

  group('BmdSearchField', () {
    testWidgets('rapid typing collapses into one query', (tester) async {
      final queries = <String>[];
      await _pump(
        tester,
        BmdSearchField(
          scopeLabel: 'Searches name, carpenter ID, phone suffix',
          onQueryChanged: queries.add,
        ),
      );

      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump(const Duration(milliseconds: 400));

      expect(queries, ['abc']);
    });

    testWidgets('clearing is immediate, not debounced', (tester) async {
      final queries = <String>[];
      await _pump(
        tester,
        BmdSearchField(
          scopeLabel: 'Searches campaign name and code',
          initialQuery: 'roadshow',
          onQueryChanged: queries.add,
        ),
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(queries, [''], reason: 'a delayed clear reads as a broken field');
    });

    testWidgets('the search scope is always visible', (tester) async {
      // §5.3: the user must be able to see what is being searched.
      await _pump(
        tester,
        BmdSearchField(
          scopeLabel: 'Searches name, carpenter ID, phone suffix',
          onQueryChanged: (_) {},
        ),
      );

      expect(
        find.text('Searches name, carpenter ID, phone suffix'),
        findsOneWidget,
      );
    });
  });
}
