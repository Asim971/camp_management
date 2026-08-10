import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';

/// Single entry point. Flavor + environment are selected via `--dart-define`
/// (see lib/app/flavors.dart), so there is no per-flavor `main_*.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inter and Noto Sans Bengali are SIL OFL 1.1, which requires the license
  // text to accompany the fonts in distribution. Registering it here (rather
  // than reading assets/fonts/OFL.txt eagerly) keeps this off the startup hot
  // path: LicenseRegistry only invokes the callback — and only then does the
  // asset read happen — when something actually asks for the license list,
  // i.e. when the user opens the app's license page.
  LicenseRegistry.addLicense(() {
    return Stream<LicenseEntry>.fromFuture(
      rootBundle
          .loadString('assets/fonts/OFL.txt')
          .then(
            (license) => LicenseEntryWithLineBreaks(const [
              'Inter',
              'NotoSansBengali',
            ], license),
          ),
    );
  });

  // Every pre-frame step lives in bootstrap(), which never throws: what used
  // to abort startup (and leave a blank screen) is now recorded on
  // BootDiagnostics instead. See lib/app/bootstrap.dart.
  final container = await bootstrap();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AcslCampaignApp(),
    ),
  );
}
