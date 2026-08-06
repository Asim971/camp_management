import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/auth/e2e_session.dart';
import '../../core/auth/session.dart';
import '../../core/media/capture_source.dart';
import '../../core/media/evidence_store.dart';
import '../../core/media/face_quality.dart';
import '../../core/media/media_encryptor.dart';
import '../../core/network/auth_interceptor.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/app_database.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_engine_impl.dart';
import '../../core/sync/sync_uploader.dart';
import '../../data/campaign/campaign_repository_impl.dart';
import '../../data/import/import_repository_impl.dart';
import '../../data/registration/registration_repository_impl.dart';
import '../../data/session/session_repository_impl.dart';
import '../../data/verification/verification_repository_impl.dart';
import '../../domain/campaign/campaign_repository.dart';
import '../../domain/import/import_repository.dart';
import '../../domain/registration/registration_repository.dart';
import '../../domain/session/session_repository.dart';
import '../../domain/verification/verification_repository.dart';
import '../flavors.dart';

/// Composition root. Every core service and repository is exposed as a
/// provider so features depend on abstractions and tests can override them
/// (Task T-0.6.1). Keep feature-specific providers inside their feature folder.

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

/// Authenticated session (null == signed out). The router watches this.
class AuthController extends Notifier<Session?> {
  @override
  Session? build() {
    final config = ref.read(appConfigProvider);
    if (config.e2e) return buildE2ESession(config.e2eRole); // test-only
    return null;
  }

  // ignore: use_setters_to_change_properties
  void setSession(Session session) => state = session;
  void clear() => state = null;

  // TODO(T-0.4.1): wire login/refresh against the auth service contract.
}

final authControllerProvider = NotifierProvider<AuthController, Session?>(
  AuthController.new,
);

final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  // The interceptor needs the client it lives in, so bind lazily: `dio` is
  // assigned before any request can run, so the closure never sees it unset.
  late final Dio dio;
  final interceptor = AuthInterceptor(
    readAccessToken: () => ref.read(authControllerProvider)?.accessToken,
    refreshToken: () async {
      // TODO(T-0.4.1): call refresh endpoint; return new token or null.
      throw UnimplementedError('Auth refresh pending service contract');
    },
    onAuthLost: () => ref.read(authControllerProvider.notifier).clear(),
    replay: (options) => dio.fetch<dynamic>(options),
  );
  dio = buildDio(baseUrl: config.apiBaseUrl, authInterceptor: interceptor);
  return dio;
});

final campaignRepositoryProvider = Provider<CampaignRepository>(
  (ref) => CampaignRepositoryImpl(ref.watch(dioProvider)),
);

// ---- Offline sync stack (mobile field) ------------------------------------

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final evidenceStoreProvider = Provider<EvidenceStore>(
  (ref) => createEvidenceStore(),
);

final secureStorageProvider = Provider<FlutterSecureStorage>(
  // v10 defaults resetOnError to true, which silently deletes a value it cannot
  // decrypt. For the evidence key that would orphan every queued capture with
  // no signal, so opt out and handle the failure explicitly in
  // loadOrCreateEvidenceKey.
  (ref) =>
      const FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: false)),
);

/// Storage key for the evidence-encryption secret. Do not rename: renaming
/// abandons any key already on the device, and with it the ability to decrypt
/// evidence encrypted under it.
const _evidenceKeyName = 'evidence_aes_key_v1';

/// Loads the 32-byte AES key used to encrypt attendance evidence, generating
/// and persisting one on first run.
///
/// Extracted from [mediaEncryptorProvider] so the failure paths are testable:
/// what happens here decides whether queued evidence stays decryptable.
Future<List<int>> loadOrCreateEvidenceKey(FlutterSecureStorage storage) async {
  String? existing;
  try {
    existing = await storage.read(key: _evidenceKeyName);
  } on PlatformException catch (error) {
    // A key exists but cannot be decrypted - after the v10 cipher change, an OS
    // keystore reset, or a restore onto a different device. Regenerating keeps
    // capture working, but every piece of evidence encrypted under the previous
    // key becomes undecryptable, so this must never look like a normal first
    // run. A durable audit event belongs here once T-0.3.6 wires an AuditSink.
    debugPrint(
      'Evidence key could not be read ($error). Generating a new one; evidence '
      'encrypted under the previous key can no longer be decrypted.',
    );
  }
  if (existing != null) return base64Decode(existing);
  final rng = Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  await storage.write(key: _evidenceKeyName, value: base64Encode(bytes));
  return bytes;
}

/// 32-byte AES key for evidence encryption, generated once and held in secure
/// storage (Keystore/Keychain-backed). Never logged or exported.
final mediaEncryptorProvider = Provider<MediaEncryptor>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return AesGcmEncryptor(() => loadOrCreateEvidenceKey(storage));
});

final faceQualityCheckerProvider = Provider<FaceQualityChecker>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.e2e) {
    return E2EQualityChecker(failFirst: config.e2eQuality == 'fail');
  }
  return const PassthroughQualityChecker(); // TODO(T-2.2.2): ML Kit impl
});

/// Real camera in production; a deterministic fake under E2E.
final captureSourceProvider = Provider<CaptureSource>((ref) {
  final config = ref.watch(appConfigProvider);
  return config.e2e ? FakeCaptureSource() : CameraCaptureSource();
});

final syncUploaderProvider = Provider<SyncUploader>(
  (ref) => DioSyncUploader(
    ref.watch(dioProvider),
    evidenceStore: ref.watch(evidenceStoreProvider),
  ),
);

final verificationRepositoryProvider = Provider<VerificationRepository>(
  (ref) => VerificationRepositoryImpl(ref.watch(dioProvider)),
);

final registrationRepositoryProvider = Provider<RegistrationRepository>(
  (ref) => RegistrationRepositoryImpl(
    ref.watch(dioProvider),
    ref.watch(appDatabaseProvider),
  ),
);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepositoryImpl(ref.watch(dioProvider)),
);

final importRepositoryProvider = Provider<ImportRepository>(
  (ref) => ImportRepositoryImpl(ref.watch(dioProvider)),
);

/// Emits `true` whenever the device regains any connectivity, driving an
/// automatic queue drain. Exposed as a plain `Stream` (not a `StreamProvider`)
/// because the sync engine consumes the stream directly and nothing renders it
/// as an `AsyncValue`.
final connectivityStreamProvider = Provider<Stream<bool>>(
  (ref) => Connectivity().onConnectivityChanged.map(
    (results) => results.any((r) => r != ConnectivityResult.none),
  ),
);

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngineImpl(
    db: ref.watch(appDatabaseProvider),
    uploader: ref.watch(syncUploaderProvider),
    evidenceStore: ref.watch(evidenceStoreProvider),
    isOnline: () async {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    },
    connectivityStream: ref.watch(connectivityStreamProvider),
  );
  ref.onDispose(engine.dispose);
  return engine;
});
