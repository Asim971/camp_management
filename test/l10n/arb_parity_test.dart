import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reads an ARB file and returns only its translatable keys — `@@locale` and
/// the `@key` metadata blocks are not strings the user ever sees.
Set<String> _translatableKeys(String path) {
  final json =
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  return json.keys.where((k) => !k.startsWith('@')).toSet();
}

void main() {
  const en = 'lib/l10n/app_en.arb';
  const bn = 'lib/l10n/app_bn.arb';

  test('en and bn have identical key sets', () {
    // This assertion PASSES today (both files hold the same 26 keys). It is
    // here to stop future drift, not to detect current drift — which is
    // exactly the failure that let three status families go missing while
    // status.dart advertised l10nKey getters for them.
    final enKeys = _translatableKeys(en);
    final bnKeys = _translatableKeys(bn);

    expect(
      enKeys.difference(bnKeys),
      isEmpty,
      reason: 'keys present in en but missing from bn',
    );
    expect(
      bnKeys.difference(enKeys),
      isEmpty,
      reason: 'keys present in bn but missing from en',
    );
  });

  test('both files hold all 45 expected keys', () {
    // 26 pre-existing + 19 added by this task. This is the assertion that
    // goes red before the keys land and green after.
    expect(_translatableKeys(en), hasLength(45));
    expect(_translatableKeys(bn), hasLength(45));
  });

  test('every status family the enums advertise has a full set of keys', () {
    // status.dart previously exposed l10nKey getters for five families while
    // the ARB carried only two. Pinning the per-family counts means adding an
    // enum value without its key fails here, not silently at runtime.
    final keys = _translatableKeys(en);
    int countPrefixed(String prefix) =>
        keys.where((k) => k.startsWith(prefix)).length;

    expect(countPrefixed('campaignStatus_'), 8);
    expect(countPrefixed('registrationStatus_'), 6);
    expect(countPrefixed('attendanceStatus_'), 7);
    expect(countPrefixed('importStatus_'), 7);
    expect(countPrefixed('integrityFlag_'), 6);
  });

  test('new machine-drafted bn values are marked unreviewed', () {
    // The 26 pre-existing bn values are genuine human translations. The 19
    // added here are machine drafts, and an unmarked draft is worse than an
    // obviously provisional one because it invites nobody to check it.
    final bnJson =
        jsonDecode(File(bn).readAsStringSync()) as Map<String, Object?>;
    const newKeys = [
      'registrationStatus_invited',
      'registrationStatus_registered',
      'registrationStatus_pendingProfileSync',
      'registrationStatus_ineligible',
      'registrationStatus_waitlisted',
      'registrationStatus_cancelled',
      'importStatus_dryRun',
      'importStatus_readyToCommit',
      'importStatus_processing',
      'importStatus_completed',
      'importStatus_partiallyCompleted',
      'importStatus_failed',
      'importStatus_cancelled',
      'integrityFlag_noReference',
      'integrityFlag_poorQuality',
      'integrityFlag_suspectedSpoof',
      'integrityFlag_duplicate',
      'integrityFlag_geofenceException',
      'integrityFlag_manualOverride',
    ];
    for (final key in newKeys) {
      final meta = bnJson['@$key'];
      expect(
        meta,
        isA<Map<String, Object?>>(),
        reason: '$key must carry @-metadata marking it unreviewed',
      );
      expect(
        (meta! as Map<String, Object?>)['description'],
        contains('UNREVIEWED'),
        reason: '$key metadata must say UNREVIEWED',
      );
    }
  });
}
