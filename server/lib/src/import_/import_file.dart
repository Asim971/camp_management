import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:csv/csv.dart';

import '../infra/error_envelope.dart';

/// One parsed CSV data row. The row itself is not yet classified — that is
/// the DB-aware step in ImportRepo. Raw phone/nid are held here and never
/// serialized (2a.D2).
class ParsedRow {
  const ParsedRow({
    required this.rowId,
    required this.name,
    required this.phone,
    this.nid,
    this.territory,
    this.dealerContext,
  });

  final String rowId;
  final String name;
  final String phone;
  final String? nid;
  final String? territory;
  final String? dealerContext;
}

class ParsedImport {
  const ParsedImport(this.rows);
  final List<ParsedRow> rows;
}

const int _maxBytes = 2 * 1024 * 1024; // 2 MB (§6a)
const List<String> _required = ['name', 'phone'];

/// Parses and validates the uploaded CSV bytes. Pure: no IO, no DB. Throws
/// [ApiException] `IMPORT_FILE_INVALID` (422) for any content-level problem so
/// the route answers a specific, safe error and no job is created (2b.D5's
/// "unsafe file" acceptance criterion, pragmatic sense).
ParsedImport parseImportCsv(List<int> bytes) {
  if (bytes.length > _maxBytes) {
    _invalid('File exceeds the 2 MB limit.');
  }
  // Strip a leading UTF-8 BOM, then decode strictly — non-UTF-8 is a content
  // error, not a 500 (§6a).
  final withoutBom =
      (bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF)
      ? bytes.sublist(3)
      : bytes;
  String text;
  try {
    text = utf8.decode(withoutBom);
  } on FormatException {
    _invalid('File is not valid UTF-8 text.');
  }
  // csv 8.0.0's decoder handles \r\n/\n natively, but normalize anyway for
  // clarity and to keep behaviour independent of that internal detail.
  final normalized = text.replaceAll('\r\n', '\n');

  // Force the delimiter (autoDetect: false) so a small/short file can't be
  // misdetected, and disable skipEmptyLines so every physical line — even a
  // row with every field empty — becomes one ParsedRow, preserving the
  // row-N-is-the-Nth-data-line contract (rows are classified, not dropped,
  // by a later stage). dynamicTyping defaults to false already, so fields
  // decode as String, never as num/bool (§6a's "shouldParseNumbers: false").
  final table = Csv(
    fieldDelimiter: ',',
    autoDetect: false,
    skipEmptyLines: false,
  ).decode(normalized);

  if (table.isEmpty) _invalid('File is empty.');

  final header = table.first
      .map((c) => (c as String).trim().toLowerCase())
      .toList();
  final index = <String, int>{
    for (var i = 0; i < header.length; i++) header[i]: i,
  };
  for (final col in _required) {
    if (!index.containsKey(col)) {
      _invalid('Missing required column "$col".');
    }
  }
  if (table.length < 2) {
    _invalid('File has a header but no data rows.');
  }

  String cell(List<Object?> r, String col) {
    final i = index[col];
    if (i == null || i >= r.length) return '';
    return (r[i] as String).trim();
  }

  String? optional(List<Object?> r, String col) {
    if (!index.containsKey(col)) return null;
    final v = cell(r, col);
    return v.isEmpty ? null : v;
  }

  final rows = <ParsedRow>[];
  for (var i = 1; i < table.length; i++) {
    final r = table[i];
    rows.add(
      ParsedRow(
        rowId: 'row-$i', // 1-based data line (2b.D4)
        name: cell(r, 'name'),
        phone: cell(r, 'phone'),
        nid: optional(r, 'nid'),
        territory: optional(r, 'territory'),
        dealerContext: optional(r, 'dealer_context'),
      ),
    );
  }
  return ParsedImport(rows);
}

Never _invalid(String message) =>
    throw ApiException(ApiErrorCode.importFileInvalid, message: message);
