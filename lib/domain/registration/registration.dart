import 'package:freezed_annotation/freezed_annotation.dart';

import '../common/status.dart';

part 'registration.freezed.dart';

/// A registered carpenter as shown in field search (M-02). Only non-sensitive
/// cues are exposed: photo, name, masked ID, phone suffix, territory/dealer
/// context — never full NID or full phone (§8.9).
@freezed
class RegisteredCarpenter with _$RegisteredCarpenter {
  const factory RegisteredCarpenter({
    required String id,
    required String name,
    required String displayId, // masked, e.g. "CARP-••4821"
    required String phoneSuffix, // last 3–4 digits only
    required String territory,
    required AttendanceStatus attendanceState,
    String? dealerContext,
    String? thumbnailUrl,
    @Default(true) bool eligible,
  }) = _RegisteredCarpenter;

  const RegisteredCarpenter._();

  bool get alreadyCaptured => attendanceState != AttendanceStatus.notCaptured;
}
