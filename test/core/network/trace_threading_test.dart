import 'package:acsl_campaign/core/network/correlation_interceptor.dart';
import 'package:acsl_campaign/core/trace/trace_id.dart';
import 'package:acsl_campaign/data/campaign/campaign_repository_impl.dart';
import 'package:acsl_campaign/domain/campaign/campaign_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_adapter.dart';

void main() {
  late ScriptedAdapter adapter;
  late CampaignRepositoryImpl repo;

  setUp(() {
    adapter = ScriptedAdapter([const ScriptedReply.status(200)]);
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(const CorrelationIdInterceptor());
    repo = CampaignRepositoryImpl(dio);
  });

  String? sentCorrelationId() {
    final value =
        adapter.requests.single.headers[CorrelationIdInterceptor.headerName];
    return value is String ? value : null;
  }

  test('submitForApproval forwards the caller trace id', () async {
    await repo.submitForApproval(
      'CMP-1',
      version: 1,
      trace: const TraceId.of('action-1'),
    );

    expect(sentCorrelationId(), 'action-1');
  });

  test('decide forwards the caller trace id', () async {
    await repo.decide(
      'CMP-1',
      decision: CampaignDecision.approve,
      version: 1,
      acknowledgedWarnings: const [],
      trace: const TraceId.of('action-2'),
    );

    expect(sentCorrelationId(), 'action-2');
  });

  test('a call with no trace still gets a minted id', () async {
    // Unscoped traffic must never be untraceable.
    await repo.getById('CMP-1');

    expect(sentCorrelationId(), isNotNull);
    expect(sentCorrelationId(), isNotEmpty);
  });
}
