import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Signs and verifies short-lived upload capability URLs (sub-project 4a.D3).
///
/// The upload PUT is bearer-less (the client uses a fresh Dio), so the URL
/// itself is the authorization: an HMAC-SHA256 over "<id>.<exp>" keyed by a
/// server-held secret, with a short expiry. This is minted only by the
/// authenticated presign endpoint and expires; an unauthenticated upload
/// guarded only by an unguessable id would be a storage-exhaustion / pollution
/// vector (spec §6a).
final _hmac = Hmac.sha256();

Future<String> _sign(String id, int exp, String signingKey) async {
  final mac = await _hmac.calculateMac(
    utf8.encode('$id.$exp'),
    secretKey: SecretKey(utf8.encode(signingKey)),
  );
  return base64Url.encode(mac.bytes);
}

Future<String> signUploadUrl({
  required String baseUrl,
  required String id,
  required String signingKey,
  required DateTime now,
  Duration ttl = const Duration(minutes: 15),
}) async {
  final exp = now.add(ttl).millisecondsSinceEpoch ~/ 1000;
  final sig = await _sign(id, exp, signingKey);
  return '$baseUrl/media/upload/$id?exp=$exp&sig=${Uri.encodeQueryComponent(sig)}';
}

/// Signs a short-lived READ URL for a media object: `<base>/media/<id>?exp&sig`.
/// The signature is the same `id.exp` HMAC as the upload URL (verified by
/// [verifyUploadSignature]); only the path differs.
Future<String> signReadUrl({
  required String baseUrl,
  required String id,
  required String signingKey,
  required DateTime now,
  Duration ttl = const Duration(minutes: 15),
}) async {
  final exp = now.add(ttl).millisecondsSinceEpoch ~/ 1000;
  final sig = await _sign(id, exp, signingKey);
  return '$baseUrl/media/$id?exp=$exp&sig=${Uri.encodeQueryComponent(sig)}';
}

Future<bool> verifyUploadSignature({
  required String id,
  required int exp,
  required String sig,
  required String signingKey,
  required DateTime now,
}) async {
  if (now.millisecondsSinceEpoch ~/ 1000 > exp) return false;
  final expected = await _sign(id, exp, signingKey);
  return _constantTimeEquals(expected, sig);
}

/// Length-independent-leaking but value-constant-time comparison — never a
/// plain `==`, which short-circuits on the first differing byte.
bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
