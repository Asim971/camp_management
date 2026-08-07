import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/design_system/bmd_button.dart';
import '../../../core/design_system/bmd_field.dart';
import '../../../core/result/result.dart';

/// Maps a sign-in [Failure] to a correction-first message (Guideline §2.1).
///
/// Never returns a generic message: every kind is named explicitly, and the
/// exhaustive switch means a new [FailureKind] is a compile error here rather
/// than a silent fallback to "something went wrong".
String loginErrorMessage(Failure failure) => switch (failure.kind) {
  // Deliberately does NOT say which of the two was wrong: doing so is a
  // username-enumeration oracle.
  FailureKind.unauthorized => 'That username or password is not correct.',
  FailureKind.forbidden => 'This account is not enabled for this app.',
  FailureKind.network || FailureKind.timeout || FailureKind.offlineQueued =>
    'Cannot reach the sign-in service. Check your connection and try again.',
  FailureKind.server =>
    'The sign-in service is having trouble. Try again shortly.',
  // scope_claims names the unrecognised claims, and that detail is what makes
  // a client/server version mismatch diagnosable.
  FailureKind.validation =>
    failure.message ?? 'This account has details this app cannot read.',
  FailureKind.notFound =>
    'The sign-in service could not be found. Check the app configuration.',
  FailureKind.conflict => 'Another sign-in is already in progress. Try again.',
  FailureKind.unknown => 'Sign-in could not be completed. Try again.',
};

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter both your username and password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    String? error;
    try {
      final result = await ref
          .read(sessionManagerProvider)
          .signIn(username, password);
      error = result.fold((_) => null, loginErrorMessage);
    } catch (_) {
      // A throw here (e.g. a keystore fault persisting the new session) must
      // not leave _busy stuck true and the button spinning forever with no
      // way out - falling through to the setState below is what un-wedges it.
      error = 'Sign-in could not be completed. Try again.';
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sign in',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                BmdField(
                  label: 'Username',
                  controller: _username,
                  identifier: 'login_username',
                ),
                const SizedBox(height: 16),
                BmdField(
                  label: 'Password',
                  controller: _password,
                  obscureText: true,
                  identifier: 'login_password',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                BmdButton(
                  label: 'Sign in',
                  loading: _busy,
                  identifier: 'login_submit',
                  onPressed: _busy ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
