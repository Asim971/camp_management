import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/domain/common/status_labels.dart';
import 'package:acsl_campaign/domain/session/campaign_session.dart';
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

      test('every SessionStatus resolves', () {
        for (final s in SessionStatus.values) {
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
    // would pass every "isNotEmpty" assertion above. Tests all six families,
    // using a machine-drafted key from SessionStatus, RegistrationStatus,
    // ImportStatus and IntegrityFlag (the four families with new keys) since
    // those are most likely to be stale. CampaignStatus and AttendanceStatus
    // use existing keys since they have no new additions.
    //
    // SessionStatus uses captureClosed rather than active/paused/completed:
    // those three share their Bengali with the CampaignStatus keys of the same
    // name (correctly — they mean the same thing), so a copy-paste that pointed
    // sessionStatus_active at campaignStatus_active would survive undetected.
    expect(
      CampaignStatus.draft.label(AppL10nEn()),
      isNot(CampaignStatus.draft.label(AppL10nBn())),
    );
    expect(
      AttendanceStatus.notCaptured.label(AppL10nEn()),
      isNot(AttendanceStatus.notCaptured.label(AppL10nBn())),
    );
    expect(
      SessionStatus.captureClosed.label(AppL10nEn()),
      isNot(SessionStatus.captureClosed.label(AppL10nBn())),
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
