import 'dart:convert';
import 'dart:typed_data';

import 'package:acsl_campaign/data/import/import_repository_impl.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/domain/import/import_job.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every request and answers a canned response — the transport-level
/// twin of 2a's `test/data/registration/registration_repository_impl_test.dart`.
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

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  late _RecordingAdapter adapter;
  late ImportRepositoryImpl repo;

  ImportRepositoryImpl build(ResponseBody Function(RequestOptions) respond) {
    adapter = _RecordingAdapter(respond);
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    return ImportRepositoryImpl(dio);
  }

  test('poll parses the job and its row outcomes explicitly', () async {
    repo = build(
      (_) => _jsonBody({
        'id': 'IMPORT-1',
        'campaignId': 'camp-1',
        'status': 'READY_TO_COMMIT',
        'totalRows': 2,
        'processedRows': 2,
        'rows': [
          {'rowId': 'row-1', 'name': 'Md. Karim', 'outcome': 'VALID'},
          {'rowId': 'row-2', 'name': 'X', 'outcome': 'NEEDS_PROFILE'},
        ],
      }),
    );
    final res = await repo.poll('IMPORT-1');
    final job = res.fold((j) => j, (f) => fail('expected Ok: $f'));
    expect(job.status, ImportStatus.readyToCommit);
    expect(job.rows.map((r) => r.outcome), [
      ImportRowOutcome.valid,
      ImportRowOutcome.needsProfile,
    ]);
    expect(adapter.requests.single.path, '/imports/IMPORT-1');
  });

  test('an unknown wire status is a visible failed job, not a silent '
      'default', () async {
    repo = build(
      (_) => _jsonBody({
        'id': 'IMPORT-1',
        'campaignId': 'camp-1',
        'status': 'SOME_FUTURE_STATUS',
        'rows': [],
      }),
    );
    final res = await repo.poll('IMPORT-1');
    final job = res.fold((j) => j, (f) => fail('expected Ok: $f'));
    expect(job.status, ImportStatus.failed);
  });

  test('an unknown row outcome maps to error, not a silent default', () async {
    repo = build(
      (_) => _jsonBody({
        'id': 'IMPORT-1',
        'campaignId': 'camp-1',
        'status': 'READY_TO_COMMIT',
        'rows': [
          {'rowId': 'row-1', 'name': 'X', 'outcome': 'SOME_FUTURE_OUTCOME'},
        ],
      }),
    );
    final res = await repo.poll('IMPORT-1');
    final job = res.fold((j) => j, (f) => fail('expected Ok: $f'));
    expect(job.rows.single.outcome, ImportRowOutcome.error);
  });

  test(
    'commit posts to the namespaced path with a UUID idempotency key',
    () async {
      repo = build(
        (_) => _jsonBody({
          'id': 'IMPORT-1',
          'campaignId': 'camp-1',
          'status': 'COMPLETED',
          'rows': [],
        }),
      );
      await repo.commit('camp-1', 'IMPORT-1');
      final req = adapter.requests.single;
      expect(req.path, '/campaigns/camp-1/imports/IMPORT-1/commit');
      expect(req.headers['Idempotency-Key'], matches(_uuidV4));
    },
  );

  test('commit mints a fresh idempotency key per call', () async {
    repo = build(
      (_) => _jsonBody({
        'id': 'IMPORT-1',
        'campaignId': 'camp-1',
        'status': 'COMPLETED',
        'rows': [],
      }),
    );
    await repo.commit('camp-1', 'IMPORT-1');
    await repo.commit('camp-1', 'IMPORT-1');
    final keys = [
      for (final r in adapter.requests) r.headers['Idempotency-Key'] as String,
    ];
    expect(keys[0], isNot(keys[1]));
  });
}
