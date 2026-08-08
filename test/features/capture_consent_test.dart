import 'dart:async';

import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:acsl_campaign/core/consent/notice.dart';
import 'package:acsl_campaign/core/consent/notice_repository.dart';
import 'package:acsl_campaign/core/l10n/locale_controller.dart';
import 'package:acsl_campaign/core/media/capture_source.dart';
import 'package:acsl_campaign/core/media/evidence_store.dart';
import 'package:acsl_campaign/core/media/face_quality.dart';
import 'package:acsl_campaign/core/media/media_encryptor.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:acsl_campaign/core/sync/sync_engine.dart';
import 'package:acsl_campaign/features/camera_capture/application/capture_controller.dart';
import 'package:acsl_campaign/features/camera_capture/presentation/capture_flow_screen.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/scripted_adapter.dart';

const _bn = ConsentNotice(
  version: 4,
  language: 'bn',
  title: 'উপস্থিতির ছবি',
  body: 'উপস্থিতি যাচাইয়ের জন্য আপনার ছবি নেওয়া হচ্ছে।',
);

const _en = ConsentNotice(
  version: 4,
  language: 'en',
  title: 'Attendance photo',
  body: 'Your photo is captured to verify attendance.',
);

/// A [NoticeRepository] whose resolution is scripted per language, so a test can
/// make one language resolve and another fail without reimplementing the rule.
/// Every requested language is recorded, which is how "the toggle re-resolves"
/// and "the app locale is only the default" are observed.
class _ScriptedRepository extends NoticeRepository {
  _ScriptedRepository(this.byLanguage)
    : super(
        source: _UnusedSource(),
        readCached: _noCache,
        writeCached: _noWrite,
        loadAsset: _noAsset,
      );

  static Future<List<ConsentNotice>> _noCache() async => const [];
  static Future<void> _noWrite(List<ConsentNotice> notices) async {}
  static Future<String> _noAsset(String key) async =>
      throw StateError('the scripted repository never reads the bundle');

  final Map<String, ConsentNotice> byLanguage;
  final List<String> resolved = [];

  /// When set, `resolve` waits on it — used to observe the state *while* the
  /// first resolution is still in flight.
  Completer<void>? gate;

  @override
  Future<Result<ConsentNotice>> resolve(String language) async {
    resolved.add(language);
    if (gate != null) await gate!.future;
    final notice = byLanguage[language];
    if (notice == null) {
      return Err(
        Failure(
          FailureKind.unknown,
          message: 'No consent notice is available in "$language".',
        ),
      );
    }
    return Ok(notice);
  }
}

class _UnusedSource implements NoticeSource {
  @override
  Future<Result<List<ConsentNotice>>> fetchLatest() async =>
      throw StateError('resolve must never touch the transport');
}

class _PassthroughEncryptor implements MediaEncryptor {
  @override
  Future<List<int>> encrypt(List<int> plaintext) async => plaintext;
}

class _InMemoryEvidenceStore implements EvidenceStore {
  final Map<String, List<int>> files = {};

  @override
  Future<String> write(String name, List<int> bytes) async {
    files['/evidence/$name'] = bytes;
    return '/evidence/$name';
  }

  @override
  Future<List<int>> readBytes(String path) async => files[path]!;

  @override
  Future<void> deleteIfExists(String path) async => files.remove(path);
}

class _RecordingSyncEngine implements SyncEngine {
  final List<SyncTaskSpec> enqueued = [];

  @override
  Future<Result<void>> enqueue(SyncTaskSpec spec) async {
    enqueued.add(spec);
    return const Ok(null);
  }

  @override
  Future<void> drain() async {}

  @override
  Future<void> retry(String taskId) async {}

  @override
  Future<void> pause(String taskId) async {}

  @override
  Future<Result<void>> discard(String taskId, {required String reason}) async =>
      const Ok(null);

  @override
  Stream<List<SyncTaskView>> statusStream() => const Stream.empty();
}

/// [LocaleController] pinned to a value, so the notice's default language can be
/// driven without a locale store or a database.
class _FixedLocale extends LocaleController {
  _FixedLocale(this._locale);
  final Locale? _locale;

  @override
  Locale? build() => _locale;
}

const _args = CaptureArgs(sessionId: 's-1', carpenterId: 'c-1');

