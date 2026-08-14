import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Signs and verifies short-lived media capability URLs (sub-project 4a.D3).
///
/// Both the upload PUT and the read GET are bearer-less (the upload client
/// uses a fresh Dio; the read URL is handed to the CRM/`<img>` and must work
/// without a session), so the URL itself is the authorization: an
/// HMAC-SHA256 over "<op>.<id>.<exp>" keyed by a server-held secret, with a
/// short expiry. The `op` ('upload' or 'read') is bound into the signed
/// payload so the two capabilities are operation-scoped — a read URL minted
/// by [signReadUrl] (which may leak into logs, proxies, or browser history
/// via the `<img>` it's embedded in) is NOT a valid signature for the upload
/// route, and vice versa. Without that binding, a leaked read URL could be
/// replayed against `PUT /media/upload/<id>` to overwrite the evidence blob
/// under adjudication. This is minted only by the authenticated presign
/// endpoint and expires; an unauthenticated upload guarded only by an
/// unguessable id would be a storage-exhaustion / pollution vector (spec
/// §6a).
final _hmac = Hmac.sha256();

Future<String> _sign(String op, String id, int exp, String signingKey) async {
  final mac = await _hmac.calculateMac(
    utf8.encode('$op.$id.$exp'),
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
  final sig = await _sign('upload', id, exp, signingKey);
  return '$baseUrl/media/upload/$id?exp=$exp&sig=${Uri.encodeQueryComponent(sig)}';
}

/// Signs a short-lived READ URL for a media object: `<base>/media/<id>?exp&sig`.
/// Signed with the `'read'` operation scope (see [verifySignedUrl]), so this
/// capability cannot be replayed against the upload route even though only
/// the path differs.
Future<String> signReadUrl({
  required String baseUrl,
  required String id,
  required String signingKey,
  required DateTime now,
  Duration ttl = const Duration(minutes: 15),
}) async {
  final exp = now.add(ttl).millisecondsSinceEpoch ~/ 1000;
  final sig = await _sign('read', id, exp, signingKey);
  return '$baseUrl/media/$id?exp=$exp&sig=${Uri.encodeQueryComponent(sig)}';
}

/// Verifies a signed media URL's signature and expiry for a given
/// operation scope (`'upload'` or `'read'`). The caller must pass the `op`
/// matching its own route — a signature minted for one operation will not
/// verify for the other, so a read capability cannot be used to authorize a
/// write and vice versa.
Future<bool> verifySignedUrl({
  required String op,
  required String id,
  required int exp,
  required String sig,
  required String signingKey,
  required DateTime now,
}) async {
  if (now.millisecondsSinceEpoch ~/ 1000 > exp) return false;
  final expected = await _sign(op, id, exp, signingKey);
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
