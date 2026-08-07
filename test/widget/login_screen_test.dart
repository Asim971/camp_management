import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/features/auth/presentation/login_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('loginErrorMessage', () {
    test('401 does not reveal WHICH field was wrong', () {
      // Distinguishing "no such user" from "wrong password" is a username
      // enumeration oracle.
      final message = loginErrorMessage(
        const Failure(FailureKind.unauthorized),
      );

      expect(message, 'That username or password is not correct.');
      expect(message.toLowerCase(), isNot(contains('user does not')));
      expect(message.toLowerCase(), isNot(contains('no such')));
    });

    test('403 explains the account is not enabled', () {
      expect(
        loginErrorMessage(const Failure(FailureKind.forbidden)),
        'This account is not enabled for this app.',
      );
    });

    test('network and timeout both point at connectivity', () {
      for (final kind in [FailureKind.network, FailureKind.timeout]) {
        expect(
          loginErrorMessage(Failure(kind)),
          'Cannot reach the sign-in service. Check your connection and try again.',
        );
      }
    });

    test('server failure is distinct from a connectivity failure', () {
      expect(
        loginErrorMessage(const Failure(FailureKind.server)),
        'The sign-in service is having trouble. Try again shortly.',
      );
    });

    test('a validation failure surfaces the claim mismatch verbatim', () {
      // scope_claims names the unrecognised claims; that detail is what makes
      // a version mismatch diagnosable, so it must not be swallowed.
      final message = loginErrorMessage(
        const Failure(
          FailureKind.validation,
          message:
              'This account has claims this app version does not '
              'recognise: role "galactic_overlord".',
        ),
      );

      expect(message, contains('galactic_overlord'));
    });

    test('every FailureKind maps to a non-empty, non-generic message', () {
      // Guideline 2.1 forbids a generic "something went wrong" anywhere.
      for (final kind in FailureKind.values) {
        final message = loginErrorMessage(Failure(kind));
        expect(message, isNotEmpty, reason: '$kind has no message');
        expect(
          message.toLowerCase(),
          isNot(contains('something went wrong')),
          reason: '$kind falls back to a generic message',
        );
      }
    });
  });
}
