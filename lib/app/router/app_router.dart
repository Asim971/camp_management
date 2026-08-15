import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/placeholder_screen.dart';
import '../../core/motion/transitions.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/bulk_import/presentation/bulk_import_screen.dart';
import '../../features/camera_capture/presentation/capture_flow_screen.dart';
import '../../features/campaign_approval/presentation/campaign_approval_screen.dart';
import '../../features/campaign_detail/presentation/campaign_detail_screen.dart';
import '../../features/campaign_list/presentation/campaign_list_screen.dart';
import '../../features/campaign_wizard/presentation/campaign_wizard_screen.dart';
import '../../features/carpenter_search/presentation/carpenter_search_screen.dart';
import '../../features/crm_case/presentation/crm_case_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/dev/presentation/dev_launcher_screen.dart';
import '../../features/gallery/presentation/gallery_screen.dart';
import '../../features/offline_queue/presentation/offline_queue_screen.dart';
import '../../features/registration/presentation/registration_workspace_screen.dart';
import '../../features/settings/presentation/language_screen.dart';
import '../../features/verification_queue/presentation/verification_queue_screen.dart';
import '../di/providers.dart';
import 'route_guards.dart';

/// App router. Redirect guards enforce auth + RBAC scope before a route builds
/// (§7). Deep-linkable web URLs, but NEVER PII/media tokens in the path.
final routerProvider = Provider<GoRouter>((ref) {
  const guards = RouteGuards();
  final config = ref.read(appConfigProvider);

  return GoRouter(
    initialLocation: config.e2e ? '/dev' : '/',
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      return guards.evaluate(
        auth: auth,
        fullPath: state.fullPath,
        location: state.matchedLocation,
        intended: state.uri.queryParameters['from'],
      );
    },
    // Rebuild redirects when auth changes.
    refreshListenable: _AuthListenable(ref),
    routes: _appRoutes(devRoutesEnabled: config.devRoutesEnabled),
  );
});

/// The actual GoRoute tree. Extracted from [routerProvider] so
/// [registeredRoutePaths] can walk the SAME route objects the app registers,
/// instead of a hand-maintained literal that could silently drift from them.
List<RouteBase> _appRoutes({required bool devRoutesEnabled}) => [
  GoRoute(
    path: '/login',
    pageBuilder: (_, state) =>
        fadeThroughPage(key: state.pageKey, child: const LoginScreen()),
  ),
  GoRoute(
    path: '/forbidden',
    pageBuilder: (_, state) => fadeThroughPage(
      key: state.pageKey,
      child: const PlaceholderScreen(title: 'Access denied', screenId: 'RBAC'),
    ),
  ),
  // Dev-only surfaces. Registered by AppConfig.devRoutesEnabled, so they
  // are genuinely absent from a production build rather than merely
  // unlinked — /dev used to be reachable by URL in prod web.
  if (devRoutesEnabled) ...[
    GoRoute(
      path: '/dev',
      pageBuilder: (_, state) =>
          fadeThroughPage(key: state.pageKey, child: const DevLauncherScreen()),
    ),
    GoRoute(
      path: '/gallery',
      pageBuilder: (_, state) =>
          fadeThroughPage(key: state.pageKey, child: const GalleryScreen()),
    ),
  ],
  GoRoute(
    path: '/',
    pageBuilder: (_, state) =>
        fadeThroughPage(key: state.pageKey, child: const DashboardScreen()),
  ),
  GoRoute(
    path: '/campaigns',
    pageBuilder: (_, state) =>
        fadeThroughPage(key: state.pageKey, child: const CampaignListScreen()),
    routes: [
      // Static 'new' must precede the ':id' param route.
      GoRoute(
        path: 'new',
        pageBuilder: (_, state) => sharedAxisPage(
          key: state.pageKey,
          child: const CampaignWizardScreen(),
        ),
      ),
      GoRoute(
        path: ':id',
        pageBuilder: (_, state) => sharedAxisPage(
          key: state.pageKey,
          child: CampaignDetailScreen(campaignId: state.pathParameters['id']!),
        ),
        routes: [
          GoRoute(
            path: 'approve',
            pageBuilder: (_, state) => sharedAxisPage(
              key: state.pageKey,
              child: CampaignApprovalScreen(
                campaignId: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: 'register',
            pageBuilder: (_, state) => sharedAxisPage(
              key: state.pageKey,
              child: RegistrationWorkspaceScreen(
                campaignId: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: 'import',
            pageBuilder: (_, state) => sharedAxisPage(
              key: state.pageKey,
              child: BulkImportScreen(campaignId: state.pathParameters['id']!),
            ),
          ),
        ],
      ),
    ],
  ),
  GoRoute(
    path: '/verification',
    pageBuilder: (_, state) => fadeThroughPage(
      key: state.pageKey,
      child: const VerificationQueueScreen(),
    ),
    routes: [
      GoRoute(
        path: 'cases/:id',
        pageBuilder: (_, state) => sharedAxisPage(
          key: state.pageKey,
          child: CrmCaseScreen(attendanceId: state.pathParameters['id']!),
        ),
      ),
    ],
  ),
  // Mobile field: search → capture, plus the offline queue monitor.
  GoRoute(
    path: '/search/:sessionId',
    pageBuilder: (_, state) => fadeThroughPage(
      key: state.pageKey,
      child: CarpenterSearchScreen(
        sessionId: state.pathParameters['sessionId']!,
      ),
    ),
  ),
  GoRoute(
    path: '/capture/:sessionId/:carpenterId',
    pageBuilder: (_, state) => sharedAxisPage(
      key: state.pageKey,
      child: CaptureFlowScreen(
        sessionId: state.pathParameters['sessionId']!,
        carpenterId: state.pathParameters['carpenterId']!,
      ),
    ),
  ),
  GoRoute(
    path: '/queue',
    pageBuilder: (_, state) =>
        fadeThroughPage(key: state.pageKey, child: const OfflineQueueScreen()),
  ),
  GoRoute(
    path: '/analytics',
    pageBuilder: (_, state) => fadeThroughPage(
      key: state.pageKey,
      child: const PlaceholderScreen(
        title: 'Campaign Analytics',
        screenId: 'A-02',
        prdRefs: ['CM-FR-080..087'],
      ),
    ),
  ),
  GoRoute(
    path: '/settings/language',
    pageBuilder: (_, state) =>
        fadeThroughPage(key: state.pageKey, child: const LanguageScreen()),
  ),
];

/// The route templates the router registers, for the exhaustiveness test in
/// `route_table_test.dart`.
///
/// Derived from the actual [_appRoutes] tree via a throwaway [GoRouter]'s
/// public `configuration`, rather than a hand-maintained literal: a literal
/// can drift from the real GoRoute tree while still happening to agree with
/// `routeTable`, and `route_table_test.dart`'s exhaustiveness assertion would
/// then pass against that stale pair without ever exercising what actually
/// gets registered.
Set<String> registeredRoutePaths({required bool devRoutesEnabled}) {
  final routes = _appRoutes(devRoutesEnabled: devRoutesEnabled);
  final router = GoRouter(routes: routes, initialLocation: '/login');
  return _fullPaths(router.configuration, routes);
}

Set<String> _fullPaths(
  RouteConfiguration configuration,
  List<RouteBase> routes,
) {
  final paths = <String>{};
  for (final route in routes) {
    if (route is GoRoute) {
      final path = configuration.locationForRoute(route);
      if (path != null) paths.add(path);
    }
    paths.addAll(_fullPaths(configuration, route.routes));
  }
  return paths;
}

/// Bridges Riverpod auth state to GoRouter's Listenable refresh.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
  }
}
