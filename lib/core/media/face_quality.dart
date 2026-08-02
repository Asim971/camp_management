/// On-device capture-quality hints (§8.10). These guide recapture — they are
/// NOT identity matching and produce NO score shown to the field user. Identity
/// comparison happens server-side after upload.
class FaceQuality {
  const FaceQuality({
    required this.faceCount,
    required this.isSharp,
    required this.isWellLit,
    required this.isUpright,
  });

  final int faceCount;
  final bool isSharp;
  final bool isWellLit;
  final bool isUpright;

  bool get passes => faceCount == 1 && isSharp && isWellLit && isUpright;

  /// Ordered problems to surface, most blocking first (empty == good capture).
  List<QualityIssue> get issues => [
    if (faceCount == 0) QualityIssue.noFace,
    if (faceCount > 1) QualityIssue.multipleFaces,
    if (!isSharp) QualityIssue.blur,
    if (!isWellLit) QualityIssue.poorLight,
    if (!isUpright) QualityIssue.orientation,
  ];
}

enum QualityIssue { noFace, multipleFaces, blur, poorLight, orientation }

/// Runs quality hints over captured image bytes. The concrete implementation
/// uses on-device ML Kit face detection (Task T-2.2.2).
abstract interface class FaceQualityChecker {
  Future<FaceQuality> check(List<int> imageBytes);
}

/// Placeholder used until ML Kit is wired. Returns a passing result so the flow
/// is exercisable end-to-end in P0; replace before field testing.
class PassthroughQualityChecker implements FaceQualityChecker {
  const PassthroughQualityChecker();

  @override
  Future<FaceQuality> check(List<int> imageBytes) async => const FaceQuality(
    faceCount: 1,
    isSharp: true,
    isWellLit: true,
    isUpright: true,
  );
}

/// E2E-only checker. When [failFirst] is set (QUALITY=fail), the first capture
/// fails quality so the recapture path is exercised, and every subsequent
/// capture passes. Test-only.
class E2EQualityChecker implements FaceQualityChecker {
  E2EQualityChecker({this.failFirst = false});

  final bool failFirst;
  int _calls = 0;

  @override
  Future<FaceQuality> check(List<int> imageBytes) async {
    _calls++;
    if (failFirst && _calls == 1) {
      return const FaceQuality(
        faceCount: 0,
        isSharp: false,
        isWellLit: false,
        isUpright: true,
      );
    }
    return const FaceQuality(
      faceCount: 1,
      isSharp: true,
      isWellLit: true,
      isUpright: true,
    );
  }
}
