import 'dart:convert';
import 'dart:typed_data';

import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/data/verification/verification_repository_impl.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/domain/verification/verification.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every request and answers a canned response — the transport-level
/// twin of `test/data/import/import_repository_impl_test.dart`.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._respond);
  final ResponseBody Function(RequestOptions options) _respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return _respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(Object? body, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  late _RecordingAdapter adapter;
  late VerificationRepositoryImpl repo;

  VerificationRepositoryImpl build(
    ResponseBody Function(RequestOptions) respond,
  ) {
    adapter = _RecordingAdapter(respond);
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    return VerificationRepositoryImpl(dio);
  }

  test(
    'queue parses band/referenceSource from SCREAMING_SNAKE wire values',
    () async {
      repo = build(
        (_) => _jsonBody({
          'items': [
            {
              'attendanceId': 'ATT-1',
              'carpenterName': 'Karim Uddin',
              'campaignName': 'Test Campaign',
              'ageSeconds': 120,
              'band': 'MEDIUM',
              'referenceSource': 'APPROVED_BASELINE_PHOTO',
              'assigneeId': null,
            },
          ],
        }),
      );
      final res = await repo.queue();
      final items = res.fold((v) => v, (f) => fail('expected Ok: $f'));
      expect(items.single.band, MatchBand.medium);
      expect(
        items.single.referenceSource,
        ReferenceSource.approvedBaselinePhoto,
      );
    },
  );

  test(
    'getCase parses band/referenceSource from SCREAMING_SNAKE wire values',
    () async {
      repo = build(
        (_) => _jsonBody({
          'attendanceId': 'ATT-1',
          'version': 1,
          'carpenterName': 'Karim Uddin',
          'carpenterIdMasked': '••••1234',
          'campaignName': 'Test Campaign',
          'sessionName': 'Session A',
          'capturedAt': '2026-07-30T00:00:00.000Z',
          'capturedImageUrl': 'https://example.test/captured.png',
          'referenceImageUrl': null,
          'band': 'MEDIUM',
          'referenceSource': 'APPROVED_BASELINE_PHOTO',
        }),
      );
      final res = await repo.getCase('ATT-1');
      final case_ = res.fold((v) => v, (f) => fail('expected Ok: $f'));
      expect(case_.machine.band, MatchBand.medium);
      expect(
        case_.machine.referenceSource,
        ReferenceSource.approvedBaselinePhoto,
      );
    },
  );

  test('an unknown band wire value is a visible fallback (noReference), not a '
      'crash', () async {
    repo = build(
      (_) => _jsonBody({
        'items': [
          {
            'attendanceId': 'ATT-1',
            'carpenterName': 'Karim Uddin',
            'campaignName': 'Test Campaign',
            'ageSeconds': 120,
            'band': 'SOME_FUTURE_BAND',
            'referenceSource': 'UNAVAILABLE',
            'assigneeId': null,
          },
        ],
      }),
    );
    final res = await repo.queue();
    final items = res.fold((v) => v, (f) => fail('expected Ok: $f'));
    expect(items.single.band, MatchBand.noReference);
  });

  test('submitDecision (decide) posts outcome as the SCREAMING_SNAKE wireValue '
      'and sends If-Match', () async {
    repo = build((_) => _jsonBody(null, status: 204));
    const decision = VerificationDecision(
      attendanceId: 'ATT-1',
      verifierId: 'u-verifier',
      outcome: VerificationOutcome.approved,
      reason: 'Matches profile photo.',
    );
    final res = await repo.decide(decision, expectedVersion: 3);
    res.fold((_) {}, (f) => fail('expected Ok: $f'));

    final req = adapter.requests.single;
    expect(req.path, '/verification/cases/ATT-1/decision');
    expect((req.data as Map)['outcome'], 'APPROVED');
    expect(req.headers['If-Match'], '3');
  });

  test(
    'a 412 (stale If-Match) response maps to FailureKind.conflict',
    () async {
      repo = build(
        (_) => _jsonBody({
          'error': {'message': 'stale'},
        }, status: 412),
      );
      const decision = VerificationDecision(
        attendanceId: 'ATT-1',
        verifierId: 'u-verifier',
        outcome: VerificationOutcome.approved,
        reason: 'Matches profile photo.',
      );
      final res = await repo.decide(decision, expectedVersion: 3);
      final failure = res.fold((_) => fail('expected Err'), (f) => f);
      expect(failure.kind, FailureKind.conflict);
    },
  );

  test('getCase parses the wire status', () async {
    repo = build(
      (_) => _jsonBody({
        'attendanceId': 'ATT-1',
        'version': 1,
        'status': 'APPROVED',
        'carpenterName': 'Karim Uddin',
        'carpenterIdMasked': '••••1234',
        'campaignName': 'Test Campaign',
        'sessionName': 'Session A',
        'capturedAt': '2026-07-30T00:00:00.000Z',
        'capturedImageUrl': 'https://example.test/captured.png',
        'referenceImageUrl': null,
        'band': 'MEDIUM',
        'referenceSource': 'APPROVED_BASELINE_PHOTO',
      }),
    );
    final res = await repo.getCase('ATT-1');
    final case_ = res.fold((v) => v, (f) => fail('expected Ok: $f'));
    expect(case_.status, AttendanceStatus.approved);
  });

  test(
    'an unknown wire status falls back visibly (crmReview), not a crash',
    () async {
      repo = build(
        (_) => _jsonBody({
          'attendanceId': 'ATT-1',
          'version': 1,
          'status': 'WAT',
          'carpenterName': 'Karim Uddin',
          'carpenterIdMasked': '••••1234',
          'campaignName': 'Test Campaign',
          'sessionName': 'Session A',
          'capturedAt': '2026-07-30T00:00:00.000Z',
          'capturedImageUrl': 'https://example.test/captured.png',
          'referenceImageUrl': null,
          'band': 'MEDIUM',
          'referenceSource': 'APPROVED_BASELINE_PHOTO',
        }),
      );
      final res = await repo.getCase('ATT-1');
      final case_ = res.fold((v) => v, (f) => fail('expected Ok: $f'));
      expect(case_.status, AttendanceStatus.crmReview);
    },
  );

  test(
    'decide sends RETURN_FOR_RECAPTURE and the supervisorOverride flag',
    () async {
      repo = build((_) => _jsonBody(null, status: 204));
      const decision = VerificationDecision(
        attendanceId: 'ATT-1',
        verifierId: 'u-verifier',
        outcome: VerificationOutcome.returnForRecapture,
        reason: 'Needs a clearer photo.',
        supervisorOverride: true,
      );
      final res = await repo.decide(decision, expectedVersion: 2);
      res.fold((_) {}, (f) => fail('expected Ok: $f'));

      final req = adapter.requests.last;
      expect((req.data as Map)['outcome'], 'RETURN_FOR_RECAPTURE');
      expect((req.data as Map)['supervisorOverride'], true);
    },
  );
}