void main() {
  // ---- The record itself (Task 7's shapes, exercised through this task) ----

  test('accepting records version, language, timestamp AND hash', () async {
    // The existing TODO said "version + language + timestamp" and omitted the
    // hash — the one field that makes the record PROVE the text rather than
    // point at it.
    final record = ConsentRecord.of(
      _bn,
      DateTime.utc(2026, 8, 7, 12),
      await _bn.hash(),
    );

    expect(record.version, 4);
    expect(record.language, 'bn');
    expect(record.shownAt, DateTime.utc(2026, 8, 7, 12));
    expect(record.contentHash, await _bn.hash());
    expect(record.contentHash, isNotEmpty);
  });

  test('the recorded hash matches the text that was displayed', () async {
    // Resolution and recording must read the SAME object, or the record could
    // attest to text nobody saw.
    final record = ConsentRecord.of(
      _bn,
      DateTime.utc(2026, 8, 7),
      await _bn.hash(),
    );

    final recomputed = await consentContentHash(
      version: _bn.version,
      language: _bn.language,
      title: _bn.title,
      body: _bn.body,
    );

    expect(record.contentHash, recomputed);
  });

  test('a different language produces a different recorded hash', () async {
    const sameTextOtherLanguage = ConsentNotice(
      version: 4,
      language: 'en',
      title: 'উপস্থিতির ছবি',
      body: 'উপস্থিতি যাচাইয়ের জন্য আপনার ছবি নেওয়া হচ্ছে।',
    );

    expect(await sameTextOtherLanguage.hash(), isNot(await _bn.hash()));
  });

  // ---- The controller ------------------------------------------------------

  group('CaptureController', () {
    late _ScriptedRepository repository;
    late AppDatabase db;
    late _RecordingSyncEngine sync;
    late _InMemoryEvidenceStore evidence;

    ProviderContainer containerWith(Map<String, ConsentNotice> notices) {
      repository = _ScriptedRepository(notices);
      db = AppDatabase(NativeDatabase.memory());
      sync = _RecordingSyncEngine();
      evidence = _InMemoryEvidenceStore();
      final container = ProviderContainer(
        overrides: [
          noticeRepositoryProvider.overrideWithValue(repository),
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(sync),
          evidenceStoreProvider.overrideWithValue(evidence),
          mediaEncryptorProvider.overrideWithValue(_PassthroughEncryptor()),
          faceQualityCheckerProvider.overrideWithValue(
            const PassthroughQualityChecker(),
          ),
          authStateProvider.overrideWithValue(const AuthSignedOut()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);
      return container;
    }

    CaptureController notifierOf(ProviderContainer c) =>
        c.read(captureControllerProvider(_args).notifier);

    CaptureState stateOf(ProviderContainer c) =>
        c.read(captureControllerProvider(_args));

    test('loadNotice puts the resolved notice in state', () async {
      final c = containerWith(const {'bn': _bn});

      await notifierOf(c).loadNotice('bn');

      expect(stateOf(c).notice, same(_bn));
      expect(stateOf(c).noticeBlocked, isFalse);
      expect(stateOf(c).step, CaptureStep.purposeNotice);
    });

    test('acceptNotice records the displayed notice and advances', () async {
      final c = containerWith(const {'bn': _bn});
      await notifierOf(c).loadNotice('bn');

      await notifierOf(c).acceptNotice();

      final consent = stateOf(c).consent!;
      expect(consent.version, 4);
      expect(consent.language, 'bn');
      expect(consent.contentHash, await _bn.hash());
      expect(consent.shownAt.isUtc, isTrue);
      expect(stateOf(c).step, CaptureStep.positioning);
    });

    test('a resolution failure blocks capture and does not advance', () async {
      final c = containerWith(const {});

      await notifierOf(c).loadNotice('en');

      expect(stateOf(c).noticeBlocked, isTrue);
      expect(stateOf(c).notice, isNull);
      expect(stateOf(c).step, CaptureStep.purposeNotice);
    });

    test('selectNoticeLanguage re-resolves and replaces the notice', () async {
      final c = containerWith(const {'bn': _bn, 'en': _en});
      await notifierOf(c).loadNotice('bn');

      await notifierOf(c).selectNoticeLanguage('en');

      expect(repository.resolved, ['bn', 'en']);
      expect(stateOf(c).notice, same(_en));
      // ...and the record follows the text now displayed, not the first one.
      await notifierOf(c).acceptNotice();
      expect(stateOf(c).consent!.language, 'en');
      expect(stateOf(c).consent!.contentHash, await _en.hash());
    });

    // THE assertion this task exists for.
    test(
      'switching to a language that FAILS cannot record the previous notice',
      () async {
        final c = containerWith(const {'bn': _bn});
        await notifierOf(c).loadNotice('bn');
        expect(stateOf(c).notice, same(_bn), reason: 'precondition');

        // The blocking message is now on screen; the Bengali text is not.
        await notifierOf(c).selectNoticeLanguage('fr');
        expect(stateOf(c).noticeBlocked, isTrue);
        expect(
          stateOf(c).notice,
          isNull,
          reason:
              'the failure branch must genuinely CLEAR the notice — '
              'CaptureState.copyWith uses the `?? this.x` idiom, so '
              'copyWith(notice: null) would silently keep the Bengali notice',
        );

        await notifierOf(c).acceptNotice();

        expect(
          stateOf(c).consent,
          isNull,
          reason:
              'a consent record here would attest to Bengali wording the user '
              'was not looking at — the exact defect the content hash exists '
              'to make impossible',
        );
        expect(stateOf(c).step, CaptureStep.purposeNotice);
      },
    );

    test('acceptNotice does nothing when no notice was ever shown', () async {
      final c = containerWith(const {'bn': _bn});

      await notifierOf(c).acceptNotice();

      expect(stateOf(c).consent, isNull);
      expect(stateOf(c).step, CaptureStep.purposeNotice);
    });

    test('recapture keeps the consent record it already holds', () async {
      // submit() refuses without a consent record, so losing it on recapture
      // would strand the user one tap after a perfectly good photo.
      final c = containerWith(const {'bn': _bn});
      await notifierOf(c).loadNotice('bn');
      await notifierOf(c).acceptNotice();
      await notifierOf(c).onCaptured(const [1, 2, 3]);
      expect(stateOf(c).quality, isNotNull, reason: 'precondition');

      notifierOf(c).recapture();

      expect(stateOf(c).consent, isNotNull);
      expect(stateOf(c).notice, same(_bn));
      expect(stateOf(c).step, CaptureStep.liveCamera);
      expect(
        stateOf(c).quality,
        isNull,
        reason: 'recapture intends to clear the previous quality result',
      );
    });

    test('submit writes all four consent columns onto the draft', () async {
      final c = containerWith(const {'bn': _bn});
      await notifierOf(c).loadNotice('bn');
      await notifierOf(c).acceptNotice();
      final consent = stateOf(c).consent!;
      await notifierOf(c).onCaptured(const [1, 2, 3]);

      await notifierOf(c).submit();

      expect(stateOf(c).error, isNull);
      expect(stateOf(c).step, CaptureStep.captured);
      final row = await db.select(db.attendanceDrafts).getSingle();
      expect(row.consentVersion, 4);
      expect(row.consentLanguage, 'bn');
      expect(row.consentContentHash, await _bn.hash());
      expect(row.consentContentHash, consent.contentHash);
      expect(row.consentShownAt, isNotNull);
      // Drift stores DateTime as unix SECONDS, so the millisecond part of the
      // recorded instant does not survive the round trip.
      expect(
        row.consentShownAt!.toUtc().difference(consent.shownAt).inSeconds.abs(),
        lessThanOrEqualTo(1),
      );

      // ...and it rides with the payload the uploader confirms with, or the
      // server would never learn which wording was shown.
      final payload = sync.enqueued.single.payload;
      expect(payload['consentVersion'], 4);
      expect(payload['consentLanguage'], 'bn');
      expect(payload['consentContentHash'], await _bn.hash());
      expect(payload['consentShownAt'], consent.shownAt.toIso8601String());
    });

    test(
      'submit refuses, with an error, when no consent was recorded',
      () async {
        final c = containerWith(const {'bn': _bn});
        // Straight to a captured photo, skipping the notice entirely.
        await notifierOf(c).onCaptured(const [1, 2, 3]);

        await notifierOf(c).submit();

        expect(stateOf(c).error, isNotNull);
        expect(stateOf(c).error, contains('onsent'));
        expect(stateOf(c).submitting, isFalse);
        expect(stateOf(c).step, CaptureStep.qualityResult);
        expect(await db.select(db.attendanceDrafts).get(), isEmpty);
        expect(sync.enqueued, isEmpty);
        expect(evidence.files, isEmpty);
      },
    );
  });

  // ---- The provider wiring -------------------------------------------------

  group('noticeRepositoryProvider', () {
    // NoticeRepository is constructed NOWHERE else in lib/. Without these two
    // tests, forgetting `readCached:`/`writeCached:` would leave the whole suite
    // green while no device ever read or wrote a consent_notices row.
    late AppDatabase db;

    ProviderContainer containerWith(List<ScriptedReply> replies) {
      db = AppDatabase(NativeDatabase.memory());
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
        ..httpClientAdapter = ScriptedAdapter(replies);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);
      return container;
    }

    test('resolve reads the Drift cache, not just the bundled floor', () async {
      final c = containerWith(const []);
      // Version 99 beats the bundled v1, so it can only be returned by reading
      // the database — which is exactly what `readCached:` wires.
      const cached = ConsentNotice(
        version: 99,
        language: 'en',
        title: 'Cached v99',
        body: 'Cached body',
      );
      await driftNoticeWriter(db)([cached]);

      final resolved = await c.read(noticeRepositoryProvider).resolve('en');

      expect(resolved.fold((n) => n.version, (_) => null), 99);
      expect(resolved.fold((n) => n.title, (_) => null), 'Cached v99');
    });

    test(
      'refreshInBackground writes fetched notices to the Drift cache',
      () async {
        final c = containerWith(const [
          ScriptedReply.json(200, {
            'notices': [
              {
                'version': 12,
                'language': 'en',
                'title': 'Fetched v12',
                'body': 'Fetched body',
              },
            ],
          }),
        ]);

        await c.read(noticeRepositoryProvider).refreshInBackground();

        final rows = await db.select(db.consentNotices).get();
        expect(rows, hasLength(1), reason: 'writeCached: must be wired');
        expect(rows.single.version, 12);
        expect(rows.single.title, 'Fetched v12');
        expect(
          rows.single.contentHash,
          await const ConsentNotice(
            version: 12,
            language: 'en',
            title: 'Fetched v12',
            body: 'Fetched body',
          ).hash(),
        );
      },
    );
  });

  // ---- The screen ----------------------------------------------------------

  group('CaptureFlowScreen notice step', () {
    late _ScriptedRepository repository;

    Future<void> pump(
      WidgetTester tester,
      Map<String, ConsentNotice> notices, {
      Locale? appLocale,
      bool settle = true,
      bool hold = false,
    }) async {
      repository = _ScriptedRepository(notices);
      // Held BEFORE the first pump: initState resolves immediately, so a gate
      // installed afterwards would arrive too late to observe the loading state.
      if (hold) repository.gate = Completer<void>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            noticeRepositoryProvider.overrideWithValue(repository),
            captureSourceProvider.overrideWithValue(FakeCaptureSource()),
            localeControllerProvider.overrideWith(
              () => _FixedLocale(appLocale),
            ),
          ],
          child: const MaterialApp(
            home: CaptureFlowScreen(sessionId: 's-1', carpenterId: 'c-1'),
          ),
        ),
      );
      if (settle) await tester.pumpAndSettle();
    }

    testWidgets('renders the resolved notice rather than hardcoded text', (
      tester,
    ) async {
      await pump(tester, const {'bn': _bn}, appLocale: const Locale('bn'));

      expect(find.text(_bn.title), findsOneWidget);
      expect(find.text(_bn.body), findsOneWidget);
      expect(find.text('Accept and continue'), findsOneWidget);
    });

    testWidgets('defaults the notice language to the app locale', (
      tester,
    ) async {
      await pump(tester, const {
        'bn': _bn,
        'en': _en,
      }, appLocale: const Locale('bn'));

      expect(repository.resolved.first, 'bn');
    });

    testWidgets('falls back to English when no locale is chosen', (
      tester,
    ) async {
      // NOT the device locale: an unsupported one (fr) would resolve to Err and
      // block every capture on that phone.
      await pump(tester, const {'bn': _bn, 'en': _en});

      expect(repository.resolved.first, 'en');
      expect(find.text(_en.title), findsOneWidget);
    });

    testWidgets('the language toggle re-resolves and re-renders', (
      tester,
    ) async {
      await pump(tester, const {'bn': _bn, 'en': _en});
      expect(find.text(_en.title), findsOneWidget);

      await tester.tap(find.text('বাংলা'));
      await tester.pumpAndSettle();

      expect(repository.resolved, ['en', 'bn']);
      expect(find.text(_bn.title), findsOneWidget);
      expect(find.text(_en.title), findsNothing);
    });

    testWidgets('a blocked notice offers no path to the camera', (
      tester,
    ) async {
      await pump(tester, const {});

      expect(find.byKey(const Key('capture_notice_blocked')), findsOneWidget);
      expect(find.text('Accept and continue'), findsNothing);
      expect(find.text("I'm ready"), findsNothing);
      expect(find.text('Capture'), findsNothing);
    });

    testWidgets('shows progress while resolving, not the blocking message', (
      tester,
    ) async {
      await pump(tester, const {'en': _en}, settle: false, hold: true);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('capture_notice_blocked')), findsNothing);
      expect(find.text('Accept and continue'), findsNothing);

      repository.gate!.complete();
      await tester.pumpAndSettle();

      expect(find.text(_en.title), findsOneWidget);
    });
  });
}
