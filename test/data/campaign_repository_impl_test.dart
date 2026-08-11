import 'package:acsl_campaign/core/network/correlation_interceptor.dart';
import 'package:acsl_campaign/data/campaign/campaign_repository_impl.dart';
import 'package:acsl_campaign/domain/campaign/campaign_draft.dart';
import 'package:acsl_campaign/domain/campaign/campaign_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/scripted_adapter.dart';

/// Task 10 fix-round (F2): the idempotency keys, `version` and
/// `acknowledgedWarnings` wiring added to [CampaignRepositoryImpl] had no
/// test coverage — verified only by a reviewer reading the diff, which dies
/// with the review. These assert on the actual `RequestOptions` the
/// repository hands to the transport, the same harness
/// `test/core/network/trace_threading_test.dart` uses for the correlation id.
void main() {
  late ScriptedAdapter adapter;
  late CampaignRepositoryImpl repo;

  setUp(() {
    adapter = ScriptedAdapter([
      const ScriptedReply.json(200, {
        'id': 'c1',
        'name': 'Q3 Drive',
        'type': 'seminar',
        'organizationId': 'org-1',
        'status': 'DRAFT',
        'ownerId': 'user-1',
        'startAt': null,
        'endAt': null,
        'venue': null,
        'objective': null,
        'territoryIds': <String>[],
        'targetAudience': 0,
        'verifiedAttendance': 0,
        'version': 7,
      }),
    ]);
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(const CorrelationIdInterceptor());
    repo = CampaignRepositoryImpl(dio);
  });

  RequestOptions sentRequest() => adapter.requests.single;
  String? sentIdempotencyKey() {
    final value =
        sentRequest().headers[CorrelationIdInterceptor.idempotencyHeaderName];
    return value is String ? value : null;
  }

  group('createDraft', () {
    test('sends a create:<token> idempotency key', () async {
      await repo.createDraft(const CampaignDraft());

      final key = sentIdempotencyKey();
      expect(key, isNotNull);
      expect(key, startsWith('create:'));
      // A fresh key per call — user-level double-submit is already blocked
      // by the wizard's own `saving`/`submitting` flags; this only has to
      // survive a transport-level retry of the SAME request, which reuses
      // the RequestOptions rather than minting a new key.
      expect(key, isNot('create:'));
    });

    test('two separate createDraft calls mint two different keys', () async {
      await repo.createDraft(const CampaignDraft());
      final firstKey = sentIdempotencyKey();

      adapter.requests.clear();
      await repo.createDraft(const CampaignDraft());
      final secondKey = sentIdempotencyKey();

      expect(firstKey, isNot(secondKey));
    });

    test('body carries no version — a create has no prior version', () async {
      await repo.createDraft(const CampaignDraft(name: 'Q3 Drive'));

      final body = sentRequest().data as Map<String, Object?>;
      expect(body.containsKey('version'), isFalse);
      expect(body['name'], 'Q3 Drive');
    });
  });

  group('updateDraft', () {
    test('sends version in the body and no idempotency key', () async {
      await repo.updateDraft(
        'CMP-1',
        const CampaignDraft(name: 'Edited'),
        version: 4,
      );

      final req = sentRequest();
      expect(req.method, 'PUT');
      final body = req.data as Map<String, Object?>;
      expect(body['version'], 4);
      expect(body['name'], 'Edited');
      expect(sentIdempotencyKey(), isNull);
    });
  });

  group('submitForApproval', () {
    test('sends version in the body and a submit:id:version key', () async {
      await repo.submitForApproval('CMP-1', version: 2);

      final req = sentRequest();
      expect((req.data as Map<String, Object?>)['version'], 2);
      expect(sentIdempotencyKey(), 'submit:CMP-1:2');
    });

    test('a resubmit at a newer version mints a DIFFERENT key — not mistaken '
        'for a replay of the first', () async {
      await repo.submitForApproval('CMP-1', version: 2);
      final firstKey = sentIdempotencyKey();

      adapter.requests.clear();
      await repo.submitForApproval('CMP-1', version: 3);
      final secondKey = sentIdempotencyKey();

      expect(firstKey, 'submit:CMP-1:2');
      expect(secondKey, 'submit:CMP-1:3');
    });
  });

  group('decide', () {
    test('sends the SCREAMING_SNAKE decision, version, acknowledgedWarnings, '
        'and a decide:id:version key', () async {
      await repo.decide(
        'CMP-1',
        decision: CampaignDecision.returnForCorrection,
        reason: 'Missing budget reference',
        version: 5,
        acknowledgedWarnings: const ['TARGET_EXCEEDS_SESSION_CAPACITY'],
      );

      final body = sentRequest().data as Map<String, Object?>;
      expect(body['decision'], 'RETURN_FOR_CORRECTION');
      expect(body['reason'], 'Missing budget reference');
      expect(body['version'], 5);
      expect(body['acknowledgedWarnings'], ['TARGET_EXCEEDS_SESSION_CAPACITY']);
      expect(sentIdempotencyKey(), 'decide:CMP-1:5');
    });

    test('an empty acknowledgedWarnings list is sent, not omitted', () async {
      await repo.decide(
        'CMP-1',
        decision: CampaignDecision.approve,
        version: 1,
        acknowledgedWarnings: const [],
      );

      final body = sentRequest().data as Map<String, Object?>;
      expect(body['acknowledgedWarnings'], <String>[]);
    });
  });
}
