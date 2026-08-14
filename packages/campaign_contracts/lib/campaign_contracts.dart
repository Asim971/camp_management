/// Wire vocabulary shared by the app and the campaign service.
///
/// Holds the WIRE only — no domain entities, no validation, no status machine
/// (spec D5). The server's campaign carries org scope, audit columns and a
/// version; the app's carries presentation concerns. Sharing entities would
/// drag each side's incidental needs into the other.
library;

export 'src/campaign_decision.dart';
export 'src/campaign_status.dart';
export 'src/error_codes.dart';
export 'src/import_row_outcome.dart';
export 'src/import_status.dart';
export 'src/match_band.dart';
export 'src/reference_source.dart';
export 'src/registration_status.dart';
export 'src/session_status.dart';
export 'src/verification_outcome.dart';
