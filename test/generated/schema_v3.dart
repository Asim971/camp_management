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
  late final GeneratedColumn<int> consentVersion = GeneratedColumn<int>(
    'consent_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<String> consentLanguage = GeneratedColumn<String>(
    'consent_language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> consentShownAt =
      GeneratedColumn<DateTime>(
        'consent_shown_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  late final GeneratedColumn<String> consentContentHash =
      GeneratedColumn<String>(
        'consent_content_hash',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
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
    consentVersion,
    consentLanguage,
    consentShownAt,
    consentContentHash,
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
      consentVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}consent_version'],
      ),
      consentLanguage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}consent_language'],
      ),
      consentShownAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}consent_shown_at'],
      ),
      consentContentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}consent_content_hash'],
      ),
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
  final int? consentVersion;
  final String? consentLanguage;
  final DateTime? consentShownAt;
  final String? consentContentHash;
  const AttendanceDraftsData({
    required this.id,
    required this.sessionId,
    required this.carpenterId,
    required this.encryptedMediaPath,
    this.qualityJson,
    required this.capturedAt,
    required this.capturedBy,
    this.consentVersion,
    this.consentLanguage,
    this.consentShownAt,
    this.consentContentHash,
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
    if (!nullToAbsent || consentVersion != null) {
      map['consent_version'] = Variable<int>(consentVersion);
    }
    if (!nullToAbsent || consentLanguage != null) {
      map['consent_language'] = Variable<String>(consentLanguage);
    }
    if (!nullToAbsent || consentShownAt != null) {
      map['consent_shown_at'] = Variable<DateTime>(consentShownAt);
    }
    if (!nullToAbsent || consentContentHash != null) {
      map['consent_content_hash'] = Variable<String>(consentContentHash);
    }
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
      consentVersion: consentVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(consentVersion),
      consentLanguage: consentLanguage == null && nullToAbsent
          ? const Value.absent()
          : Value(consentLanguage),
      consentShownAt: consentShownAt == null && nullToAbsent
          ? const Value.absent()
          : Value(consentShownAt),
      consentContentHash: consentContentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(consentContentHash),
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
      consentVersion: serializer.fromJson<int?>(json['consentVersion']),
      consentLanguage: serializer.fromJson<String?>(json['consentLanguage']),
      consentShownAt: serializer.fromJson<DateTime?>(json['consentShownAt']),
      consentContentHash: serializer.fromJson<String?>(
        json['consentContentHash'],
      ),
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
      'consentVersion': serializer.toJson<int?>(consentVersion),
      'consentLanguage': serializer.toJson<String?>(consentLanguage),
      'consentShownAt': serializer.toJson<DateTime?>(consentShownAt),
      'consentContentHash': serializer.toJson<String?>(consentContentHash),
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
    Value<int?> consentVersion = const Value.absent(),
    Value<String?> consentLanguage = const Value.absent(),
    Value<DateTime?> consentShownAt = const Value.absent(),
    Value<String?> consentContentHash = const Value.absent(),
  }) => AttendanceDraftsData(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    carpenterId: carpenterId ?? this.carpenterId,
    encryptedMediaPath: encryptedMediaPath ?? this.encryptedMediaPath,
    qualityJson: qualityJson.present ? qualityJson.value : this.qualityJson,
    capturedAt: capturedAt ?? this.capturedAt,
    capturedBy: capturedBy ?? this.capturedBy,
    consentVersion: consentVersion.present
        ? consentVersion.value
        : this.consentVersion,
    consentLanguage: consentLanguage.present
        ? consentLanguage.value
        : this.consentLanguage,
    consentShownAt: consentShownAt.present
        ? consentShownAt.value
        : this.consentShownAt,
    consentContentHash: consentContentHash.present
        ? consentContentHash.value
        : this.consentContentHash,
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
      consentVersion: data.consentVersion.present
          ? data.consentVersion.value
          : this.consentVersion,
      consentLanguage: data.consentLanguage.present
          ? data.consentLanguage.value
          : this.consentLanguage,
      consentShownAt: data.consentShownAt.present
          ? data.consentShownAt.value
          : this.consentShownAt,
      consentContentHash: data.consentContentHash.present
          ? data.consentContentHash.value
          : this.consentContentHash,
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
          ..write('capturedBy: $capturedBy, ')
          ..write('consentVersion: $consentVersion, ')
          ..write('consentLanguage: $consentLanguage, ')
          ..write('consentShownAt: $consentShownAt, ')
          ..write('consentContentHash: $consentContentHash')
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
    consentVersion,
    consentLanguage,
    consentShownAt,
    consentContentHash,
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
          other.capturedBy == this.capturedBy &&
          other.consentVersion == this.consentVersion &&
          other.consentLanguage == this.consentLanguage &&
          other.consentShownAt == this.consentShownAt &&
          other.consentContentHash == this.consentContentHash);
}

