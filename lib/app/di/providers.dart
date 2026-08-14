import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audit/audit.dart';
import '../../core/audit/audit_emitter.dart';
import '../../core/audit/audit_transport.dart';
import '../../core/auth/auth_binding.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/e2e_session.dart';
import '../../core/auth/session_manager.dart';
import '../../core/auth/token_store.dart';
import '../../core/consent/notice_repository.dart';
import '../../core/files/file_source.dart';
import '../../core/media/capture_source.dart';
import '../../core/media/evidence_store.dart';
import '../../core/media/face_quality.dart';
import '../../core/media/media_encryptor.dart';
import '../../core/network/auth_interceptor.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/app_database.dart';
import '../../core/storage/evidence_key_store.dart';
import '../../core/storage/secure_store.dart';
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

/// 🔒 Contract-pending: swapped for [FakeAuthService] under E2E so Maestro
/// signs in through the same [SessionManager] path production does, instead
/// of bypassing it with a pre-built [Session].
///
/// Explicitly typed (`Provider<AuthService> authServiceProvider = ...` rather
/// than `final authServiceProvider = ...`): this provider, [dioProvider],
/// [sessionManagerProvider] and [authStateProvider] reference each other in a
/// cycle (`authServiceProvider` -> `dioProvider` -> `authStateProvider` ->
/// `sessionManagerProvider` -> `authServiceProvider`). The cycle itself is
/// harmless at runtime because every cross-reference inside `dioProvider`'s
/// `AuthInterceptor` callbacks is a lazy closure that runs per request, long
/// after all four providers are built - but without an explicit type on each
/// variable, the analyzer has to *infer* each one's type from its initializer
/// before it can check the others, and inference itself cannot go around a
/// cycle. An explicit type breaks that compile-time cycle without changing
/// the (lazy, safe) runtime one.
final Provider<AuthService> authServiceProvider = Provider<AuthService>((ref) {
  final config = ref.watch(appConfigProvider);
  // E2E normally signs in through a fake transport rather than skipping the
  // lifecycle, so Maestro exercises the same SessionManager path production
  // does. E2E_REAL_AUTH keeps the real one so at least one flow proves the
  // service we now own can actually issue a token — shipping an identity
  // provider no end-to-end test has logged into would repeat P0.6's central
  // mistake (spec D3).
  if (config.e2e && !config.e2eRealAuth) return FakeAuthService(config.e2eRole);
  return DioAuthService(ref.watch(dioProvider));
});

final Provider<TokenStore> tokenStoreProvider = Provider<TokenStore>(
  (ref) => createTokenStore(ref.watch(secureStoreProvider)),
);

/// The leaf that lets [dioProvider]'s AuthInterceptor reach live session
/// state WITHOUT a provider edge back into the auth graph — see [AuthBinding]
/// for the cycle it breaks and `auth_cycle_regression_test.dart` for the net.
final Provider<AuthBinding> authBindingProvider = Provider<AuthBinding>(
  (_) => AuthBinding(),
);

final Provider<SessionManager> sessionManagerProvider =
    Provider<SessionManager>((ref) {
      final manager = SessionManager(
        service: ref.watch(authServiceProvider),
        tokens: ref.watch(tokenStoreProvider),
      );
      ref.onDispose(manager.dispose);
      // Attach INSIDE the build, before any caller can hold the manager and
      // fire a request, so the interceptor is never live while unattached.
      ref.read(authBindingProvider).attach(manager);
      return manager;
    });

/// The router, the shell and every `PermissionGate` watch this.
///
/// Expiry is deliberately NOT re-checked here against `Session.expiresAt`:
/// [SessionManager.accessTokenForRequest] already proactively refreshes
/// inside a 60s skew and signs out on refresh failure, so an expired session
/// is caught on the next outbound *request*, not on every render of this
/// provider. Duplicating an expiry check on the render path would just make
/// the same decision twice from two different clocks (wall-clock read here vs.
/// the request-time read in `accessTokenForRequest`), and an idle screen with
/// no pending request has no user-visible harm in waiting for the next one to
/// discover expiry.
final Provider<AuthState> authStateProvider = Provider<AuthState>((ref) {
  final manager = ref.watch(sessionManagerProvider);
  final sub = manager.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return manager.state;
});

final Provider<Dio> dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  // AuthInterceptor.replay must dispatch through a client that does NOT carry
  // AuthInterceptor itself, or a second 401 on the replay would need a second
  // onError run - which deadlocks inside QueuedInterceptor's exclusive error
  // queue while the first onError is still awaiting replay(). buildReplayDio
  // shares buildDio's baseUrl/timeouts (so the replay resolves relative paths
  // like `/campaigns` against the real baseUrl, the original bug this task
  // fixes) but adds no interceptors of its own.
  final replayClient = buildReplayDio(baseUrl: config.apiBaseUrl);
  // The callbacks below reach session state through [AuthBinding] — a
  // dependency LEAF — never through ref.read(authStateProvider) or
  // ref.read(sessionManagerProvider). Those reads look harmless ("lazy
  // closures, run per request, long after every provider is built") but
  // Riverpod checks for cycles AT READ TIME, and both chains lead back to
  // dioProvider itself (authState -> sessionManager -> authService -> dio).
  // The very first request through the real DioAuthService — the login —
  // threw CircularDependencyError from inside onRequest, which broke every
  // real-auth sign-in while every FakeAuthService config stayed green (the
  // fake never watches dioProvider, so the closing edge never exists).
  // auth_cycle_regression_test.dart pins this with the un-overridden graph.
  final binding = ref.read(authBindingProvider);
  final interceptor = AuthInterceptor(
    readAccessToken: () => binding.accessToken,
    refreshToken: binding.refresh,
    onAuthLost: () => unawaited(binding.signOut()),
    replay: (options) => replayClient.fetch<dynamic>(options),
  );
  return buildDio(baseUrl: config.apiBaseUrl, authInterceptor: interceptor);
});

