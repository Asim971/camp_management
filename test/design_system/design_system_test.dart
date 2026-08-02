import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/app/theme/tokens.dart';
import 'package:acsl_campaign/core/design_system/bmd_cards.dart';
import 'package:acsl_campaign/core/design_system/bmd_feedback.dart';
import 'package:acsl_campaign/core/design_system/lineage_rail.dart';
import 'package:acsl_campaign/core/design_system/status_chip.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// These tests guard the design rules that are easy to break silently — the
/// ones a reviewer would not catch in a diff but a field user would hit in
/// production.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: bmdTheme(brightness: brightness),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('BmdTokens', () {
    test('both modes expose the full validated series and funnel ramps', () {
      for (final tokens in [BmdTokens.light, BmdTokens.dark]) {
        expect(tokens.series, hasLength(6));
        expect(tokens.funnel, hasLength(5));
      }
    });

    test('slot 1 is brand red in both modes — the one principal series', () {
      expect(BmdTokens.light.series.first, BmdColor.primary600);
      expect(BmdTokens.dark.series.first, BmdColor.primary600);
    });

    test('no series slot impersonates a reserved semantic hue', () {
      // A list, not a const Set — Color has no primitive equality, so it
      // cannot be a compile-time set element.
      const reserved = <Color>[
        BmdColor.success,
        BmdColor.warning,
        BmdColor.error,
        BmdColor.info,
      ];
      for (final tokens in [BmdTokens.light, BmdTokens.dark]) {
        for (final c in tokens.series) {
          expect(reserved.contains(c), isFalse, reason: '$c is a status hue');
        }
      }
    });

    test('seriesAt folds past the last slot instead of inventing a hue', () {
      // A generated 7th hue would not have been through the CVD gates.
      expect(BmdTokens.light.seriesAt(6), BmdTokens.light.neutral);
      expect(BmdTokens.light.seriesAt(0), BmdColor.primary600);
    });

    testWidgets('the theme carries the tokens for the active brightness',
        (tester) async {
      late BmdTokens seen;
      await _pump(
        tester,
        Builder(
          builder: (context) {
            seen = Theme.of(context).bmd;
            return const SizedBox();
          },
        ),
        brightness: Brightness.dark,
      );
      expect(seen.series, BmdTokens.dark.series);
    });
  });

  group('StatusChip', () {
    testWidgets('every status family renders an icon, never colour alone',
        (tester) async {
      final chips = <StatusChip>[
        for (final s in CampaignStatus.values)
          StatusChip.campaign(s, label: s.name),
        for (final s in RegistrationStatus.values)
          StatusChip.registration(s, label: s.name),
        for (final s in AttendanceStatus.values)
          StatusChip.attendance(s, label: s.name),
        for (final s in ImportStatus.values)
          StatusChip.import(s, label: s.name),
        for (final f in IntegrityFlag.values)
          StatusChip.integrity(f, label: f.name),
      ];

      for (final chip in chips) {
        await _pump(tester, chip);
        expect(
          find.byType(Icon),
          findsOneWidget,
          reason: '${chip.label} must pair colour with an icon',
        );
        expect(find.text(chip.label), findsOneWidget);
      }
    });

    testWidgets('green is reserved for outcomes, not for registering',
        (tester) async {
      // Registering is an intention. Spending green on it makes a dashboard of
      // registrations read as a dashboard of success.
      final registered = StatusChip.registration(
        RegistrationStatus.registered,
        label: 'Registered',
      );
      expect(registered.tone, isNot(StatusTone.success));

      final approved = StatusChip.attendance(
        AttendanceStatus.approved,
        label: 'Approved',
      );
      expect(approved.tone, StatusTone.success);
    });

    testWidgets('a status chip announces itself as a status', (tester) async {
      await _pump(
        tester,
        StatusChip.attendance(
          AttendanceStatus.pendingSync,
          label: 'Pending sync',
        ),
      );
      expect(
        tester.getSemantics(find.byType(StatusChip)).label,
        'Status: Pending sync',
      );
    });
  });

  group('LineageRail', () {
    const chain = [
      LineageNode(label: 'Captured', state: LineageState.done, meta: '10:24'),
      LineageNode(
        label: 'Queued',
        state: LineageState.current,
        meta: 'waiting for network',
      ),
      LineageNode(label: 'Uploaded', state: LineageState.pending),
      LineageNode(label: 'CRM decision', state: LineageState.pending),
      LineageNode(label: 'Counted', state: LineageState.pending),
    ];

    testWidgets('renders every link, in order', (tester) async {
      await _pump(
        tester,
        const SizedBox(width: 900, child: LineageRail(nodes: chain)),
      );
      for (final node in chain) {
        expect(find.text(node.label), findsOneWidget);
      }
    });

    testWidgets('a pending step and a failed step are announced differently',
        (tester) async {
      // The whole component exists to keep these apart: capture success is not
      // upload success, and "hasn't happened" is not "went wrong".
      await _pump(
        tester,
        const SizedBox(
          width: 900,
          child: LineageRail(
            nodes: [
              LineageNode(label: 'Captured', state: LineageState.done),
              LineageNode(label: 'Upload failed', state: LineageState.failed),
              LineageNode(label: 'Counted', state: LineageState.pending),
            ],
          ),
        ),
      );

      String labelFor(String text) =>
          tester.getSemantics(find.text(text)).label;

      expect(labelFor('Captured'), contains('completed'));
      expect(labelFor('Upload failed'), contains('failed'));
      expect(labelFor('Counted'), contains('not started'));
    });

    testWidgets('the rail never wears brand red', (tester) async {
      // Red means "press this". A report that looks pressable is a bug.
      await _pump(
        tester,
        const SizedBox(
          width: 900,
          child: LineageRail(
            nodes: [
              LineageNode(label: 'Captured', state: LineageState.done),
              LineageNode(label: 'Upload failed', state: LineageState.failed),
              LineageNode(label: 'Blocked', state: LineageState.blocked),
              LineageNode(label: 'Counted', state: LineageState.pending),
            ],
          ),
        ),
      );

      final decorated = tester.widgetList<Container>(find.byType(Container));
      for (final container in decorated) {
        final decoration = container.decoration;
        if (decoration is BoxDecoration) {
          expect(decoration.color, isNot(BmdColor.primary600));
        }
      }
    });

    testWidgets('the vertical variant keeps the same semantics',
        (tester) async {
      await _pump(
        tester,
        const SizedBox(width: 320, child: LineageRail.vertical(nodes: chain)),
      );
      for (final node in chain) {
        expect(find.text(node.label), findsOneWidget);
      }
    });
  });

  group('KpiCard', () {
    testWidgets('carries denominator, source and freshness on the card',
        (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: 320,
          child: KpiCard(
            label: 'Verified attendance',
            value: '1,107',
            denominator: 'of 1,184 registered · 93.5%',
            definition: 'Distinct carpenters with a CRM-approved record.',
            source: 'verification facts',
            freshness: 'refreshed 09:42',
          ),
        ),
      );

      expect(find.text('1,107'), findsOneWidget);
      expect(find.text('of 1,184 registered · 93.5%'), findsOneWidget);
      // Source and freshness are on the card, not in a tooltip — the card is
      // what gets screenshotted into a deck.
      expect(find.text('verification facts · refreshed 09:42'), findsOneWidget);
    });
  });

  group('Feedback', () {
    testWidgets('the offline bar reports upload state, never recapture',
        (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: 390,
          child: OfflineBar(pendingCount: 3, lastSyncLabel: '14m ago'),
        ),
      );

      final semantics = tester.getSemantics(find.byType(OfflineBar)).label;
      expect(semantics, contains('3 captures waiting to upload'));
      expect(semantics, contains('14m ago'));
      expect(semantics.toLowerCase(), isNot(contains('recapture')));
    });

    testWidgets('a denied state names the rule and carries a reference',
        (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: 480,
          child: BmdState.denied(
            title: "You don't have access to campaign approval",
            body: 'Approval is limited to the Campaign Approver role, and an '
                'approver cannot approve a campaign they created.',
            reference: 'Reference SEC-403',
          ),
        ),
      );

      expect(
        find.textContaining('cannot approve a campaign they created'),
        findsOneWidget,
      );
      expect(find.text('Reference SEC-403'), findsOneWidget);
    });
  });
}
