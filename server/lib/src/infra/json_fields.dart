import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:shelf/shelf.dart';

import 'error_envelope.dart';

/// Decodes [request]'s body as a JSON object. A missing/empty body decodes
/// to `{}` (every field below is then "missing", which the field-level
/// parsing turns into its own specific error) rather than failing outright —
/// only a body that IS present but isn't a JSON object is a [badField].
Future<Map<String, Object?>> readJsonBody(Request request) async {
  final text = await request.readAsString();
  if (text.isEmpty) return const {};
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw ApiException(ApiErrorCode.badRequest, message: 'Invalid JSON body.');
  }
  if (decoded is! Map<String, Object?>) {
    throw ApiException(
      ApiErrorCode.badRequest,
      message: 'Expected a JSON object body.',
    );
  }
  return decoded;
}

/// Every `*Field` helper below shares the same contract: `null`/absent is
/// a valid "not provided" (the caller decides the fallback), but a value
/// that IS present and the wrong JSON type is a [badField] naming [field]
/// (or [reportAs], for a nested field whose own JSON key isn't the name a
/// caller wants surfaced) — never a silent coercion and never an uncaught
/// cast exception.
Never badField(String field, String problem) => throw ApiException(
  ApiErrorCode.badRequest,
  message: '"$field" $problem.',
  details: {'field': field},
);

String? stringField(
  Map<String, Object?> body,
  String field, {
  String? reportAs,
}) {
  final value = body[field];
  if (value == null) return null;
  if (value is! String) badField(reportAs ?? field, 'must be a string');
  return value;
}

int? intField(Map<String, Object?> body, String field, {String? reportAs}) {
  final value = body[field];
  if (value == null) return null;
  if (value is! int) badField(reportAs ?? field, 'must be an integer');
  return value;
}

bool? boolField(Map<String, Object?> body, String field) {
  final value = body[field];
  if (value == null) return null;
  if (value is! bool) badField(field, 'must be a boolean');
  return value;
}

/// `[]` when [field] is absent — every caller here treats "not provided"
/// the same as "provided empty" — but a [field] that IS present and not a
/// JSON array (e.g. `{}`) is a [badField], not a value silently coerced
/// into an empty list.
List<Object?> listField(Map<String, Object?> body, String field) {
  final value = body[field];
  if (value == null) return const [];
  if (value is! List) badField(field, 'must be an array');
  return value;
}

/// [listField] plus an element-type check — `{"territoryIds": [1]}` names
/// the specific offending index (`territoryIds[0]`) rather than failing
/// lazily, mid-iteration, wherever the list is later consumed (`cast`'s
/// laziness is exactly how this one reached the envelope as a 500 before
/// this check existed).
List<String> stringListField(Map<String, Object?> body, String field) {
  final list = listField(body, field);
  for (var i = 0; i < list.length; i++) {
    if (list[i] is! String) badField('$field[$i]', 'must be a string');
  }
  return list.cast<String>();
}

DateTime? dateTimeField(
  Map<String, Object?> body,
  String field, {
  String? reportAs,
}) {
  final value = body[field];
  if (value == null) return null;
  if (value is! String) {
    badField(reportAs ?? field, 'must be an ISO-8601 string');
  }
  try {
    return DateTime.parse(value);
  } on FormatException {
    badField(reportAs ?? field, 'must be a valid ISO-8601 date/time');
  }
}
