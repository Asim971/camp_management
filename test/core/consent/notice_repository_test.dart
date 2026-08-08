import 'dart:async';
import 'dart:convert';

import 'package:acsl_campaign/core/consent/notice.dart';
import 'package:acsl_campaign/core/consent/notice_repository.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Source whose result is scripted, recording whether it was called at all.
class _ScriptedSource implements NoticeSource {
  _ScriptedSource([this._result]);
  final Result<List<ConsentNotice>>? _result;
  int calls = 0;
  Completer<void>? gate;

  @override
  Future<Result<List<ConsentNotice>>> fetchLatest() async {
    calls++;
    if (gate != null) await gate!.future;
    return _result ?? const Ok(<ConsentNotice>[]);
  }
}

String _bundledJson({int version = 1}) => jsonEncode({
  'version': version,
  'notices': [
    {
      'version': version,
      'language': 'en',
      'title': 'Bundled EN',
      'body': 'Bundled body EN',
    },
    {
      'version': version,
      'language': 'bn',
      'title': 'Bundled BN',
      'body': 'Bundled body BN',
    },
  ],
});

void main() {
  NoticeRepository build({
    _ScriptedSource? source,
    List<ConsentNotice> cached = const [],
    String? assetJson,
    bool assetThrows = false,
  }) => NoticeRepository(
    source: source ?? _ScriptedSource(),
    readCached: () async => cached,
    writeCached: (_) async {},
    loadAsset: (_) async {
      if (assetThrows) throw StateError('asset missing');
      return assetJson ?? _bundledJson();
    },
  );

  group('resolve', () {
    test('falls back to the bundled floor when nothing is cached', () async {
      final result = await build().resolve('en');

      final notice = result.fold((n) => n, (_) => null)!;
      expect(notice.version, 1);
      expect(notice.title, 'Bundled EN');
    });

    test('prefers a newer cached version over the bundled floor', () async {
      final result = await build(
        cached: const [
          ConsentNotice(
            version: 5,
            language: 'en',
            title: 'Cached EN v5',
            body: 'b',
          ),
        ],
      ).resolve('en');

      expect(result.fold((n) => n.version, (_) => null), 5);
      expect(result.fold((n) => n.title, (_) => null), 'Cached EN v5');
    });

    test('keeps the bundled floor when the cache is OLDER', () async {
      // A stale cached row must never beat a newer bundled version shipped by
      // an app update.
      final result = await build(
        assetJson: _bundledJson(version: 7),
        cached: const [
          ConsentNotice(version: 3, language: 'en', title: 'old', body: 'b'),
        ],
      ).resolve('en');

      expect(result.fold((n) => n.version, (_) => null), 7);
    });

    test('picks the highest cached version, not the first', () async {
      final result = await build(
        cached: const [
          ConsentNotice(version: 4, language: 'en', title: 'v4', body: 'b'),
          ConsentNotice(version: 9, language: 'en', title: 'v9', body: 'b'),
          ConsentNotice(version: 6, language: 'en', title: 'v6', body: 'b'),
        ],
      ).resolve('en');

      expect(result.fold((n) => n.version, (_) => null), 9);
    });

    test('resolves per language, not globally', () async {
      final result = await build(
        cached: const [
          ConsentNotice(version: 9, language: 'en', title: 'v9 en', body: 'b'),
        ],
      ).resolve('bn');

      // No cached bn row, so bn falls back to the bundled floor even though a
      // newer en version exists.
      expect(result.fold((n) => n.title, (_) => null), 'Bundled BN');
    });

    test('resolves an equal-version tie to the BUNDLED notice', () async {
      // Cache and bundle both claim version 4 but disagree on the text, so
      // they have DIFFERENT content hashes. Task 10 records that hash as proof
      // of the exact wording shown, so an arbitrary pick would produce a
      // consent record matching neither copy — a defect that only surfaces
      // during a dispute. The bundled text is the copy reviewed for version 4
      // and shipped inside this binary, so it is the one that must win.
      final result = await build(
        assetJson: _bundledJson(version: 4),
        cached: const [
          ConsentNotice(
            version: 4,
            language: 'en',
            title: 'Cached EN v4',
            body: 'cached body',
          ),
        ],
      ).resolve('en');

      expect(result.fold((n) => n.version, (_) => null), 4);
      expect(result.fold((n) => n.title, (_) => null), 'Bundled EN');
    });

    test('a newer cached version still beats an older bundled one', () async {
      // The reverse direction of the tie-break, so "bundled wins ties" cannot
      // silently become "bundled always wins".
      final result = await build(
        assetJson: _bundledJson(version: 4),
        cached: const [
          ConsentNotice(
            version: 5,
            language: 'en',
            title: 'Cached EN v5',
            body: 'b',
          ),
        ],
      ).resolve('en');

      expect(result.fold((n) => n.version, (_) => null), 5);
      expect(result.fold((n) => n.title, (_) => null), 'Cached EN v5');
    });

    test('NEVER awaits the network', () async {
      // The guarantee that makes offline capture possible. The gate is held
      // shut for the whole call; if resolve awaited the source it would hang
      // and this test would time out.
      final source = _ScriptedSource()..gate = Completer<void>();

      final result = await build(source: source).resolve('en');

      expect(result.isOk, isTrue);
      expect(source.calls, 0);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('returns Err when no notice can be resolved at all', () async {
      // Spec D7: consent fails CLOSED. A missing bundled asset with an empty
      // cache must not yield a null notice that a caller might render as blank
      // — capture has to be blocked.
      final result = await build(assetThrows: true).resolve('en');

      expect(result.isOk, isFalse);
      expect(result.fold((_) => null, (f) => f.kind), FailureKind.unknown);
    });

    test('returns Err when the bundled asset is not valid JSON', () async {
      // Distinct code path from a missing asset: loadAsset SUCCEEDS and
      // jsonDecode is what throws. ConsentNotice.fromJson is unguarded (bare
      // `!` and `as`), so this pins that the throw is contained and consent
      // fails closed rather than an exception reaching the capture screen.
      final Result<ConsentNotice> result;
      try {
        result = await build(assetJson: 'not-json{{{').resolve('en');
      } catch (error) {
        fail('resolve threw instead of returning Err: $error');
      }

      expect(result.isOk, isFalse);
      expect(result.fold((_) => null, (f) => f.kind), FailureKind.unknown);
    });

    test(
      'returns Err when a bundled notice is missing a required field',
      () async {
        // Third code path: the JSON parses, but fromJson's `json['body']!`
        // throws on the null. Must still be contained.
        final malformed = jsonEncode(const {
          'version': 1,
          'notices': [
            {'version': 1, 'language': 'en', 'title': 'No body'},
          ],
        });

        final Result<ConsentNotice> result;
        try {
          result = await build(assetJson: malformed).resolve('en');
        } catch (error) {
          fail('resolve threw instead of returning Err: $error');
        }

        expect(result.isOk, isFalse);
        expect(result.fold((_) => null, (f) => f.kind), FailureKind.unknown);
      },
    );

    test('returns Err for a language the bundle does not contain', () async {
      final result = await build().resolve('fr');

      expect(result.isOk, isFalse);
    });
  });

  group('the real bundled asset', () {
    // Every test above injects `loadAsset`, so nothing there exercises the
    // actual file or the pubspec `assets:` entry. Without this, a path typo or
    // a malformed commit would ship and fail SILENTLY — landing in resolve's
    // catch and returning Err, i.e. blocking every capture on every device.
    setUp(TestWidgetsFlutterBinding.ensureInitialized);

    test('loads through rootBundle and yields both languages', () async {
      final repo = NoticeRepository(
        source: _ScriptedSource(),
        readCached: () async => const [],
        writeCached: (_) async {},
      );

      for (final language in ['en', 'bn']) {
        final result = await repo.resolve(language);

        final notice = result.fold((n) => n, (_) => null);
        expect(
          notice,
          isNotNull,
          reason:
              'assets/consent/notice_v1.json did not resolve for "$language" '
              '— check the pubspec assets: entry and the JSON.',
        );
        expect(notice!.version, 1);
        expect(notice.language, language);
        expect(notice.title, isNotEmpty);
        // Pending Legal sign-off: the placeholder must announce itself in-text
        // so no one mistakes it for approved wording. The ticket marker is the
        // portable assertion — the English body says "PLACEHOLDER" but the
        // Bengali says "প্লেসহোল্ডার", so the Latin word is not a shared
        // invariant while `T-0.5.2` is.
        expect(notice.body, contains('T-0.5.2'));
      }

      // ...and the English body does carry the Latin word.
      final en = await repo.resolve('en');
      expect(en.fold((n) => n.body, (_) => ''), contains('PLACEHOLDER'));
    });
  });

  group('refreshInBackground', () {
    test('calls the source and does not throw when it fails', () async {
      final source = _ScriptedSource(const Err(Failure(FailureKind.network)));

      await expectLater(build(source: source).refreshInBackground(), completes);
      expect(source.calls, 1);
    });
  });
}
