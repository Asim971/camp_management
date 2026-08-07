import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_manager.dart';
import '../../core/design_system/placeholder_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/bulk_import/presentation/bulk_import_screen.dart';
import '../../features/camera_capture/presentation/capture_flow_screen.dart';
import '../../features/campaign_approval/presentation/campaign_approval_screen.dart';
import '../../features/campaign_detail/presentation/campaign_detail_screen.dart';
import '../../features/campaign_list/presentation/campaign_list_screen.dart';
import '../../features/campaign_wizard/presentation/campaign_wizard_screen.dart';
import '../../features/carpenter_search/presentation/carpenter_search_screen.dart';
import '../../features/crm_case/presentation/crm_case_screen.dart';
import '../../features/dev/presentation/dev_launcher_screen.dart';
import '../../features/gallery/presentation/gallery_screen.dart';
import '../../features/offline_queue/presentation/offline_queue_screen.dart';
import '../../features/registration/presentation/registration_workspace_screen.dart';
import '../di/providers.dart';
import 'route_guards.dart';
import 'route_table.dart';

// TEMPORARY (removed in the providers-wiring task): bridges the old
// authControllerProvider to the new AuthState shape.
final authStateProvider = Provider<AuthState>((ref) {
  final session = ref.watch(authControllerProvider);
  return session == null ? const AuthSignedOut() : AuthSignedIn(session);
});

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
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: '/forbidden',
        builder: (_, __) =>
            const PlaceholderScreen(title: 'Access denied', screenId: 'RBAC'),
      ),
      // Dev-only surfaces. Registered by AppConfig.devRoutesEnabled, so they
      // are genuinely absent from a production build rather than merely
      // unlinked — /dev used to be reachable by URL in prod web.
      if (config.devRoutesEnabled) ...[
        GoRoute(path: '/dev', builder: (_, __) => const DevLauncherScreen()),
        GoRoute(path: '/gallery', builder: (_, __) => const GalleryScreen()),
      ],
      GoRoute(
        path: '/',
        builder: (_, __) => const PlaceholderScreen(
          title: 'Campaign Dashboard',
          screenId: 'W-01',
          prdRefs: ['CM-FR-080..087'],
        ),
      ),
      GoRoute(
        path: '/campaigns',
        builder: (_, __) => const CampaignListScreen(),
        routes: [
          // Static 'new' must precede the ':id' param route.
          GoRoute(
            path: 'new',
            builder: (_, __) => const CampaignWizardScreen(),
          ),
          GoRoute(
            path: ':id',
            builder: (_, state) =>
                CampaignDetailScreen(campaignId: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'approve',
                builder: (_, state) => CampaignApprovalScreen(
                  campaignId: state.pathParameters['id']!,
                ),
              ),
              GoRoute(
                path: 'register',
                builder: (_, state) => RegistrationWorkspaceScreen(
                  campaignId: state.pathParameters['id']!,
                ),
              ),
              GoRoute(
                path: 'import',
                builder: (_, state) =>
                    BulkImportScreen(campaignId: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/verification',
        builder: (_, __) => const PlaceholderScreen(
          title: 'Verification Queue',
          screenId: 'C-01',
          prdRefs: ['CM-FR-060, 067'],
        ),
        routes: [
          GoRoute(
            path: 'cases/:id',
            builder: (_, state) =>
                CrmCaseScreen(attendanceId: state.pathParameters['id']!),
          ),
        ],
      ),
      // Mobile field: search → capture, plus the offline queue monitor.
      GoRoute(
        path: '/search/:sessionId',
        builder: (_, state) => CarpenterSearchScreen(
          sessionId: state.pathParameters['sessionId']!,
        ),
      ),
      GoRoute(
        path: '/capture/:sessionId/:carpenterId',
        builder: (_, state) => CaptureFlowScreen(
          sessionId: state.pathParameters['sessionId']!,
          carpenterId: state.pathParameters['carpenterId']!,
        ),
      ),
      GoRoute(path: '/queue', builder: (_, __) => const OfflineQueueScreen()),
      GoRoute(
        path: '/analytics',
        builder: (_, __) => const PlaceholderScreen(
          title: 'Campaign Analytics',
          screenId: 'A-02',
          prdRefs: ['CM-FR-080..087'],
        ),
      ),
    ],
  );
});

/// The route templates the router registers, for the exhaustiveness test in
/// `route_table_test.dart`. Kept beside the route definitions so the two
/// cannot drift: if a GoRoute is added here it must be listed here too, and
/// the test then demands a matching `routeTable` entry.
Set<String> registeredRoutePaths({required bool devRoutesEnabled}) => {
  '/login',
  '/forbidden',
  if (devRoutesEnabled) ...devOnlyPaths,
  '/',
  '/campaigns',
  '/campaigns/new',
  '/campaigns/:id',
  '/campaigns/:id/approve',
  '/campaigns/:id/register',
  '/campaigns/:id/import',
  '/verification',
  '/verification/cases/:id',
  '/search/:sessionId',
  '/capture/:sessionId/:carpenterId',
  '/queue',
  '/analytics',
};

/// Bridges Riverpod auth state to GoRouter's Listenable refresh.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
  }
}
