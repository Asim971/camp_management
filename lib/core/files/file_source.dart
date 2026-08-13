import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Where a CSV upload comes from. Abstracted (like CaptureSource) so E2E can
/// inject a bundled file without the native picker Maestro cannot drive.
abstract interface class FileSource {
  Future<({List<int> bytes, String name})?> pickCsv();
}

class RealFileSource implements FileSource {
  const RealFileSource();

  @override
  Future<({List<int> bytes, String name})?> pickCsv() async {
    const csvGroup = XTypeGroup(
      label: 'CSV',
      extensions: <String>['csv'],
      mimeTypes: <String>['text/csv'],
    );
    final file = await openFile(acceptedTypeGroups: <XTypeGroup>[csvGroup]);
    if (file == null) return null;
    return (bytes: await file.readAsBytes(), name: file.name);
  }
}

/// Returns a bundled sample CSV, no native picker. Selected under E2E.
class FakeFileSource implements FileSource {
  const FakeFileSource();

  @override
  Future<({List<int> bytes, String name})?> pickCsv() async {
    final data = await rootBundle.load('assets/e2e/bulk_import_sample.csv');
    return (bytes: data.buffer.asUint8List(), name: 'bulk_import_sample.csv');
  }
}
