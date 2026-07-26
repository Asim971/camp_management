import 'evidence_store_io.dart'
    if (dart.library.js_interop) 'evidence_store_web.dart';

/// Platform seam for reading/deleting locally captured encrypted evidence.
///
/// Field capture is mobile-only, so the concrete file I/O lives in
/// [evidence_store_io.dart] (dart:io). The web build gets an unsupported stub
/// via conditional import, keeping `dart:io` out of the web compilation while
/// the sync stack stays in the shared codebase.
abstract interface class EvidenceStore {
  /// Persists [bytes] under [name] in the app's private evidence directory and
  /// returns the absolute path. Bytes are expected to already be encrypted.
  Future<String> write(String name, List<int> bytes);

  Future<List<int>> readBytes(String path);
  Future<void> deleteIfExists(String path);
}

/// Resolves to the native or web implementation at compile time.
EvidenceStore createEvidenceStore() => makeEvidenceStore();