class AttendanceDraftsCompanion extends UpdateCompanion<AttendanceDraftsData> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> carpenterId;
  final Value<String> encryptedMediaPath;
  final Value<String?> qualityJson;
  final Value<DateTime> capturedAt;
  final Value<String> capturedBy;
  final Value<int?> consentVersion;
  final Value<String?> consentLanguage;
  final Value<DateTime?> consentShownAt;
  final Value<String?> consentContentHash;
  final Value<int> rowid;
  const AttendanceDraftsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.carpenterId = const Value.absent(),
    this.encryptedMediaPath = const Value.absent(),
    this.qualityJson = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.capturedBy = const Value.absent(),
    this.consentVersion = const Value.absent(),
    this.consentLanguage = const Value.absent(),
    this.consentShownAt = const Value.absent(),
    this.consentContentHash = const Value.absent(),
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
    this.consentVersion = const Value.absent(),
    this.consentLanguage = const Value.absent(),
    this.consentShownAt = const Value.absent(),
    this.consentContentHash = const Value.absent(),
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
    Expression<int>? consentVersion,
    Expression<String>? consentLanguage,
    Expression<DateTime>? consentShownAt,
    Expression<String>? consentContentHash,
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
      if (consentVersion != null) 'consent_version': consentVersion,
      if (consentLanguage != null) 'consent_language': consentLanguage,
      if (consentShownAt != null) 'consent_shown_at': consentShownAt,
      if (consentContentHash != null)
        'consent_content_hash': consentContentHash,
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
    Value<int?>? consentVersion,
    Value<String?>? consentLanguage,
    Value<DateTime?>? consentShownAt,
    Value<String?>? consentContentHash,
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
      consentVersion: consentVersion ?? this.consentVersion,
      consentLanguage: consentLanguage ?? this.consentLanguage,
      consentShownAt: consentShownAt ?? this.consentShownAt,
      consentContentHash: consentContentHash ?? this.consentContentHash,
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
    if (consentVersion.present) {
      map['consent_version'] = Variable<int>(consentVersion.value);
    }
    if (consentLanguage.present) {
      map['consent_language'] = Variable<String>(consentLanguage.value);
    }
    if (consentShownAt.present) {
      map['consent_shown_at'] = Variable<DateTime>(consentShownAt.value);
    }
    if (consentContentHash.present) {
      map['consent_content_hash'] = Variable<String>(consentContentHash.value);
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
          ..write('consentVersion: $consentVersion, ')
          ..write('consentLanguage: $consentLanguage, ')
          ..write('consentShownAt: $consentShownAt, ')
          ..write('consentContentHash: $consentContentHash, ')
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

class AuditEvents extends Table with TableInfo<AuditEvents, AuditEventsData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  AuditEvents(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> correlationId = GeneratedColumn<String>(
    'correlation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> actorId = GeneratedColumn<String>(
    'actor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> remarks = GeneratedColumn<String>(
    'remarks',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const CustomExpression('0'),
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
    seq,
    id,
    action,
    entity,
    entityId,
    correlationId,
    actorId,
    remarks,
    occurredAt,
    attempts,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'audit_events';
  @override
  Set<GeneratedColumn> get $primaryKey => {seq};
  @override
  AuditEventsData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuditEventsData(
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      correlationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}correlation_id'],
      )!,
      actorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_id'],
      )!,
      remarks: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remarks'],
      ),
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  AuditEvents createAlias(String alias) {
    return AuditEvents(attachedDatabase, alias);
  }
}

