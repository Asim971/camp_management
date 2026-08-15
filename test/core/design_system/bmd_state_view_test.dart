import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/core/design_system/bmd_state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: bmdTheme(brightness: Brightness.light),
  // disableAnimations so Reveal renders its final frame on the first pump.
  home: MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('empty variant renders icon, title, message and optional '
      'action', (tester) async {
    await tester.pumpWidget(
      _host(
        const BmdStateView.empty(
          title: 'No cases in this view',
          message: 'Claimed and escalated cases appear under their tabs.',
          action: Text('action-slot'),
        ),
      ),
    );
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(find.text('No cases in this view'), findsOneWidget);
    expect(find.text('action-slot'), findsOneWidget);
  });

  testWidgets('error variant renders a Retry button wired to onRetry', (
    tester,
  ) async {
    var retried = 0;
    await tester.pumpWidget(
      _host(
        BmdStateView.error(
          title: "Couldn't load campaigns",
          message: 'Check your connection and try again.',
          onRetry: () => retried++,
        ),
      ),
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, 1);
  });
}
