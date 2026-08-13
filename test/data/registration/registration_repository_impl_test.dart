import 'dart:convert';
import 'dart:typed_data';

import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:acsl_campaign/data/registration/registration_repository_impl.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every request and answers a canned response — the transport-level
/// twin of slice-1 Task 10's key-string tests.
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

const _carpenterJson = {
  'id': 'CARP_NEW',
  'name': 'New Person',
  'displayId': 'CARP-••0042',
  'phoneSuffix': '0042',
  'territory': '',
  'dealerContext': null,
  'thumbnailUrl': null,
  'eligible': true,
  'syncStatus': 'PENDING_PROFILE_SYNC',
};

void main() {
  late _RecordingAdapter adapter;
  late RegistrationRepositoryImpl repo;
  late AppDatabase db;

  RegistrationRepositoryImpl build(
    ResponseBody Function(RequestOptions) respond,
  ) {
    adapter = _RecordingAdapter(respond);
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    return RegistrationRepositoryImpl(dio, db);
  }

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  final uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('register sends a UUID v4 idempotency key, fresh per call', () async {
    repo = build((_) => _jsonBody({'registered': 1, 'alreadyRegistered': 0}));

    await repo.register('camp-1', ['c-1']);
    await repo.register('camp-1', ['c-1']);

    final keys = [
      for (final r in adapter.requests) r.headers['Idempotency-Key'] as String,
    ];
    expect(
      keys[0],
      matches(uuidV4),
      reason:
          'the old comma-joined carpenter-id key collides across '
          'users and leaks ids into header logs',
    );
    expect(keys[1], matches(uuidV4));
    expect(
      keys[0],
      isNot(keys[1]),
      reason: 'a new submit is a new operation, not a replay',
    );
  });

  test('requestNewProfile parses the 201 and returns the provisional '
      'carpenter', () async {
    repo = build(
      (_) => _jsonBody({
        'requestId': 'REQ-1',
        'carpenter': _carpenterJson,
      }, status: 201),
    );

    final result = await repo.requestNewProfile('camp-1', 'New', '+88017');
    final carpenter = result.fold((c) => c, (f) => fail('expected Ok: $f'));
    expect(carpenter.id, 'CARP_NEW');
    expect(carpenter.displayId, 'CARP-••0042');
  });

  test('an absent attendanceState maps to notCaptured explicitly', () async {
    repo = build(
      (_) => _jsonBody({
        'items': [_carpenterJson], // no attendanceState key at all
      }),
    );
    final result = await repo.searchMaster('new');
    final items = result.fold((v) => v, (f) => fail('expected Ok: $f'));
    expect(items.single.attendanceState.name, 'notCaptured');
  });
}
