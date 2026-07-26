import 'evidence_store.dart';

/// Web stub. Field attendance capture does not run on web, so evidence file
/// operations are unsupported here; the sync engine is never instantiated on
/// the web admin/CRM surfaces.
class WebEvidenceStore implements EvidenceStore {
  const WebEvidenceStore();

  @override
  Future<String> write(String name, List<int> bytes) async =>
      throw UnsupportedError('Attendance capture is mobile-only');

  @override
  Future<List<int>> readBytes(String path) async =>
      throw UnsupportedError('Attendance capture is mobile-only');

  @override
  Future<void> deleteIfExists(String path) async {/* no-op on web */}
}

EvidenceStore makeEvidenceStore() => const WebEvidenceStore();
