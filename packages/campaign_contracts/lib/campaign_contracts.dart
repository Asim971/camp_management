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
export 'src/registration_status.dart';
