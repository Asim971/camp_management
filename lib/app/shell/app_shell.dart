import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_manager.dart';
import '../../core/responsive/adaptive_scaffold.dart';
import '../di/providers.dart';
import 'nav_destinations.dart';

/// The session-aware app shell (§3.3).
///
/// Wraps [AdaptiveScaffold]'s pure responsive layout with everything that
/// depends on who is signed in: permission-filtered destinations, the
/// breadcrumb, a notifications slot, and the account menu with sign-out.
class AppShell extends ConsumerWidget {
  const AppShell({
    required this.title,
    required this.body,
    this.actions = const [],
    this.breadcrumb = const [],
    super.key,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;

  /// Ancestor labels, outermost first. The current screen is [title] and is
  /// not repeated here.
  final List<String> breadcrumb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final destinations = visibleDestinations(auth);
    final location = GoRouterState.of(context).matchedLocation;

    return AdaptiveScaffold(
      title: title,
      destinations: destinations,
      selectedIndex: selectedIndexFor(destinations, location),
      onDestinationSelected: (i) => context.go(destinations[i].path),
      actions: [
        ...actions,
        // Notifications slot (§3.3). Wired to a real feed by a later epic; the
        // slot exists now so the shell's geometry is settled.
        const IconButton(
          tooltip: 'Notifications (not yet available)',
          icon: Icon(Icons.notifications_none),
          onPressed: null,
        ),
        _AccountMenu(auth: auth),
      ],
      body: breadcrumb.isEmpty
          ? body
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Breadcrumb(trail: breadcrumb, current: title),
                const SizedBox(height: 8),
                Expanded(child: body),
              ],
            ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.trail, required this.current});

  final List<String> trail;
  final String current;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Semantics(
      label: 'Breadcrumb: ${[...trail, current].join(', ')}',
      excludeSemantics: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final label in trail) ...[
            Text(label, style: style),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.chevron_right, size: 14, color: style?.color),
            ),
          ],
          Text(current, style: style?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({required this.auth});

  final AuthState auth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = switch (auth) {
      AuthSignedIn(:final session) => session.displayName,
      _ => null,
    };
    if (name == null) return const SizedBox.shrink();

    // Semantics identifiers (not Keys) so Maestro flows can open the menu and
    // reach the language picker: `id:` maps to Semantics(identifier:).
    return Semantics(
      identifier: 'account_menu',
      child: PopupMenuButton<String>(
        tooltip: 'Account',
        icon: const Icon(Icons.account_circle_outlined),
        onSelected: (value) async {
          switch (value) {
            case 'language':
              context.go('/settings/language');
            case 'signOut':
              await ref.read(sessionManagerProvider).signOut();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem<String>(enabled: false, child: Text(name)),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'language',
            child: Semantics(
              identifier: 'account_language',
              child: const Text('Language'),
            ),
          ),
          const PopupMenuItem<String>(
            value: 'signOut',
            child: Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
