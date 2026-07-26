import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'evidence_store.dart';

/// Native (Android/iOS) evidence store backed by the app's private support
/// directory. Files here are OS-sandboxed to the app; contents are already
/// AES-encrypted before they reach [write] (§10.2 sensitive evidence controls).
class IoEvidenceStore implements EvidenceStore {
  const IoEvidenceStore();

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'evidence'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  @override
  Future<String> write(String name, List<int> bytes) async {
    final dir = await _dir();
    final path = p.join(dir.path, name);
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  @override
  Future<List<int>> readBytes(String path) => File(path).readAsBytes();

  @override
  Future<void> deleteIfExists(String path) async {
    final f = File(path);
    if (f.existsSync()) await f.delete();
  }
}

EvidenceStore makeEvidenceStore() => const IoEvidenceStore();
