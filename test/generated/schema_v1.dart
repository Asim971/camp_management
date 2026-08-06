// dart format width=80
// GENERATED CODE, DO NOT EDIT BY HAND.
// ignore_for_file: type=lint
import 'package:drift/drift.dart';

class SyncTasks extends Table with TableInfo<SyncTasks, SyncTasksData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  SyncTasks(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('\'pendingSync\''),
  );
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('0'),
  );
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> lastAttemptAt =
      GeneratedColumn<DateTime>(
        'last_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    payloadJson,
    status,
    retryCount,
    createdAt,
    lastAttemptAt,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_tasks';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncTasksData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncTasksData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  SyncTasks createAlias(String alias) {
    return SyncTasks(attachedDatabase, alias);
  }
}

class SyncTasksData extends DataClass implements Insertable<SyncTasksData> {
  final String id;
  final String type;
  final String payloadJson;
  final String status;
  final int retryCount;
  final DateTime createdAt;
  final DateTime? lastAttemptAt;
  final String? lastError;
  const SyncTasksData({
    required this.id,
    required this.type,
    required this.payloadJson,
    required this.status,
    required this.retryCount,
    required this.createdAt,
    this.lastAttemptAt,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    map['payload_json'] = Variable<String>(payloadJson);
    map['status'] = Variable<String>(status);
    map['retry_count'] = Variable<int>(retryCount);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  SyncTasksCompanion toCompanion(bool nullToAbsent) {
    return SyncTasksCompanion(
      id: Value(id),
      type: Value(type),
      payloadJson: Value(payloadJson),
      status: Value(status),
      retryCount: Value(retryCount),
      createdAt: Value(createdAt),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory SyncTasksData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncTasksData(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      status: serializer.fromJson<String>(json['status']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'status': serializer.toJson<String>(status),
      'retryCount': serializer.toJson<int>(retryCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  SyncTasksData copyWith({
    String? id,
    String? type,
    String? payloadJson,
    String? status,
    int? retryCount,
    DateTime? createdAt,
    Value<DateTime?> lastAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
  }) => SyncTasksData(
    id: id ?? this.id,
    type: type ?? this.type,
    payloadJson: payloadJson ?? this.payloadJson,
    status: status ?? this.status,
    retryCount: retryCount ?? this.retryCount,
    createdAt: createdAt ?? this.createdAt,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  SyncTasksData copyWithCompanion(SyncTasksCompanion data) {
    return SyncTasksData(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      status: data.status.present ? data.status.value : this.status,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncTasksData(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    payloadJson,
    status,
    retryCount,
    createdAt,
    lastAttemptAt,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncTasksData &&
          other.id == this.id &&
          other.type == this.type &&
          other.payloadJson == this.payloadJson &&
          other.status == this.status &&
          other.retryCount == this.retryCount &&
          other.createdAt == this.createdAt &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.lastError == this.lastError);
}

class SyncTasksCompanion extends UpdateCompanion<SyncTasksData> {
  final Value<String> id;
  final Value<String> type;
  final Value<String> payloadJson;
  final Value<String> status;
  final Value<int> retryCount;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastAttemptAt;
  final Value<String?> lastError;
  final Value<int> rowid;
  const SyncTasksCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncTasksCompanion.insert({
    required String id,
    required String type,
    required String payloadJson,
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    required DateTime createdAt,
    this.lastAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       type = Value(type),
       payloadJson = Value(payloadJson),
       createdAt = Value(createdAt);
  static Insertable<SyncTasksData> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? payloadJson,
    Expression<String>? status,
    Expression<int>? retryCount,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastAttemptAt,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (status != null) 'status': status,
      if (retryCount != null) 'retry_count': retryCount,
      if (createdAt != null) 'created_at': createdAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncTasksCompanion copyWith({
    Value<String>? id,
    Value<String>? type,
    Value<String>? payloadJson,
    Value<String>? status,
    Value<int>? retryCount,
    Value<DateTime>? createdAt,
    Value<DateTime?>? lastAttemptAt,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return SyncTasksCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      payloadJson: payloadJson ?? this.payloadJson,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncTasksCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class AttendanceDrafts extends Table
    with TableInfo<AttendanceDrafts, AttendanceDraftsData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  AttendanceDrafts(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> carpenterId = GeneratedColumn<String>(
    'carpenter_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> encryptedMediaPath =
      GeneratedColumn<String>(
        'encrypted_media_path',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  late final GeneratedColumn<String> qualityJson = GeneratedColumn<String>(
    'quality_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> capturedAt = GeneratedColumn<DateTime>(
    'captured_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> capturedBy = GeneratedColumn<String>(
    'captured_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    carpenterId,
    encryptedMediaPath,
    qualityJson,
    capturedAt,
    capturedBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attendance_drafts';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AttendanceDraftsData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AttendanceDraftsData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      carpenterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}carpenter_id'],
      )!,
      encryptedMediaPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_media_path'],
      )!,
      qualityJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quality_json'],
      ),
      capturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}captured_at'],
      )!,
      capturedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}captured_by'],
      )!,
    );
  }

  @override
  AttendanceDrafts createAlias(String alias) {
    return AttendanceDrafts(attachedDatabase, alias);
  }
}

class AttendanceDraftsData extends DataClass
    implements Insertable<AttendanceDraftsData> {
  final String id;
  final String sessionId;
  final String carpenterId;
  final String encryptedMediaPath;
  final String? qualityJson;
  final DateTime capturedAt;
  final String capturedBy;
  const AttendanceDraftsData({
    required this.id,
    required this.sessionId,
    required this.carpenterId,
    required this.encryptedMediaPath,
    this.qualityJson,
    required this.capturedAt,
    required this.capturedBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['carpenter_id'] = Variable<String>(carpenterId);
    map['encrypted_media_path'] = Variable<String>(encryptedMediaPath);
    if (!nullToAbsent || qualityJson != null) {
      map['quality_json'] = Variable<String>(qualityJson);
    }
    map['captured_at'] = Variable<DateTime>(capturedAt);
    map['captured_by'] = Variable<String>(capturedBy);
    return map;
  }

  AttendanceDraftsCompanion toCompanion(bool nullToAbsent) {
    return AttendanceDraftsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      carpenterId: Value(carpenterId),
      encryptedMediaPath: Value(encryptedMediaPath),
      qualityJson: qualityJson == null && nullToAbsent
          ? const Value.absent()
          : Value(qualityJson),
      capturedAt: Value(capturedAt),
      capturedBy: Value(capturedBy),
    );
  }

  factory AttendanceDraftsData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AttendanceDraftsData(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      carpenterId: serializer.fromJson<String>(json['carpenterId']),
      encryptedMediaPath: serializer.fromJson<String>(
        json['encryptedMediaPath'],
      ),
      qualityJson: serializer.fromJson<String?>(json['qualityJson']),
      capturedAt: serializer.fromJson<DateTime>(json['capturedAt']),
      capturedBy: serializer.fromJson<String>(json['capturedBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'carpenterId': serializer.toJson<String>(carpenterId),
      'encryptedMediaPath': serializer.toJson<String>(encryptedMediaPath),
      'qualityJson': serializer.toJson<String?>(qualityJson),
      'capturedAt': serializer.toJson<DateTime>(capturedAt),
      'capturedBy': serializer.toJson<String>(capturedBy),
    };
  }

  AttendanceDraftsData copyWith({
    String? id,
    String? sessionId,
    String? carpenterId,
    String? encryptedMediaPath,
    Value<String?> qualityJson = const Value.absent(),
    DateTime? capturedAt,
    String? capturedBy,
  }) => AttendanceDraftsData(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    carpenterId: carpenterId ?? this.carpenterId,
    encryptedMediaPath: encryptedMediaPath ?? this.encryptedMediaPath,
    qualityJson: qualityJson.present ? qualityJson.value : this.qualityJson,
    capturedAt: capturedAt ?? this.capturedAt,
    capturedBy: capturedBy ?? this.capturedBy,
  );
  AttendanceDraftsData copyWithCompanion(AttendanceDraftsCompanion data) {
    return AttendanceDraftsData(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      carpenterId: data.carpenterId.present
          ? data.carpenterId.value
          : this.carpenterId,
      encryptedMediaPath: data.encryptedMediaPath.present
          ? data.encryptedMediaPath.value
          : this.encryptedMediaPath,
      qualityJson: data.qualityJson.present
          ? data.qualityJson.value
          : this.qualityJson,
      capturedAt: data.capturedAt.present
          ? data.capturedAt.value
          : this.capturedAt,
      capturedBy: data.capturedBy.present
          ? data.capturedBy.value
          : this.capturedBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AttendanceDraftsData(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('carpenterId: $carpenterId, ')
          ..write('encryptedMediaPath: $encryptedMediaPath, ')
          ..write('qualityJson: $qualityJson, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('capturedBy: $capturedBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    carpenterId,
    encryptedMediaPath,
    qualityJson,
    capturedAt,
    capturedBy,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AttendanceDraftsData &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.carpenterId == this.carpenterId &&
          other.encryptedMediaPath == this.encryptedMediaPath &&
          other.qualityJson == this.qualityJson &&
          other.capturedAt == this.capturedAt &&
          other.capturedBy == this.capturedBy);
}

class AttendanceDraftsCompanion extends UpdateCompanion<AttendanceDraftsData> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> carpenterId;
  final Value<String> encryptedMediaPath;
  final Value<String?> qualityJson;
  final Value<DateTime> capturedAt;
  final Value<String> capturedBy;
  final Value<int> rowid;
  const AttendanceDraftsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.carpenterId = const Value.absent(),
    this.encryptedMediaPath = const Value.absent(),
    this.qualityJson = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.capturedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AttendanceDraftsCompanion.insert({
    required String id,
    required String sessionId,
    required String carpenterId,
    required String encryptedMediaPath,
    this.qualityJson = const Value.absent(),
    required DateTime capturedAt,
    required String capturedBy,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       carpenterId = Value(carpenterId),
       encryptedMediaPath = Value(encryptedMediaPath),
       capturedAt = Value(capturedAt),
       capturedBy = Value(capturedBy);
  static Insertable<AttendanceDraftsData> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? carpenterId,
    Expression<String>? encryptedMediaPath,
    Expression<String>? qualityJson,
    Expression<DateTime>? capturedAt,
    Expression<String>? capturedBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (carpenterId != null) 'carpenter_id': carpenterId,
      if (encryptedMediaPath != null)
        'encrypted_media_path': encryptedMediaPath,
      if (qualityJson != null) 'quality_json': qualityJson,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (capturedBy != null) 'captured_by': capturedBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AttendanceDraftsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? carpenterId,
    Value<String>? encryptedMediaPath,
    Value<String?>? qualityJson,
    Value<DateTime>? capturedAt,
    Value<String>? capturedBy,
    Value<int>? rowid,
  }) {
    return AttendanceDraftsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      carpenterId: carpenterId ?? this.carpenterId,
      encryptedMediaPath: encryptedMediaPath ?? this.encryptedMediaPath,
      qualityJson: qualityJson ?? this.qualityJson,
      capturedAt: capturedAt ?? this.capturedAt,
      capturedBy: capturedBy ?? this.capturedBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (carpenterId.present) {
      map['carpenter_id'] = Variable<String>(carpenterId.value);
    }
    if (encryptedMediaPath.present) {
      map['encrypted_media_path'] = Variable<String>(encryptedMediaPath.value);
    }
    if (qualityJson.present) {
      map['quality_json'] = Variable<String>(qualityJson.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<DateTime>(capturedAt.value);
    }
    if (capturedBy.present) {
      map['captured_by'] = Variable<String>(capturedBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AttendanceDraftsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('carpenterId: $carpenterId, ')
          ..write('encryptedMediaPath: $encryptedMediaPath, ')
          ..write('qualityJson: $qualityJson, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('capturedBy: $capturedBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class CachedReferences extends Table
    with TableInfo<CachedReferences, CachedReferencesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  CachedReferences(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, valueJson, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_references';
  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CachedReferencesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedReferencesData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  CachedReferences createAlias(String alias) {
    return CachedReferences(attachedDatabase, alias);
  }
}

class CachedReferencesData extends DataClass
    implements Insertable<CachedReferencesData> {
  final String key;
  final String valueJson;
  final DateTime fetchedAt;
  const CachedReferencesData({
    required this.key,
    required this.valueJson,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value_json'] = Variable<String>(valueJson);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  CachedReferencesCompanion toCompanion(bool nullToAbsent) {
    return CachedReferencesCompanion(
      key: Value(key),
      valueJson: Value(valueJson),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory CachedReferencesData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedReferencesData(
      key: serializer.fromJson<String>(json['key']),
      valueJson: serializer.fromJson<String>(json['valueJson']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'valueJson': serializer.toJson<String>(valueJson),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  CachedReferencesData copyWith({
    String? key,
    String? valueJson,
    DateTime? fetchedAt,
  }) => CachedReferencesData(
    key: key ?? this.key,
    valueJson: valueJson ?? this.valueJson,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  CachedReferencesData copyWithCompanion(CachedReferencesCompanion data) {
    return CachedReferencesData(
      key: data.key.present ? data.key.value : this.key,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedReferencesData(')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, valueJson, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedReferencesData &&
          other.key == this.key &&
          other.valueJson == this.valueJson &&
          other.fetchedAt == this.fetchedAt);
}

class CachedReferencesCompanion extends UpdateCompanion<CachedReferencesData> {
  final Value<String> key;
  final Value<String> valueJson;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const CachedReferencesCompanion({
    this.key = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedReferencesCompanion.insert({
    required String key,
    required String valueJson,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       valueJson = Value(valueJson),
       fetchedAt = Value(fetchedAt);
  static Insertable<CachedReferencesData> custom({
    Expression<String>? key,
    Expression<String>? valueJson,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (valueJson != null) 'value_json': valueJson,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedReferencesCompanion copyWith({
    Value<String>? key,
    Value<String>? valueJson,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return CachedReferencesCompanion(
      key: key ?? this.key,
      valueJson: valueJson ?? this.valueJson,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedReferencesCompanion(')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class DatabaseAtV1 extends GeneratedDatabase {
  DatabaseAtV1(QueryExecutor e) : super(e);
  late final SyncTasks syncTasks = SyncTasks(this);
  late final AttendanceDrafts attendanceDrafts = AttendanceDrafts(this);
  late final CachedReferences cachedReferences = CachedReferences(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    syncTasks,
    attendanceDrafts,
    cachedReferences,
  ];
  @override
  int get schemaVersion => 1;
}
