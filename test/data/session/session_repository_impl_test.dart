import 'dart:convert';
import 'dart:typed_data';

import 'package:acsl_campaign/data/session/session_repository_impl.dart';
import 'package:acsl_campaign/domain/session/campaign_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this._respond);
  final ResponseBody Function(RequestOptions o) _respond;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? __,
  ) async {
    requests.add(o);
    return _respond(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  SessionRepositoryImpl build(ResponseBody Function(RequestOptions) r) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _Adapter(r);
    return SessionRepositoryImpl(dio);
  }

  test('parses SCREAMING_SNAKE status from the list endpoint', () async {
    final repo = build(
      (_) => _json({
        'items': [
          {
            'id': 's1',
            'campaignId': 'c1',
            'venue': 'Hall',
            'status': 'CAPTURE_CLOSED',
            'capacity': 10,
            'readinessOk': false,
          },
        ],
      }),
    );
    final res = await repo.listForCampaign('c1');
    final list = res.fold((l) => l, (f) => fail('expected Ok: $f'));
    expect(list.single.status, SessionStatus.captureClosed);
  });

  test(
    'an unknown status is non-operational (captureClosed), never upcoming',
    () async {
      final repo = build(
        (_) => _json({
          'id': 's1',
          'campaignId': 'c1',
          'venue': 'Hall',
          'status': 'SOME_FUTURE_STATE',
          'capacity': 0,
          'readinessOk': false,
        }),
      );
      final res = await repo.start('s1');
      final s = res.fold((s) => s, (f) => fail('expected Ok: $f'));
      expect(
        s.status,
        SessionStatus.captureClosed,
        reason: 'unknown must not become a startable upcoming session',
      );
    },
  );

  test('actions POST to /sessions/<id>/<action>', () async {
    late RequestOptions seen;
    final repo = build((o) {
      seen = o;
      return _json({
        'id': 's1',
        'campaignId': 'c1',
        'venue': 'Hall',
        'status': 'PAUSED',
        'capacity': 0,
        'readinessOk': true,
      });
    });
    await repo.pause('s1');
    expect(seen.path, '/sessions/s1/pause');
    expect(seen.method, 'POST');
  });
}
