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

  /// [queryMode] defaults to the driver's normal choice (extended/prepared).
  /// Pass [QueryMode.simple] to run a multi-statement script as one Query
  /// message — the extended protocol rejects a `Parse` containing more than
  /// one command, so a script like a migration (many `CREATE TABLE`/`CREATE
  /// INDEX` statements) must use simple mode to run at all.
  ///
  /// The trap: Postgres's simple protocol already treats that one Query
  /// message as implicitly atomic, all on its own. So a failure *inside* the
  /// script (e.g. a bad statement partway through the migration text) proves
  /// nothing about whether the script and a *separate* statement issued after
  /// it — such as the `schema_migrations` version-row insert — share a
  /// transaction. Postgres would roll the script back regardless. The actual
  /// P0.R5 gap this codebase cares about sits in the window *between* the two
  /// statements: whether the version insert is wrapped in the same
  /// application-level transaction as the script, not whether the script is
  /// internally atomic.
  Future<Result> execute(
    String sql, {
    Map<String, Object?>? params,
    QueryMode? queryMode,
  }) => params == null
      ? _connection.execute(sql, queryMode: queryMode)
      : _connection.execute(
          Sql.named(sql),
          parameters: params,
          queryMode: queryMode,
        );

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
