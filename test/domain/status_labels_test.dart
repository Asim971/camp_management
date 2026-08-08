import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/domain/common/status_labels.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations_bn.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Both locales are exercised, because a key present in en and empty in bn
  // would satisfy the compiler and still ship a blank label.
  final locales = {'en': AppL10nEn(), 'bn': AppL10nBn()};

  locales.forEach((code, l10n) {
    group('locale $code', () {
      test('every CampaignStatus resolves', () {
        for (final s in CampaignStatus.values) {
          expect(s.label(l10n), isNotEmpty, reason: '$code / ${s.name}');
        }
      });

      test('every RegistrationStatus resolves', () {
        for (final s in RegistrationStatus.values) {
          expect(s.label(l10n), isNotEmpty, reason: '$code / ${s.name}');
        }
      });

      test('every AttendanceStatus resolves', () {
        for (final s in AttendanceStatus.values) {
          expect(s.label(l10n), isNotEmpty, reason: '$code / ${s.name}');
        }
      });

      test('every ImportStatus resolves', () {
        for (final s in ImportStatus.values) {
          expect(s.label(l10n), isNotEmpty, reason: '$code / ${s.name}');
        }
      });

      test('every IntegrityFlag resolves', () {
        for (final f in IntegrityFlag.values) {
          expect(f.label(l10n), isNotEmpty, reason: '$code / ${f.name}');
        }
      });
    });
  });

  test('labels differ between locales', () {
    // Guards against a copy-paste that points bn at the en getters, which
    // would pass every "isNotEmpty" assertion above. Tests all five families,
    // using a machine-drafted key from RegistrationStatus, ImportStatus and
    // IntegrityFlag (the three families with new keys) since those are most
    // likely to be stale. CampaignStatus and AttendanceStatus use existing
    // keys since they have no new additions.
    expect(
      CampaignStatus.draft.label(AppL10nEn()),
      isNot(CampaignStatus.draft.label(AppL10nBn())),
    );
    expect(
      AttendanceStatus.notCaptured.label(AppL10nEn()),
      isNot(AttendanceStatus.notCaptured.label(AppL10nBn())),
    );
    expect(
      RegistrationStatus.invited.label(AppL10nEn()),
      isNot(RegistrationStatus.invited.label(AppL10nBn())),
    );
    expect(
      ImportStatus.dryRun.label(AppL10nEn()),
      isNot(ImportStatus.dryRun.label(AppL10nBn())),
    );
    expect(
      IntegrityFlag.noReference.label(AppL10nEn()),
      isNot(IntegrityFlag.noReference.label(AppL10nBn())),
    );
  });
}
