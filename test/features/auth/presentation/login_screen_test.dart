import 'dart:async';

import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:acsl_campaign/core/design_system/bmd_button.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_auth.dart';

/// [SessionManager] whose [signIn] is fully controlled by the test: it
/// records every call, optionally gates on a [Completer] so the busy state
/// can be observed mid-flight, and can be told to throw instead of returning
/// a [Result] - the fault I2 diagnosed (a keystore write escaping
/// `_adopt`) surfaces to `_submit` exactly this way.
class _ControllableSessionManager extends SessionManager {
  _ControllableSessionManager()
    : super(service: ScriptedAuthService(), tokens: FakeTokenStore());

  final List<String> signInCalls = [];
  Completer<Result<void>>? gate;
  Result<void> result = const Err(Failure(FailureKind.unauthorized));
  bool shouldThrow = false;

  @override
  Future<Result<void>> signIn(String username, String password) async {
    signInCalls.add('$username:$password');
    if (shouldThrow) throw StateError('keystore write escaped persist()');
    if (gate != null) return gate!.future;
    return result;
  }
}

void main() {
  Future<_ControllableSessionManager> pump(
    WidgetTester tester,
    _ControllableSessionManager manager,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionManagerProvider.overrideWithValue(manager)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    return manager;
  }

  Future<void> enterCredentials(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).at(0), 'bob');
    await tester.enterText(find.byType(TextFormField).at(1), 'pw');
  }

  testWidgets('empty fields show a message and never call signIn', (
    tester,
  ) async {
    final manager = await pump(tester, _ControllableSessionManager());
    addTearDown(manager.dispose);

    await tester.tap(find.byType(BmdButton));
    await tester.pump();

    expect(find.text('Enter both your username and password.'), findsOneWidget);
    expect(manager.signInCalls, isEmpty);
  });

  testWidgets('the busy state disables submit until signIn resolves', (
    tester,
  ) async {
    final manager = _ControllableSessionManager()
      ..gate = Completer<Result<void>>();
    addTearDown(manager.dispose);
    await pump(tester, manager);
    await enterCredentials(tester);

    await tester.tap(find.byType(BmdButton));
    await tester.pump();

    // Still mid-flight: onPressed must be nulled, not merely visually dimmed
    // - a second tap while _busy is true must not fire a second signIn.
    expect(manager.signInCalls, hasLength(1));
    final button = tester.widget<BmdButton>(find.byType(BmdButton));
    expect(button.onPressed, isNull);
    expect(button.loading, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    manager.gate!.complete(const Err(Failure(FailureKind.unauthorized)));
    await tester.pumpAndSettle();

    final settled = tester.widget<BmdButton>(find.byType(BmdButton));
    expect(settled.onPressed, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failed sign-in surfaces the mapped message, not a raw '
      'exception', (tester) async {
    final manager = _ControllableSessionManager()
      ..result = const Err(Failure(FailureKind.unauthorized));
    addTearDown(manager.dispose);
    await pump(tester, manager);
    await enterCredentials(tester);

    await tester.tap(find.byType(BmdButton));
    await tester.pumpAndSettle();

    expect(
      find.text('That username or password is not correct.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'I2: a throw out of signIn does not leave the button spinning forever',
    (tester) async {
      // The fault this pins: a keystore fault escaping SessionManager._adopt
      // (before token_store.dart's persist()/clear() were hardened) used to
      // leave _busy stuck true with no way for the user to recover.
      final manager = _ControllableSessionManager()..shouldThrow = true;
      addTearDown(manager.dispose);
      await pump(tester, manager);
      await enterCredentials(tester);

      await tester.tap(find.byType(BmdButton));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text('Sign-in could not be completed. Try again.'),
        findsOneWidget,
      );
    },
  );
}