class AuditEventsData extends DataClass implements Insertable<AuditEventsData> {
  final int seq;
  final String id;
  final String action;
  final String entity;
  final String entityId;
  final String correlationId;
  final String actorId;
  final String? remarks;
  final DateTime occurredAt;
  final int attempts;
  final String? lastError;
  const AuditEventsData({
    required this.seq,
    required this.id,
    required this.action,
    required this.entity,
    required this.entityId,
    required this.correlationId,
    required this.actorId,
    this.remarks,
    required this.occurredAt,
    required this.attempts,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['seq'] = Variable<int>(seq);
    map['id'] = Variable<String>(id);
    map['action'] = Variable<String>(action);
    map['entity'] = Variable<String>(entity);
    map['entity_id'] = Variable<String>(entityId);
    map['correlation_id'] = Variable<String>(correlationId);
    map['actor_id'] = Variable<String>(actorId);
    if (!nullToAbsent || remarks != null) {
      map['remarks'] = Variable<String>(remarks);
    }
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  AuditEventsCompanion toCompanion(bool nullToAbsent) {
    return AuditEventsCompanion(
      seq: Value(seq),
      id: Value(id),
      action: Value(action),
      entity: Value(entity),
      entityId: Value(entityId),
      correlationId: Value(correlationId),
      actorId: Value(actorId),
      remarks: remarks == null && nullToAbsent
          ? const Value.absent()
          : Value(remarks),
      occurredAt: Value(occurredAt),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory AuditEventsData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuditEventsData(
      seq: serializer.fromJson<int>(json['seq']),
      id: serializer.fromJson<String>(json['id']),
      action: serializer.fromJson<String>(json['action']),
      entity: serializer.fromJson<String>(json['entity']),
      entityId: serializer.fromJson<String>(json['entityId']),
      correlationId: serializer.fromJson<String>(json['correlationId']),
      actorId: serializer.fromJson<String>(json['actorId']),
      remarks: serializer.fromJson<String?>(json['remarks']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seq': serializer.toJson<int>(seq),
      'id': serializer.toJson<String>(id),
      'action': serializer.toJson<String>(action),
      'entity': serializer.toJson<String>(entity),
      'entityId': serializer.toJson<String>(entityId),
      'correlationId': serializer.toJson<String>(correlationId),
      'actorId': serializer.toJson<String>(actorId),
      'remarks': serializer.toJson<String?>(remarks),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  AuditEventsData copyWith({
    int? seq,
    String? id,
    String? action,
    String? entity,
    String? entityId,
    String? correlationId,
    String? actorId,
    Value<String?> remarks = const Value.absent(),
    DateTime? occurredAt,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
  }) => AuditEventsData(
    seq: seq ?? this.seq,
    id: id ?? this.id,
    action: action ?? this.action,
    entity: entity ?? this.entity,
    entityId: entityId ?? this.entityId,
    correlationId: correlationId ?? this.correlationId,
    actorId: actorId ?? this.actorId,
    remarks: remarks.present ? remarks.value : this.remarks,
    occurredAt: occurredAt ?? this.occurredAt,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  AuditEventsData copyWithCompanion(AuditEventsCompanion data) {
    return AuditEventsData(
      seq: data.seq.present ? data.seq.value : this.seq,
      id: data.id.present ? data.id.value : this.id,
      action: data.action.present ? data.action.value : this.action,
      entity: data.entity.present ? data.entity.value : this.entity,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      correlationId: data.correlationId.present
          ? data.correlationId.value
          : this.correlationId,
      actorId: data.actorId.present ? data.actorId.value : this.actorId,
      remarks: data.remarks.present ? data.remarks.value : this.remarks,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuditEventsData(')
          ..write('seq: $seq, ')
          ..write('id: $id, ')
          ..write('action: $action, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('correlationId: $correlationId, ')
          ..write('actorId: $actorId, ')
          ..write('remarks: $remarks, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    seq,
    id,
    action,
    entity,
    entityId,
    correlationId,
    actorId,
    remarks,
    occurredAt,
    attempts,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuditEventsData &&
          other.seq == this.seq &&
          other.id == this.id &&
          other.action == this.action &&
          other.entity == this.entity &&
          other.entityId == this.entityId &&
          other.correlationId == this.correlationId &&
          other.actorId == this.actorId &&
          other.remarks == this.remarks &&
          other.occurredAt == this.occurredAt &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class AuditEventsCompanion extends UpdateCompanion<AuditEventsData> {
  final Value<int> seq;
  final Value<String> id;
  final Value<String> action;
  final Value<String> entity;
  final Value<String> entityId;
  final Value<String> correlationId;
  final Value<String> actorId;
  final Value<String?> remarks;
  final Value<DateTime> occurredAt;
  final Value<int> attempts;
  final Value<String?> lastError;
  const AuditEventsCompanion({
    this.seq = const Value.absent(),
    this.id = const Value.absent(),
    this.action = const Value.absent(),
    this.entity = const Value.absent(),
    this.entityId = const Value.absent(),
    this.correlationId = const Value.absent(),
    this.actorId = const Value.absent(),
    this.remarks = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  AuditEventsCompanion.insert({
    this.seq = const Value.absent(),
    required String id,
    required String action,
    required String entity,
    required String entityId,
    required String correlationId,
    required String actorId,
    this.remarks = const Value.absent(),
    required DateTime occurredAt,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  }) : id = Value(id),
       action = Value(action),
       entity = Value(entity),
       entityId = Value(entityId),
       correlationId = Value(correlationId),
       actorId = Value(actorId),
       occurredAt = Value(occurredAt);
  static Insertable<AuditEventsData> custom({
    Expression<int>? seq,
    Expression<String>? id,
    Expression<String>? action,
    Expression<String>? entity,
    Expression<String>? entityId,
    Expression<String>? correlationId,
    Expression<String>? actorId,
    Expression<String>? remarks,
    Expression<DateTime>? occurredAt,
    Expression<int>? attempts,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (seq != null) 'seq': seq,
      if (id != null) 'id': id,
      if (action != null) 'action': action,
      if (entity != null) 'entity': entity,
      if (entityId != null) 'entity_id': entityId,
      if (correlationId != null) 'correlation_id': correlationId,
      if (actorId != null) 'actor_id': actorId,
      if (remarks != null) 'remarks': remarks,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
    });
  }

  AuditEventsCompanion copyWith({
    Value<int>? seq,
    Value<String>? id,
    Value<String>? action,
    Value<String>? entity,
    Value<String>? entityId,
    Value<String>? correlationId,
    Value<String>? actorId,
    Value<String?>? remarks,
    Value<DateTime>? occurredAt,
    Value<int>? attempts,
    Value<String?>? lastError,
  }) {
    return AuditEventsCompanion(
      seq: seq ?? this.seq,
      id: id ?? this.id,
      action: action ?? this.action,
      entity: entity ?? this.entity,
      entityId: entityId ?? this.entityId,
      correlationId: correlationId ?? this.correlationId,
      actorId: actorId ?? this.actorId,
      remarks: remarks ?? this.remarks,
      occurredAt: occurredAt ?? this.occurredAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (correlationId.present) {
      map['correlation_id'] = Variable<String>(correlationId.value);
    }
    if (actorId.present) {
      map['actor_id'] = Variable<String>(actorId.value);
    }
    if (remarks.present) {
      map['remarks'] = Variable<String>(remarks.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuditEventsCompanion(')
          ..write('seq: $seq, ')
          ..write('id: $id, ')
          ..write('action: $action, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('correlationId: $correlationId, ')
          ..write('actorId: $actorId, ')
          ..write('remarks: $remarks, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

class ConsentNotices extends Table
    with TableInfo<ConsentNotices, ConsentNoticesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ConsentNotices(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
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
  List<GeneratedColumn> get $columns => [
    version,
    language,
    title,
    body,
    contentHash,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'consent_notices';
  @override
  Set<GeneratedColumn> get $primaryKey => {version, language};
  @override
  ConsentNoticesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConsentNoticesData(
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  ConsentNotices createAlias(String alias) {
    return ConsentNotices(attachedDatabase, alias);
  }
}

class ConsentNoticesData extends DataClass
    implements Insertable<ConsentNoticesData> {
  final int version;
  final String language;
  final String title;
  final String body;
  final String contentHash;
  final DateTime fetchedAt;
  const ConsentNoticesData({
    required this.version,
    required this.language,
    required this.title,
    required this.body,
    required this.contentHash,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['version'] = Variable<int>(version);
    map['language'] = Variable<String>(language);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    map['content_hash'] = Variable<String>(contentHash);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  ConsentNoticesCompanion toCompanion(bool nullToAbsent) {
    return ConsentNoticesCompanion(
      version: Value(version),
      language: Value(language),
      title: Value(title),
      body: Value(body),
      contentHash: Value(contentHash),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory ConsentNoticesData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConsentNoticesData(
      version: serializer.fromJson<int>(json['version']),
      language: serializer.fromJson<String>(json['language']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'version': serializer.toJson<int>(version),
      'language': serializer.toJson<String>(language),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'contentHash': serializer.toJson<String>(contentHash),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  ConsentNoticesData copyWith({
    int? version,
    String? language,
    String? title,
    String? body,
    String? contentHash,
    DateTime? fetchedAt,
  }) => ConsentNoticesData(
    version: version ?? this.version,
    language: language ?? this.language,
    title: title ?? this.title,
    body: body ?? this.body,
    contentHash: contentHash ?? this.contentHash,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  ConsentNoticesData copyWithCompanion(ConsentNoticesCompanion data) {
    return ConsentNoticesData(
      version: data.version.present ? data.version.value : this.version,
      language: data.language.present ? data.language.value : this.language,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConsentNoticesData(')
          ..write('version: $version, ')
          ..write('language: $language, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('contentHash: $contentHash, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(version, language, title, body, contentHash, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConsentNoticesData &&
          other.version == this.version &&
          other.language == this.language &&
          other.title == this.title &&
          other.body == this.body &&
          other.contentHash == this.contentHash &&
          other.fetchedAt == this.fetchedAt);
}

class ConsentNoticesCompanion extends UpdateCompanion<ConsentNoticesData> {
  final Value<int> version;
  final Value<String> language;
  final Value<String> title;
  final Value<String> body;
  final Value<String> contentHash;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const ConsentNoticesCompanion({
    this.version = const Value.absent(),
    this.language = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConsentNoticesCompanion.insert({
    required int version,
    required String language,
    required String title,
    required String body,
    required String contentHash,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : version = Value(version),
       language = Value(language),
       title = Value(title),
       body = Value(body),
       contentHash = Value(contentHash),
       fetchedAt = Value(fetchedAt);
  static Insertable<ConsentNoticesData> custom({
    Expression<int>? version,
    Expression<String>? language,
    Expression<String>? title,
    Expression<String>? body,
    Expression<String>? contentHash,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (version != null) 'version': version,
      if (language != null) 'language': language,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (contentHash != null) 'content_hash': contentHash,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConsentNoticesCompanion copyWith({
    Value<int>? version,
    Value<String>? language,
    Value<String>? title,
    Value<String>? body,
    Value<String>? contentHash,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return ConsentNoticesCompanion(
      version: version ?? this.version,
      language: language ?? this.language,
      title: title ?? this.title,
      body: body ?? this.body,
      contentHash: contentHash ?? this.contentHash,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
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
    return (StringBuffer('ConsentNoticesCompanion(')
          ..write('version: $version, ')
          ..write('language: $language, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('contentHash: $contentHash, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class DatabaseAtV3 extends GeneratedDatabase {
  DatabaseAtV3(QueryExecutor e) : super(e);
  late final SyncTasks syncTasks = SyncTasks(this);
  late final AttendanceDrafts attendanceDrafts = AttendanceDrafts(this);
  late final CachedReferences cachedReferences = CachedReferences(this);
  late final AuditEvents auditEvents = AuditEvents(this);
  late final ConsentNotices consentNotices = ConsentNotices(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    syncTasks,
    attendanceDrafts,
    cachedReferences,
    auditEvents,
    consentNotices,
  ];
  @override
  int get schemaVersion => 3;
}