final campaignRepositoryProvider = Provider<CampaignRepository>(
  (ref) => CampaignRepositoryImpl(ref.watch(dioProvider)),
);

// ---- Offline sync stack (mobile field) ------------------------------------

/// Overridden only by tests, so the real [AppDatabase.open] can run against a
/// temp directory. `null` means "use path_provider", i.e. production.
final databaseDirectoryProvider = Provider<Future<Object> Function()?>(
  (ref) => null,
);

/// Also test-only. drift_flutter defaults this to `getTemporaryDirectory()`,
/// which has no plugin under `flutter_test` — the specific call that throws.
final tempDirectoryPathProvider = Provider<Future<String?> Function()?>(
  (ref) => null,
);

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open(
    databaseDirectory: ref.watch(databaseDirectoryProvider),
    tempDirectoryPath: ref.watch(tempDirectoryPathProvider),
  );
  // `unawaited` rather than the shorter `ref.onDispose(db.close)`: Dart's void
  // covariance accepts a `Future<void> Function()` where a `void Function()` is
  // expected, so the implicit form hides that the close is fire-and-forget.
  // That hazard already cost this branch once - an unawaited close let a temp
  // directory be removed under a live sqlite handle (invisible on POSIX,
  // `PathAccessException` on Windows), which is why test/support/harness.dart
  // registers its close before the container dispose. Behaviour is unchanged;
  // the intent is now visible to the next reader.
  ref.onDispose(() => unawaited(db.close()));
  return db;
});

final evidenceStoreProvider = Provider<EvidenceStore>(
  (ref) => createEvidenceStore(),
);

/// Resolves the consent notice shown before a capture, and caches fetched
/// versions.
///
/// The two Drift seams are the whole point of this provider: without them
/// `resolve` would silently always return the bundled floor and no device would
/// ever read or write a `consent_notices` row — a failure no other test in the
/// suite can see, because this is the only place [NoticeRepository] is
/// constructed. `test/features/capture_consent_test.dart` asserts both.
final noticeRepositoryProvider = Provider<NoticeRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return NoticeRepository(
    source: DioNoticeSource(ref.watch(dioProvider)),
    readCached: driftNoticeReader(db),
    writeCached: driftNoticeWriter(db),
  );
});

final secureStoreProvider = Provider<SecureStore>(
  (ref) => FlutterSecureStore(),
);

final auditTransportProvider = Provider<AuditTransport>(
  (ref) => DioAuditTransport(ref.watch(dioProvider)),
);

/// Started eagerly from `main()` — see [AuditFlusher.start]. Lazily creating it
/// on a feature's first read (as the sync engine is) would mean audit only
/// flushed once someone opened the offline-queue screen.
final auditFlusherProvider = Provider<AuditFlusher>((ref) {
  final flusher = AuditFlusher(
    db: ref.watch(appDatabaseProvider),
    transport: ref.watch(auditTransportProvider),
    connectivity: ref.watch(connectivityStreamProvider),
  );
  ref.onDispose(() => unawaited(flusher.dispose()));
  return flusher;
});

final auditSinkProvider = Provider<AuditSink>((ref) {
  final flusher = ref.watch(auditFlusherProvider);
  return DurableAuditSink(
    db: ref.watch(appDatabaseProvider),
    transport: ref.watch(auditTransportProvider),
    onBuffered: flusher.notifyBuffered,
  );
});

final evidenceKeyStoreProvider = Provider<EvidenceKeyStore>(
  (ref) => EvidenceKeyStore(
    store: ref.watch(secureStoreProvider),
    audit: ref.watch(auditSinkProvider),
  ),
);

/// 32-byte AES key for evidence encryption, generated once and held in secure
/// storage (Keystore/Keychain-backed on mobile). Never logged or exported.
final mediaEncryptorProvider = Provider<MediaEncryptor>((ref) {
  final keys = ref.watch(evidenceKeyStoreProvider);
  return AesGcmEncryptor(keys.loadOrCreate);
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

/// Real file picker in production; a bundled-asset fake under E2E so Maestro
/// can drive the bulk-import flow without a native file dialog.
final fileSourceProvider = Provider<FileSource>((ref) {
  final config = ref.watch(appConfigProvider);
  return config.e2e ? const FakeFileSource() : const RealFileSource();
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
