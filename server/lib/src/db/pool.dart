import 'package:postgres/postgres.dart';

/// Thin wrapper over a single Postgres connection. Deliberately not a pool:
/// one connection serves this slice and the e2e suite, and a pool would hide
/// the runTx constraint documented on [tx].
class Db {
  Db(this._connection);

  final Connection _connection;

  static Future<Db> open(String url) async {
    final uri = Uri.parse(url);
    final userInfo = uri.userInfo.split(':');
    final endpoint = Endpoint(
      host: uri.host,
      port: uri.port == 0 ? 5432 : uri.port,
      database: uri.pathSegments.isEmpty ? 'campaign' : uri.pathSegments.first,
      username: Uri.decodeComponent(userInfo.first),
      password: userInfo.length > 1 ? Uri.decodeComponent(userInfo[1]) : null,
    );
    final connection = await Connection.open(
      endpoint,
      // Local docker and the CI service container speak plaintext. A deploy
      // target requiring TLS must override this; it is not a default.
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    return Db(connection);
  }

  Future<Result> execute(String sql, {Map<String, Object?>? params}) =>
      params == null
      ? _connection.execute(sql)
      : _connection.execute(Sql.named(sql), parameters: params);

  /// Runs [fn] in a transaction.
  ///
  /// Use the [TxSession] passed to [fn] for every statement inside. Calling
  /// [execute] on this Db while a transaction is active throws
  /// PgException("Attempting to execute query on connection while inside a
  /// runTx call") — at protocol level the whole connection is in the
  /// transaction.
  Future<R> tx<R>(Future<R> Function(TxSession tx) fn) => _connection.runTx(fn);

  Future<void> close() => _connection.close();
}

/// ResultRow.toColumnMap() returns Map<String, dynamic>, which every read would
/// otherwise cast under strict-casts. Cast once, here.
Map<String, Object?> row(ResultRow r) =>
    r.toColumnMap().cast<String, Object?>();
