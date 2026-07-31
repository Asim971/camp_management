import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/di/providers.dart';
import 'core/dev/e2e_seeder.dart';

/// Single entry point. Flavor + environment are selected via `--dart-define`
/// (see lib/app/flavors.dart), so there is no per-flavor `main_*.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();
  final config = container.read(appConfigProvider);

  // E2E-only: seed deterministic local data before the app renders. Best-effort
  // — a local-DB failure (e.g. Drift web wasm assets absent) must not block the
  // UI, so DB-independent screens still boot.
  if (config.e2e) {
    try {
      await seedE2EData(
        container.read(appDatabaseProvider),
        seed: config.e2eSeed,
      );
    } catch (_) {/* seeding is non-critical for the demo */}
  }

  runApp(
    UncontrolledProviderScope(
        container: container, child: const AcslCampaignApp(),),
  );
}
