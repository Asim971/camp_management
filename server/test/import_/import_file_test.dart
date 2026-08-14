import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:campaign_service/src/import_/import_file.dart';
import 'package:campaign_service/src/infra/error_envelope.dart';
import 'package:test/test.dart';

void main() {
  List<int> utf8Bytes(String s) => utf8.encode(s);

  test('parses a well-formed CSV with the required + optional columns', () {
    final parsed = parseImportCsv(
      utf8Bytes(
        'name,phone,territory\n'
        'Md. Karim,+8801700004821,Dhaka North\n'
        'Karim Uddin,+8801700007734,Dhaka South\n',
      ),
    );
    expect(parsed.rows, hasLength(2));
    expect(parsed.rows[0].rowId, 'row-1');
    expect(parsed.rows[0].name, 'Md. Karim');
    expect(parsed.rows[0].phone, '+8801700004821');
    expect(parsed.rows[0].territory, 'Dhaka North');
    expect(parsed.rows[1].rowId, 'row-2');
  });

  test('header matching is case-insensitive and trims whitespace', () {
    final parsed = parseImportCsv(
      utf8Bytes(' Name , Phone \nA,+8801700000001\n'),
    );
    expect(parsed.rows.single.name, 'A');
    expect(parsed.rows.single.phone, '+8801700000001');
  });

  test('normalizes CRLF and a leading BOM before parsing', () {
    final withBom = <int>[
      0xEF,
      0xBB,
      0xBF,
      ...utf8Bytes('name,phone\r\nA,+8801700000001\r\n'),
    ];
    final parsed = parseImportCsv(withBom);
    expect(parsed.rows.single.name, 'A');
    expect(
      parsed.rows.single.rowId,
      'row-1',
      reason: 'a BOM or CRLF must not shift/blank the first row',
    );
  });

  test('a missing required column is IMPORT_FILE_INVALID', () {
    expect(
      () => parseImportCsv(utf8Bytes('name,territory\nA,North\n')),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.importFileInvalid,
        ),
      ),
    );
  });

  test('a header-only file (zero data rows) is IMPORT_FILE_INVALID', () {
    expect(
      () => parseImportCsv(utf8Bytes('name,phone\n')),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.importFileInvalid,
        ),
      ),
    );
  });

  test('non-UTF-8 bytes are IMPORT_FILE_INVALID, not an uncaught error', () {
    expect(
      () => parseImportCsv(<int>[0xFF, 0xFE, 0x00]),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.importFileInvalid,
        ),
      ),
    );
  });

  test('over the 2 MB cap is IMPORT_FILE_INVALID', () {
    final big = utf8Bytes(
      'name,phone\n${List.filled(200000, 'A,+8801700000001').join('\n')}',
    );
    expect(big.length, greaterThan(2 * 1024 * 1024));
    expect(
      () => parseImportCsv(big),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.importFileInvalid,
        ),
      ),
    );
  });

  test('a row missing name or phone still parses (classified ERROR later), '
      'never throws', () {
    final parsed = parseImportCsv(utf8Bytes('name,phone\n,\nB,\n'));
    expect(parsed.rows, hasLength(2));
    expect(parsed.rows[0].name, '');
    expect(parsed.rows[1].phone, '');
  });
}
