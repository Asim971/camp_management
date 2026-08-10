import '../db/pool.dart';

/// Whether Segregation of Duties is enforced for campaign decisions, read
/// from `app_config` key `sod.enforced`.
///
/// Defaults to **enforced** whenever the row is missing (deleted, or the
/// table was never seeded) or the lookup itself fails for any reason — a
/// missing or unreadable config row must not silently disable a governance
/// control (spec section 6). Only the literal stored value `'false'`
/// disables SoD; anything else, including a garbled value, is treated as
/// "still enforced" rather than "we can't tell, so let's not enforce it".
Future<bool> sodEnforced(Db db) async {
  try {
    final res = await db.execute(
      "SELECT value FROM app_config WHERE key = 'sod.enforced'",
    );
    if (res.isEmpty) return true;
    final value = row(res.single)['value'] as String?;
    return value != 'false';
  } on Object {
    return true;
  }
}
