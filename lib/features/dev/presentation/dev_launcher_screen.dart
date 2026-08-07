import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Test-only deep-link launcher (reachable at `/dev` when `AppConfig.e2e`).
/// Production navigation does not yet route to the field/CRM screens, so Maestro
/// uses these entries to jump directly. See TESTING_MAESTRO.md §3.2.
///
/// The fixed IDs (SESSION_E2E, CARP_E2E, CASE_E2E, CASE_CONFLICT) are the ones
/// the E2E seeder and mock server provision.
class DevLauncherScreen extends StatelessWidget {
  const DevLauncherScreen({super.key});

  static const _entries = <({String id, String label, String route})>[
    (id: 'dev_open_campaigns', label: 'Campaign list', route: '/campaigns'),
    (
      id: 'dev_open_search',
      label: 'Carpenter search',
      route: '/search/SESSION_E2E',
    ),
    (
      id: 'dev_open_capture',
      label: 'Capture',
      route: '/capture/SESSION_E2E/CARP_E2E',
    ),
    (id: 'dev_open_queue', label: 'Sync queue', route: '/queue'),
    (
      id: 'dev_open_crm_case',
      label: 'CRM case',
      route: '/verification/cases/CASE_E2E',
    ),
    (
      id: 'dev_open_crm_case_conflict',
      label: 'CRM case (conflict)',
      route: '/verification/cases/CASE_CONFLICT',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('E2E launcher')),
      body: Semantics(
        identifier: 'dev_launcher',
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final e in _entries)
              Semantics(
                identifier: e.id,
                child: Card(
                  child: ListTile(
                    title: Text(e.label),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(e.route),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
