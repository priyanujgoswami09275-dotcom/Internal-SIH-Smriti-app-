// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $GameSessionsTable extends GameSessions
    with TableInfo<$GameSessionsTable, GameSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GameSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _patientIdMeta =
      const VerificationMeta('patientId');
  @override
  late final GeneratedColumn<String> patientId = GeneratedColumn<String>(
      'patient_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _gameTypeMeta =
      const VerificationMeta('gameType');
  @override
  late final GeneratedColumn<String> gameType = GeneratedColumn<String>(
      'game_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _difficultyLevelMeta =
      const VerificationMeta('difficultyLevel');
  @override
  late final GeneratedColumn<int> difficultyLevel = GeneratedColumn<int>(
      'difficulty_level', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _attemptsMeta =
      const VerificationMeta('attempts');
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
      'attempts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _correctCountMeta =
      const VerificationMeta('correctCount');
  @override
  late final GeneratedColumn<int> correctCount = GeneratedColumn<int>(
      'correct_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _incorrectCountMeta =
      const VerificationMeta('incorrectCount');
  @override
  late final GeneratedColumn<int> incorrectCount = GeneratedColumn<int>(
      'incorrect_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _avgResponseTimeMsMeta =
      const VerificationMeta('avgResponseTimeMs');
  @override
  late final GeneratedColumn<double> avgResponseTimeMs =
      GeneratedColumn<double>('avg_response_time_ms', aliasedName, true,
          type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _startedAtMeta =
      const VerificationMeta('startedAt');
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
      'started_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _completedAtMeta =
      const VerificationMeta('completedAt');
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
      'completed_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
      'synced', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("synced" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        patientId,
        gameType,
        difficultyLevel,
        attempts,
        correctCount,
        incorrectCount,
        avgResponseTimeMs,
        startedAt,
        completedAt,
        synced
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'game_sessions';
  @override
  VerificationContext validateIntegrity(Insertable<GameSessionRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('patient_id')) {
      context.handle(_patientIdMeta,
          patientId.isAcceptableOrUnknown(data['patient_id']!, _patientIdMeta));
    } else if (isInserting) {
      context.missing(_patientIdMeta);
    }
    if (data.containsKey('game_type')) {
      context.handle(_gameTypeMeta,
          gameType.isAcceptableOrUnknown(data['game_type']!, _gameTypeMeta));
    } else if (isInserting) {
      context.missing(_gameTypeMeta);
    }
    if (data.containsKey('difficulty_level')) {
      context.handle(
          _difficultyLevelMeta,
          difficultyLevel.isAcceptableOrUnknown(
              data['difficulty_level']!, _difficultyLevelMeta));
    }
    if (data.containsKey('attempts')) {
      context.handle(_attemptsMeta,
          attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta));
    }
    if (data.containsKey('correct_count')) {
      context.handle(
          _correctCountMeta,
          correctCount.isAcceptableOrUnknown(
              data['correct_count']!, _correctCountMeta));
    }
    if (data.containsKey('incorrect_count')) {
      context.handle(
          _incorrectCountMeta,
          incorrectCount.isAcceptableOrUnknown(
              data['incorrect_count']!, _incorrectCountMeta));
    }
    if (data.containsKey('avg_response_time_ms')) {
      context.handle(
          _avgResponseTimeMsMeta,
          avgResponseTimeMs.isAcceptableOrUnknown(
              data['avg_response_time_ms']!, _avgResponseTimeMsMeta));
    }
    if (data.containsKey('started_at')) {
      context.handle(_startedAtMeta,
          startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta));
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
          _completedAtMeta,
          completedAt.isAcceptableOrUnknown(
              data['completed_at']!, _completedAtMeta));
    }
    if (data.containsKey('synced')) {
      context.handle(_syncedMeta,
          synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GameSessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GameSessionRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      patientId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}patient_id'])!,
      gameType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}game_type'])!,
      difficultyLevel: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}difficulty_level'])!,
      attempts: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempts'])!,
      correctCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}correct_count'])!,
      incorrectCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}incorrect_count'])!,
      avgResponseTimeMs: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}avg_response_time_ms']),
      startedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}started_at'])!,
      completedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}completed_at']),
      synced: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}synced'])!,
    );
  }

  @override
  $GameSessionsTable createAlias(String alias) {
    return $GameSessionsTable(attachedDatabase, alias);
  }
}

class GameSessionRow extends DataClass implements Insertable<GameSessionRow> {
  final String id;
  final String patientId;
  final String gameType;
  final int difficultyLevel;
  final int attempts;
  final int correctCount;
  final int incorrectCount;
  final double? avgResponseTimeMs;
  final DateTime startedAt;
  final DateTime? completedAt;
  final bool synced;
  const GameSessionRow(
      {required this.id,
      required this.patientId,
      required this.gameType,
      required this.difficultyLevel,
      required this.attempts,
      required this.correctCount,
      required this.incorrectCount,
      this.avgResponseTimeMs,
      required this.startedAt,
      this.completedAt,
      required this.synced});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['patient_id'] = Variable<String>(patientId);
    map['game_type'] = Variable<String>(gameType);
    map['difficulty_level'] = Variable<int>(difficultyLevel);
    map['attempts'] = Variable<int>(attempts);
    map['correct_count'] = Variable<int>(correctCount);
    map['incorrect_count'] = Variable<int>(incorrectCount);
    if (!nullToAbsent || avgResponseTimeMs != null) {
      map['avg_response_time_ms'] = Variable<double>(avgResponseTimeMs);
    }
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    map['synced'] = Variable<bool>(synced);
    return map;
  }

  GameSessionsCompanion toCompanion(bool nullToAbsent) {
    return GameSessionsCompanion(
      id: Value(id),
      patientId: Value(patientId),
      gameType: Value(gameType),
      difficultyLevel: Value(difficultyLevel),
      attempts: Value(attempts),
      correctCount: Value(correctCount),
      incorrectCount: Value(incorrectCount),
      avgResponseTimeMs: avgResponseTimeMs == null && nullToAbsent
          ? const Value.absent()
          : Value(avgResponseTimeMs),
      startedAt: Value(startedAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      synced: Value(synced),
    );
  }

  factory GameSessionRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GameSessionRow(
      id: serializer.fromJson<String>(json['id']),
      patientId: serializer.fromJson<String>(json['patientId']),
      gameType: serializer.fromJson<String>(json['gameType']),
      difficultyLevel: serializer.fromJson<int>(json['difficultyLevel']),
      attempts: serializer.fromJson<int>(json['attempts']),
      correctCount: serializer.fromJson<int>(json['correctCount']),
      incorrectCount: serializer.fromJson<int>(json['incorrectCount']),
      avgResponseTimeMs:
          serializer.fromJson<double?>(json['avgResponseTimeMs']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      synced: serializer.fromJson<bool>(json['synced']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'patientId': serializer.toJson<String>(patientId),
      'gameType': serializer.toJson<String>(gameType),
      'difficultyLevel': serializer.toJson<int>(difficultyLevel),
      'attempts': serializer.toJson<int>(attempts),
      'correctCount': serializer.toJson<int>(correctCount),
      'incorrectCount': serializer.toJson<int>(incorrectCount),
      'avgResponseTimeMs': serializer.toJson<double?>(avgResponseTimeMs),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'synced': serializer.toJson<bool>(synced),
    };
  }

  GameSessionRow copyWith(
          {String? id,
          String? patientId,
          String? gameType,
          int? difficultyLevel,
          int? attempts,
          int? correctCount,
          int? incorrectCount,
          Value<double?> avgResponseTimeMs = const Value.absent(),
          DateTime? startedAt,
          Value<DateTime?> completedAt = const Value.absent(),
          bool? synced}) =>
      GameSessionRow(
        id: id ?? this.id,
        patientId: patientId ?? this.patientId,
        gameType: gameType ?? this.gameType,
        difficultyLevel: difficultyLevel ?? this.difficultyLevel,
        attempts: attempts ?? this.attempts,
        correctCount: correctCount ?? this.correctCount,
        incorrectCount: incorrectCount ?? this.incorrectCount,
        avgResponseTimeMs: avgResponseTimeMs.present
            ? avgResponseTimeMs.value
            : this.avgResponseTimeMs,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt.present ? completedAt.value : this.completedAt,
        synced: synced ?? this.synced,
      );
  GameSessionRow copyWithCompanion(GameSessionsCompanion data) {
    return GameSessionRow(
      id: data.id.present ? data.id.value : this.id,
      patientId: data.patientId.present ? data.patientId.value : this.patientId,
      gameType: data.gameType.present ? data.gameType.value : this.gameType,
      difficultyLevel: data.difficultyLevel.present
          ? data.difficultyLevel.value
          : this.difficultyLevel,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      correctCount: data.correctCount.present
          ? data.correctCount.value
          : this.correctCount,
      incorrectCount: data.incorrectCount.present
          ? data.incorrectCount.value
          : this.incorrectCount,
      avgResponseTimeMs: data.avgResponseTimeMs.present
          ? data.avgResponseTimeMs.value
          : this.avgResponseTimeMs,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      completedAt:
          data.completedAt.present ? data.completedAt.value : this.completedAt,
      synced: data.synced.present ? data.synced.value : this.synced,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GameSessionRow(')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('gameType: $gameType, ')
          ..write('difficultyLevel: $difficultyLevel, ')
          ..write('attempts: $attempts, ')
          ..write('correctCount: $correctCount, ')
          ..write('incorrectCount: $incorrectCount, ')
          ..write('avgResponseTimeMs: $avgResponseTimeMs, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('synced: $synced')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      patientId,
      gameType,
      difficultyLevel,
      attempts,
      correctCount,
      incorrectCount,
      avgResponseTimeMs,
      startedAt,
      completedAt,
      synced);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GameSessionRow &&
          other.id == this.id &&
          other.patientId == this.patientId &&
          other.gameType == this.gameType &&
          other.difficultyLevel == this.difficultyLevel &&
          other.attempts == this.attempts &&
          other.correctCount == this.correctCount &&
          other.incorrectCount == this.incorrectCount &&
          other.avgResponseTimeMs == this.avgResponseTimeMs &&
          other.startedAt == this.startedAt &&
          other.completedAt == this.completedAt &&
          other.synced == this.synced);
}

class GameSessionsCompanion extends UpdateCompanion<GameSessionRow> {
  final Value<String> id;
  final Value<String> patientId;
  final Value<String> gameType;
  final Value<int> difficultyLevel;
  final Value<int> attempts;
  final Value<int> correctCount;
  final Value<int> incorrectCount;
  final Value<double?> avgResponseTimeMs;
  final Value<DateTime> startedAt;
  final Value<DateTime?> completedAt;
  final Value<bool> synced;
  final Value<int> rowid;
  const GameSessionsCompanion({
    this.id = const Value.absent(),
    this.patientId = const Value.absent(),
    this.gameType = const Value.absent(),
    this.difficultyLevel = const Value.absent(),
    this.attempts = const Value.absent(),
    this.correctCount = const Value.absent(),
    this.incorrectCount = const Value.absent(),
    this.avgResponseTimeMs = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.synced = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GameSessionsCompanion.insert({
    required String id,
    required String patientId,
    required String gameType,
    this.difficultyLevel = const Value.absent(),
    this.attempts = const Value.absent(),
    this.correctCount = const Value.absent(),
    this.incorrectCount = const Value.absent(),
    this.avgResponseTimeMs = const Value.absent(),
    required DateTime startedAt,
    this.completedAt = const Value.absent(),
    this.synced = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        patientId = Value(patientId),
        gameType = Value(gameType),
        startedAt = Value(startedAt);
  static Insertable<GameSessionRow> custom({
    Expression<String>? id,
    Expression<String>? patientId,
    Expression<String>? gameType,
    Expression<int>? difficultyLevel,
    Expression<int>? attempts,
    Expression<int>? correctCount,
    Expression<int>? incorrectCount,
    Expression<double>? avgResponseTimeMs,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? completedAt,
    Expression<bool>? synced,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (patientId != null) 'patient_id': patientId,
      if (gameType != null) 'game_type': gameType,
      if (difficultyLevel != null) 'difficulty_level': difficultyLevel,
      if (attempts != null) 'attempts': attempts,
      if (correctCount != null) 'correct_count': correctCount,
      if (incorrectCount != null) 'incorrect_count': incorrectCount,
      if (avgResponseTimeMs != null) 'avg_response_time_ms': avgResponseTimeMs,
      if (startedAt != null) 'started_at': startedAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (synced != null) 'synced': synced,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GameSessionsCompanion copyWith(
      {Value<String>? id,
      Value<String>? patientId,
      Value<String>? gameType,
      Value<int>? difficultyLevel,
      Value<int>? attempts,
      Value<int>? correctCount,
      Value<int>? incorrectCount,
      Value<double?>? avgResponseTimeMs,
      Value<DateTime>? startedAt,
      Value<DateTime?>? completedAt,
      Value<bool>? synced,
      Value<int>? rowid}) {
    return GameSessionsCompanion(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      gameType: gameType ?? this.gameType,
      difficultyLevel: difficultyLevel ?? this.difficultyLevel,
      attempts: attempts ?? this.attempts,
      correctCount: correctCount ?? this.correctCount,
      incorrectCount: incorrectCount ?? this.incorrectCount,
      avgResponseTimeMs: avgResponseTimeMs ?? this.avgResponseTimeMs,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      synced: synced ?? this.synced,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (patientId.present) {
      map['patient_id'] = Variable<String>(patientId.value);
    }
    if (gameType.present) {
      map['game_type'] = Variable<String>(gameType.value);
    }
    if (difficultyLevel.present) {
      map['difficulty_level'] = Variable<int>(difficultyLevel.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (correctCount.present) {
      map['correct_count'] = Variable<int>(correctCount.value);
    }
    if (incorrectCount.present) {
      map['incorrect_count'] = Variable<int>(incorrectCount.value);
    }
    if (avgResponseTimeMs.present) {
      map['avg_response_time_ms'] = Variable<double>(avgResponseTimeMs.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GameSessionsCompanion(')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('gameType: $gameType, ')
          ..write('difficultyLevel: $difficultyLevel, ')
          ..write('attempts: $attempts, ')
          ..write('correctCount: $correctCount, ')
          ..write('incorrectCount: $incorrectCount, ')
          ..write('avgResponseTimeMs: $avgResponseTimeMs, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('synced: $synced, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GameActionsTable extends GameActions
    with TableInfo<$GameActionsTable, GameActionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GameActionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sessionIdMeta =
      const VerificationMeta('sessionId');
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
      'session_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES game_sessions (id)'));
  static const VerificationMeta _actionTypeMeta =
      const VerificationMeta('actionType');
  @override
  late final GeneratedColumn<String> actionType = GeneratedColumn<String>(
      'action_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _actionDataMeta =
      const VerificationMeta('actionData');
  @override
  late final GeneratedColumn<String> actionData = GeneratedColumn<String>(
      'action_data', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isCorrectMeta =
      const VerificationMeta('isCorrect');
  @override
  late final GeneratedColumn<bool> isCorrect = GeneratedColumn<bool>(
      'is_correct', aliasedName, true,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_correct" IN (0, 1))'));
  static const VerificationMeta _responseTimeMsMeta =
      const VerificationMeta('responseTimeMs');
  @override
  late final GeneratedColumn<int> responseTimeMs = GeneratedColumn<int>(
      'response_time_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
      'synced', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("synced" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        sessionId,
        actionType,
        actionData,
        isCorrect,
        responseTimeMs,
        timestamp,
        synced
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'game_actions';
  @override
  VerificationContext validateIntegrity(Insertable<GameActionRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(_sessionIdMeta,
          sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta));
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('action_type')) {
      context.handle(
          _actionTypeMeta,
          actionType.isAcceptableOrUnknown(
              data['action_type']!, _actionTypeMeta));
    } else if (isInserting) {
      context.missing(_actionTypeMeta);
    }
    if (data.containsKey('action_data')) {
      context.handle(
          _actionDataMeta,
          actionData.isAcceptableOrUnknown(
              data['action_data']!, _actionDataMeta));
    } else if (isInserting) {
      context.missing(_actionDataMeta);
    }
    if (data.containsKey('is_correct')) {
      context.handle(_isCorrectMeta,
          isCorrect.isAcceptableOrUnknown(data['is_correct']!, _isCorrectMeta));
    }
    if (data.containsKey('response_time_ms')) {
      context.handle(
          _responseTimeMsMeta,
          responseTimeMs.isAcceptableOrUnknown(
              data['response_time_ms']!, _responseTimeMsMeta));
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('synced')) {
      context.handle(_syncedMeta,
          synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GameActionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GameActionRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      sessionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}session_id'])!,
      actionType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}action_type'])!,
      actionData: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}action_data'])!,
      isCorrect: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_correct']),
      responseTimeMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}response_time_ms']),
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}timestamp'])!,
      synced: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}synced'])!,
    );
  }

  @override
  $GameActionsTable createAlias(String alias) {
    return $GameActionsTable(attachedDatabase, alias);
  }
}

class GameActionRow extends DataClass implements Insertable<GameActionRow> {
  final String id;
  final String sessionId;
  final String actionType;
  final String actionData;
  final bool? isCorrect;
  final int? responseTimeMs;
  final DateTime timestamp;
  final bool synced;
  const GameActionRow(
      {required this.id,
      required this.sessionId,
      required this.actionType,
      required this.actionData,
      this.isCorrect,
      this.responseTimeMs,
      required this.timestamp,
      required this.synced});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['action_type'] = Variable<String>(actionType);
    map['action_data'] = Variable<String>(actionData);
    if (!nullToAbsent || isCorrect != null) {
      map['is_correct'] = Variable<bool>(isCorrect);
    }
    if (!nullToAbsent || responseTimeMs != null) {
      map['response_time_ms'] = Variable<int>(responseTimeMs);
    }
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['synced'] = Variable<bool>(synced);
    return map;
  }

  GameActionsCompanion toCompanion(bool nullToAbsent) {
    return GameActionsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      actionType: Value(actionType),
      actionData: Value(actionData),
      isCorrect: isCorrect == null && nullToAbsent
          ? const Value.absent()
          : Value(isCorrect),
      responseTimeMs: responseTimeMs == null && nullToAbsent
          ? const Value.absent()
          : Value(responseTimeMs),
      timestamp: Value(timestamp),
      synced: Value(synced),
    );
  }

  factory GameActionRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GameActionRow(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      actionType: serializer.fromJson<String>(json['actionType']),
      actionData: serializer.fromJson<String>(json['actionData']),
      isCorrect: serializer.fromJson<bool?>(json['isCorrect']),
      responseTimeMs: serializer.fromJson<int?>(json['responseTimeMs']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      synced: serializer.fromJson<bool>(json['synced']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'actionType': serializer.toJson<String>(actionType),
      'actionData': serializer.toJson<String>(actionData),
      'isCorrect': serializer.toJson<bool?>(isCorrect),
      'responseTimeMs': serializer.toJson<int?>(responseTimeMs),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'synced': serializer.toJson<bool>(synced),
    };
  }

  GameActionRow copyWith(
          {String? id,
          String? sessionId,
          String? actionType,
          String? actionData,
          Value<bool?> isCorrect = const Value.absent(),
          Value<int?> responseTimeMs = const Value.absent(),
          DateTime? timestamp,
          bool? synced}) =>
      GameActionRow(
        id: id ?? this.id,
        sessionId: sessionId ?? this.sessionId,
        actionType: actionType ?? this.actionType,
        actionData: actionData ?? this.actionData,
        isCorrect: isCorrect.present ? isCorrect.value : this.isCorrect,
        responseTimeMs:
            responseTimeMs.present ? responseTimeMs.value : this.responseTimeMs,
        timestamp: timestamp ?? this.timestamp,
        synced: synced ?? this.synced,
      );
  GameActionRow copyWithCompanion(GameActionsCompanion data) {
    return GameActionRow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      actionType:
          data.actionType.present ? data.actionType.value : this.actionType,
      actionData:
          data.actionData.present ? data.actionData.value : this.actionData,
      isCorrect: data.isCorrect.present ? data.isCorrect.value : this.isCorrect,
      responseTimeMs: data.responseTimeMs.present
          ? data.responseTimeMs.value
          : this.responseTimeMs,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      synced: data.synced.present ? data.synced.value : this.synced,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GameActionRow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('actionType: $actionType, ')
          ..write('actionData: $actionData, ')
          ..write('isCorrect: $isCorrect, ')
          ..write('responseTimeMs: $responseTimeMs, ')
          ..write('timestamp: $timestamp, ')
          ..write('synced: $synced')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sessionId, actionType, actionData,
      isCorrect, responseTimeMs, timestamp, synced);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GameActionRow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.actionType == this.actionType &&
          other.actionData == this.actionData &&
          other.isCorrect == this.isCorrect &&
          other.responseTimeMs == this.responseTimeMs &&
          other.timestamp == this.timestamp &&
          other.synced == this.synced);
}

class GameActionsCompanion extends UpdateCompanion<GameActionRow> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> actionType;
  final Value<String> actionData;
  final Value<bool?> isCorrect;
  final Value<int?> responseTimeMs;
  final Value<DateTime> timestamp;
  final Value<bool> synced;
  final Value<int> rowid;
  const GameActionsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.actionType = const Value.absent(),
    this.actionData = const Value.absent(),
    this.isCorrect = const Value.absent(),
    this.responseTimeMs = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.synced = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GameActionsCompanion.insert({
    required String id,
    required String sessionId,
    required String actionType,
    required String actionData,
    this.isCorrect = const Value.absent(),
    this.responseTimeMs = const Value.absent(),
    required DateTime timestamp,
    this.synced = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        sessionId = Value(sessionId),
        actionType = Value(actionType),
        actionData = Value(actionData),
        timestamp = Value(timestamp);
  static Insertable<GameActionRow> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? actionType,
    Expression<String>? actionData,
    Expression<bool>? isCorrect,
    Expression<int>? responseTimeMs,
    Expression<DateTime>? timestamp,
    Expression<bool>? synced,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (actionType != null) 'action_type': actionType,
      if (actionData != null) 'action_data': actionData,
      if (isCorrect != null) 'is_correct': isCorrect,
      if (responseTimeMs != null) 'response_time_ms': responseTimeMs,
      if (timestamp != null) 'timestamp': timestamp,
      if (synced != null) 'synced': synced,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GameActionsCompanion copyWith(
      {Value<String>? id,
      Value<String>? sessionId,
      Value<String>? actionType,
      Value<String>? actionData,
      Value<bool?>? isCorrect,
      Value<int?>? responseTimeMs,
      Value<DateTime>? timestamp,
      Value<bool>? synced,
      Value<int>? rowid}) {
    return GameActionsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      actionType: actionType ?? this.actionType,
      actionData: actionData ?? this.actionData,
      isCorrect: isCorrect ?? this.isCorrect,
      responseTimeMs: responseTimeMs ?? this.responseTimeMs,
      timestamp: timestamp ?? this.timestamp,
      synced: synced ?? this.synced,
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
    if (actionType.present) {
      map['action_type'] = Variable<String>(actionType.value);
    }
    if (actionData.present) {
      map['action_data'] = Variable<String>(actionData.value);
    }
    if (isCorrect.present) {
      map['is_correct'] = Variable<bool>(isCorrect.value);
    }
    if (responseTimeMs.present) {
      map['response_time_ms'] = Variable<int>(responseTimeMs.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GameActionsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('actionType: $actionType, ')
          ..write('actionData: $actionData, ')
          ..write('isCorrect: $isCorrect, ')
          ..write('responseTimeMs: $responseTimeMs, ')
          ..write('timestamp: $timestamp, ')
          ..write('synced: $synced, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReminderEventsTable extends ReminderEvents
    with TableInfo<$ReminderEventsTable, ReminderEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReminderEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _scheduleIdMeta =
      const VerificationMeta('scheduleId');
  @override
  late final GeneratedColumn<String> scheduleId = GeneratedColumn<String>(
      'schedule_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _patientIdMeta =
      const VerificationMeta('patientId');
  @override
  late final GeneratedColumn<String> patientId = GeneratedColumn<String>(
      'patient_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _scheduledAtMeta =
      const VerificationMeta('scheduledAt');
  @override
  late final GeneratedColumn<DateTime> scheduledAt = GeneratedColumn<DateTime>(
      'scheduled_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _deliveredAtMeta =
      const VerificationMeta('deliveredAt');
  @override
  late final GeneratedColumn<DateTime> deliveredAt = GeneratedColumn<DateTime>(
      'delivered_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _acknowledgedAtMeta =
      const VerificationMeta('acknowledgedAt');
  @override
  late final GeneratedColumn<DateTime> acknowledgedAt =
      GeneratedColumn<DateTime>('acknowledged_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
      'synced', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("synced" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        scheduleId,
        patientId,
        scheduledAt,
        deliveredAt,
        acknowledgedAt,
        status,
        synced
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reminder_events';
  @override
  VerificationContext validateIntegrity(Insertable<ReminderEventRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('schedule_id')) {
      context.handle(
          _scheduleIdMeta,
          scheduleId.isAcceptableOrUnknown(
              data['schedule_id']!, _scheduleIdMeta));
    } else if (isInserting) {
      context.missing(_scheduleIdMeta);
    }
    if (data.containsKey('patient_id')) {
      context.handle(_patientIdMeta,
          patientId.isAcceptableOrUnknown(data['patient_id']!, _patientIdMeta));
    } else if (isInserting) {
      context.missing(_patientIdMeta);
    }
    if (data.containsKey('scheduled_at')) {
      context.handle(
          _scheduledAtMeta,
          scheduledAt.isAcceptableOrUnknown(
              data['scheduled_at']!, _scheduledAtMeta));
    } else if (isInserting) {
      context.missing(_scheduledAtMeta);
    }
    if (data.containsKey('delivered_at')) {
      context.handle(
          _deliveredAtMeta,
          deliveredAt.isAcceptableOrUnknown(
              data['delivered_at']!, _deliveredAtMeta));
    }
    if (data.containsKey('acknowledged_at')) {
      context.handle(
          _acknowledgedAtMeta,
          acknowledgedAt.isAcceptableOrUnknown(
              data['acknowledged_at']!, _acknowledgedAtMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('synced')) {
      context.handle(_syncedMeta,
          synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReminderEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReminderEventRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      scheduleId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}schedule_id'])!,
      patientId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}patient_id'])!,
      scheduledAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}scheduled_at'])!,
      deliveredAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}delivered_at']),
      acknowledgedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}acknowledged_at']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      synced: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}synced'])!,
    );
  }

  @override
  $ReminderEventsTable createAlias(String alias) {
    return $ReminderEventsTable(attachedDatabase, alias);
  }
}

class ReminderEventRow extends DataClass
    implements Insertable<ReminderEventRow> {
  final String id;
  final String scheduleId;
  final String patientId;
  final DateTime scheduledAt;
  final DateTime? deliveredAt;
  final DateTime? acknowledgedAt;
  final String status;
  final bool synced;
  const ReminderEventRow(
      {required this.id,
      required this.scheduleId,
      required this.patientId,
      required this.scheduledAt,
      this.deliveredAt,
      this.acknowledgedAt,
      required this.status,
      required this.synced});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['schedule_id'] = Variable<String>(scheduleId);
    map['patient_id'] = Variable<String>(patientId);
    map['scheduled_at'] = Variable<DateTime>(scheduledAt);
    if (!nullToAbsent || deliveredAt != null) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt);
    }
    if (!nullToAbsent || acknowledgedAt != null) {
      map['acknowledged_at'] = Variable<DateTime>(acknowledgedAt);
    }
    map['status'] = Variable<String>(status);
    map['synced'] = Variable<bool>(synced);
    return map;
  }

  ReminderEventsCompanion toCompanion(bool nullToAbsent) {
    return ReminderEventsCompanion(
      id: Value(id),
      scheduleId: Value(scheduleId),
      patientId: Value(patientId),
      scheduledAt: Value(scheduledAt),
      deliveredAt: deliveredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveredAt),
      acknowledgedAt: acknowledgedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(acknowledgedAt),
      status: Value(status),
      synced: Value(synced),
    );
  }

  factory ReminderEventRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReminderEventRow(
      id: serializer.fromJson<String>(json['id']),
      scheduleId: serializer.fromJson<String>(json['scheduleId']),
      patientId: serializer.fromJson<String>(json['patientId']),
      scheduledAt: serializer.fromJson<DateTime>(json['scheduledAt']),
      deliveredAt: serializer.fromJson<DateTime?>(json['deliveredAt']),
      acknowledgedAt: serializer.fromJson<DateTime?>(json['acknowledgedAt']),
      status: serializer.fromJson<String>(json['status']),
      synced: serializer.fromJson<bool>(json['synced']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'scheduleId': serializer.toJson<String>(scheduleId),
      'patientId': serializer.toJson<String>(patientId),
      'scheduledAt': serializer.toJson<DateTime>(scheduledAt),
      'deliveredAt': serializer.toJson<DateTime?>(deliveredAt),
      'acknowledgedAt': serializer.toJson<DateTime?>(acknowledgedAt),
      'status': serializer.toJson<String>(status),
      'synced': serializer.toJson<bool>(synced),
    };
  }

  ReminderEventRow copyWith(
          {String? id,
          String? scheduleId,
          String? patientId,
          DateTime? scheduledAt,
          Value<DateTime?> deliveredAt = const Value.absent(),
          Value<DateTime?> acknowledgedAt = const Value.absent(),
          String? status,
          bool? synced}) =>
      ReminderEventRow(
        id: id ?? this.id,
        scheduleId: scheduleId ?? this.scheduleId,
        patientId: patientId ?? this.patientId,
        scheduledAt: scheduledAt ?? this.scheduledAt,
        deliveredAt: deliveredAt.present ? deliveredAt.value : this.deliveredAt,
        acknowledgedAt:
            acknowledgedAt.present ? acknowledgedAt.value : this.acknowledgedAt,
        status: status ?? this.status,
        synced: synced ?? this.synced,
      );
  ReminderEventRow copyWithCompanion(ReminderEventsCompanion data) {
    return ReminderEventRow(
      id: data.id.present ? data.id.value : this.id,
      scheduleId:
          data.scheduleId.present ? data.scheduleId.value : this.scheduleId,
      patientId: data.patientId.present ? data.patientId.value : this.patientId,
      scheduledAt:
          data.scheduledAt.present ? data.scheduledAt.value : this.scheduledAt,
      deliveredAt:
          data.deliveredAt.present ? data.deliveredAt.value : this.deliveredAt,
      acknowledgedAt: data.acknowledgedAt.present
          ? data.acknowledgedAt.value
          : this.acknowledgedAt,
      status: data.status.present ? data.status.value : this.status,
      synced: data.synced.present ? data.synced.value : this.synced,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReminderEventRow(')
          ..write('id: $id, ')
          ..write('scheduleId: $scheduleId, ')
          ..write('patientId: $patientId, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('acknowledgedAt: $acknowledgedAt, ')
          ..write('status: $status, ')
          ..write('synced: $synced')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, scheduleId, patientId, scheduledAt,
      deliveredAt, acknowledgedAt, status, synced);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReminderEventRow &&
          other.id == this.id &&
          other.scheduleId == this.scheduleId &&
          other.patientId == this.patientId &&
          other.scheduledAt == this.scheduledAt &&
          other.deliveredAt == this.deliveredAt &&
          other.acknowledgedAt == this.acknowledgedAt &&
          other.status == this.status &&
          other.synced == this.synced);
}

class ReminderEventsCompanion extends UpdateCompanion<ReminderEventRow> {
  final Value<String> id;
  final Value<String> scheduleId;
  final Value<String> patientId;
  final Value<DateTime> scheduledAt;
  final Value<DateTime?> deliveredAt;
  final Value<DateTime?> acknowledgedAt;
  final Value<String> status;
  final Value<bool> synced;
  final Value<int> rowid;
  const ReminderEventsCompanion({
    this.id = const Value.absent(),
    this.scheduleId = const Value.absent(),
    this.patientId = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.acknowledgedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.synced = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReminderEventsCompanion.insert({
    required String id,
    required String scheduleId,
    required String patientId,
    required DateTime scheduledAt,
    this.deliveredAt = const Value.absent(),
    this.acknowledgedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.synced = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        scheduleId = Value(scheduleId),
        patientId = Value(patientId),
        scheduledAt = Value(scheduledAt);
  static Insertable<ReminderEventRow> custom({
    Expression<String>? id,
    Expression<String>? scheduleId,
    Expression<String>? patientId,
    Expression<DateTime>? scheduledAt,
    Expression<DateTime>? deliveredAt,
    Expression<DateTime>? acknowledgedAt,
    Expression<String>? status,
    Expression<bool>? synced,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (scheduleId != null) 'schedule_id': scheduleId,
      if (patientId != null) 'patient_id': patientId,
      if (scheduledAt != null) 'scheduled_at': scheduledAt,
      if (deliveredAt != null) 'delivered_at': deliveredAt,
      if (acknowledgedAt != null) 'acknowledged_at': acknowledgedAt,
      if (status != null) 'status': status,
      if (synced != null) 'synced': synced,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReminderEventsCompanion copyWith(
      {Value<String>? id,
      Value<String>? scheduleId,
      Value<String>? patientId,
      Value<DateTime>? scheduledAt,
      Value<DateTime?>? deliveredAt,
      Value<DateTime?>? acknowledgedAt,
      Value<String>? status,
      Value<bool>? synced,
      Value<int>? rowid}) {
    return ReminderEventsCompanion(
      id: id ?? this.id,
      scheduleId: scheduleId ?? this.scheduleId,
      patientId: patientId ?? this.patientId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      status: status ?? this.status,
      synced: synced ?? this.synced,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (scheduleId.present) {
      map['schedule_id'] = Variable<String>(scheduleId.value);
    }
    if (patientId.present) {
      map['patient_id'] = Variable<String>(patientId.value);
    }
    if (scheduledAt.present) {
      map['scheduled_at'] = Variable<DateTime>(scheduledAt.value);
    }
    if (deliveredAt.present) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt.value);
    }
    if (acknowledgedAt.present) {
      map['acknowledged_at'] = Variable<DateTime>(acknowledgedAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReminderEventsCompanion(')
          ..write('id: $id, ')
          ..write('scheduleId: $scheduleId, ')
          ..write('patientId: $patientId, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('acknowledgedAt: $acknowledgedAt, ')
          ..write('status: $status, ')
          ..write('synced: $synced, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncQueueTable extends SyncQueue
    with TableInfo<$SyncQueueTable, SyncQueueRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _patientIdMeta =
      const VerificationMeta('patientId');
  @override
  late final GeneratedColumn<String> patientId = GeneratedColumn<String>(
      'patient_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
      'account_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _resourceTypeMeta =
      const VerificationMeta('resourceType');
  @override
  late final GeneratedColumn<String> resourceType = GeneratedColumn<String>(
      'resource_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _operationMeta =
      const VerificationMeta('operation');
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
      'operation', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _resourceIdMeta =
      const VerificationMeta('resourceId');
  @override
  late final GeneratedColumn<String> resourceId = GeneratedColumn<String>(
      'resource_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _syncedAtMeta =
      const VerificationMeta('syncedAt');
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
      'synced_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _retryCountMeta =
      const VerificationMeta('retryCount');
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
      'retry_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastErrorMeta =
      const VerificationMeta('lastError');
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
      'last_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        patientId,
        accountId,
        resourceType,
        operation,
        resourceId,
        payload,
        createdAt,
        syncedAt,
        retryCount,
        lastError
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_queue';
  @override
  VerificationContext validateIntegrity(Insertable<SyncQueueRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('patient_id')) {
      context.handle(_patientIdMeta,
          patientId.isAcceptableOrUnknown(data['patient_id']!, _patientIdMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    }
    if (data.containsKey('resource_type')) {
      context.handle(
          _resourceTypeMeta,
          resourceType.isAcceptableOrUnknown(
              data['resource_type']!, _resourceTypeMeta));
    } else if (isInserting) {
      context.missing(_resourceTypeMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(_operationMeta,
          operation.isAcceptableOrUnknown(data['operation']!, _operationMeta));
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('resource_id')) {
      context.handle(
          _resourceIdMeta,
          resourceId.isAcceptableOrUnknown(
              data['resource_id']!, _resourceIdMeta));
    } else if (isInserting) {
      context.missing(_resourceIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('synced_at')) {
      context.handle(_syncedAtMeta,
          syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta));
    }
    if (data.containsKey('retry_count')) {
      context.handle(
          _retryCountMeta,
          retryCount.isAcceptableOrUnknown(
              data['retry_count']!, _retryCountMeta));
    }
    if (data.containsKey('last_error')) {
      context.handle(_lastErrorMeta,
          lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncQueueRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncQueueRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      patientId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}patient_id']),
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}account_id']),
      resourceType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}resource_type'])!,
      operation: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}operation'])!,
      resourceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}resource_id'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      syncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}synced_at']),
      retryCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}retry_count'])!,
      lastError: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_error']),
    );
  }

  @override
  $SyncQueueTable createAlias(String alias) {
    return $SyncQueueTable(attachedDatabase, alias);
  }
}

class SyncQueueRow extends DataClass implements Insertable<SyncQueueRow> {
  final String id;
  final String? patientId;
  final String? accountId;
  final String resourceType;
  final String operation;
  final String resourceId;
  final String payload;
  final DateTime createdAt;
  final DateTime? syncedAt;
  final int retryCount;
  final String? lastError;
  const SyncQueueRow(
      {required this.id,
      this.patientId,
      this.accountId,
      required this.resourceType,
      required this.operation,
      required this.resourceId,
      required this.payload,
      required this.createdAt,
      this.syncedAt,
      required this.retryCount,
      this.lastError});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || patientId != null) {
      map['patient_id'] = Variable<String>(patientId);
    }
    if (!nullToAbsent || accountId != null) {
      map['account_id'] = Variable<String>(accountId);
    }
    map['resource_type'] = Variable<String>(resourceType);
    map['operation'] = Variable<String>(operation);
    map['resource_id'] = Variable<String>(resourceId);
    map['payload'] = Variable<String>(payload);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  SyncQueueCompanion toCompanion(bool nullToAbsent) {
    return SyncQueueCompanion(
      id: Value(id),
      patientId: patientId == null && nullToAbsent
          ? const Value.absent()
          : Value(patientId),
      accountId: accountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountId),
      resourceType: Value(resourceType),
      operation: Value(operation),
      resourceId: Value(resourceId),
      payload: Value(payload),
      createdAt: Value(createdAt),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
      retryCount: Value(retryCount),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory SyncQueueRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncQueueRow(
      id: serializer.fromJson<String>(json['id']),
      patientId: serializer.fromJson<String?>(json['patientId']),
      accountId: serializer.fromJson<String?>(json['accountId']),
      resourceType: serializer.fromJson<String>(json['resourceType']),
      operation: serializer.fromJson<String>(json['operation']),
      resourceId: serializer.fromJson<String>(json['resourceId']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'patientId': serializer.toJson<String?>(patientId),
      'accountId': serializer.toJson<String?>(accountId),
      'resourceType': serializer.toJson<String>(resourceType),
      'operation': serializer.toJson<String>(operation),
      'resourceId': serializer.toJson<String>(resourceId),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
      'retryCount': serializer.toJson<int>(retryCount),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  SyncQueueRow copyWith(
          {String? id,
          Value<String?> patientId = const Value.absent(),
          Value<String?> accountId = const Value.absent(),
          String? resourceType,
          String? operation,
          String? resourceId,
          String? payload,
          DateTime? createdAt,
          Value<DateTime?> syncedAt = const Value.absent(),
          int? retryCount,
          Value<String?> lastError = const Value.absent()}) =>
      SyncQueueRow(
        id: id ?? this.id,
        patientId: patientId.present ? patientId.value : this.patientId,
        accountId: accountId.present ? accountId.value : this.accountId,
        resourceType: resourceType ?? this.resourceType,
        operation: operation ?? this.operation,
        resourceId: resourceId ?? this.resourceId,
        payload: payload ?? this.payload,
        createdAt: createdAt ?? this.createdAt,
        syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
        retryCount: retryCount ?? this.retryCount,
        lastError: lastError.present ? lastError.value : this.lastError,
      );
  SyncQueueRow copyWithCompanion(SyncQueueCompanion data) {
    return SyncQueueRow(
      id: data.id.present ? data.id.value : this.id,
      patientId: data.patientId.present ? data.patientId.value : this.patientId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      resourceType: data.resourceType.present
          ? data.resourceType.value
          : this.resourceType,
      operation: data.operation.present ? data.operation.value : this.operation,
      resourceId:
          data.resourceId.present ? data.resourceId.value : this.resourceId,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
      retryCount:
          data.retryCount.present ? data.retryCount.value : this.retryCount,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueRow(')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('accountId: $accountId, ')
          ..write('resourceType: $resourceType, ')
          ..write('operation: $operation, ')
          ..write('resourceId: $resourceId, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      patientId,
      accountId,
      resourceType,
      operation,
      resourceId,
      payload,
      createdAt,
      syncedAt,
      retryCount,
      lastError);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncQueueRow &&
          other.id == this.id &&
          other.patientId == this.patientId &&
          other.accountId == this.accountId &&
          other.resourceType == this.resourceType &&
          other.operation == this.operation &&
          other.resourceId == this.resourceId &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.syncedAt == this.syncedAt &&
          other.retryCount == this.retryCount &&
          other.lastError == this.lastError);
}

class SyncQueueCompanion extends UpdateCompanion<SyncQueueRow> {
  final Value<String> id;
  final Value<String?> patientId;
  final Value<String?> accountId;
  final Value<String> resourceType;
  final Value<String> operation;
  final Value<String> resourceId;
  final Value<String> payload;
  final Value<DateTime> createdAt;
  final Value<DateTime?> syncedAt;
  final Value<int> retryCount;
  final Value<String?> lastError;
  final Value<int> rowid;
  const SyncQueueCompanion({
    this.id = const Value.absent(),
    this.patientId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.resourceType = const Value.absent(),
    this.operation = const Value.absent(),
    this.resourceId = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncQueueCompanion.insert({
    required String id,
    this.patientId = const Value.absent(),
    this.accountId = const Value.absent(),
    required String resourceType,
    required String operation,
    required String resourceId,
    required String payload,
    required DateTime createdAt,
    this.syncedAt = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        resourceType = Value(resourceType),
        operation = Value(operation),
        resourceId = Value(resourceId),
        payload = Value(payload),
        createdAt = Value(createdAt);
  static Insertable<SyncQueueRow> custom({
    Expression<String>? id,
    Expression<String>? patientId,
    Expression<String>? accountId,
    Expression<String>? resourceType,
    Expression<String>? operation,
    Expression<String>? resourceId,
    Expression<String>? payload,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? syncedAt,
    Expression<int>? retryCount,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (patientId != null) 'patient_id': patientId,
      if (accountId != null) 'account_id': accountId,
      if (resourceType != null) 'resource_type': resourceType,
      if (operation != null) 'operation': operation,
      if (resourceId != null) 'resource_id': resourceId,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (retryCount != null) 'retry_count': retryCount,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncQueueCompanion copyWith(
      {Value<String>? id,
      Value<String?>? patientId,
      Value<String?>? accountId,
      Value<String>? resourceType,
      Value<String>? operation,
      Value<String>? resourceId,
      Value<String>? payload,
      Value<DateTime>? createdAt,
      Value<DateTime?>? syncedAt,
      Value<int>? retryCount,
      Value<String?>? lastError,
      Value<int>? rowid}) {
    return SyncQueueCompanion(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      accountId: accountId ?? this.accountId,
      resourceType: resourceType ?? this.resourceType,
      operation: operation ?? this.operation,
      resourceId: resourceId ?? this.resourceId,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      retryCount: retryCount ?? this.retryCount,
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
    if (patientId.present) {
      map['patient_id'] = Variable<String>(patientId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (resourceType.present) {
      map['resource_type'] = Variable<String>(resourceType.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (resourceId.present) {
      map['resource_id'] = Variable<String>(resourceId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
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
    return (StringBuffer('SyncQueueCompanion(')
          ..write('id: $id, ')
          ..write('patientId: $patientId, ')
          ..write('accountId: $accountId, ')
          ..write('resourceType: $resourceType, ')
          ..write('operation: $operation, ')
          ..write('resourceId: $resourceId, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PatientRoutinesTable extends PatientRoutines
    with TableInfo<$PatientRoutinesTable, PatientRoutineRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PatientRoutinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _patientIdMeta =
      const VerificationMeta('patientId');
  @override
  late final GeneratedColumn<String> patientId = GeneratedColumn<String>(
      'patient_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _stepsJsonMeta =
      const VerificationMeta('stepsJson');
  @override
  late final GeneratedColumn<String> stepsJson = GeneratedColumn<String>(
      'steps_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [patientId, stepsJson, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'patient_routines';
  @override
  VerificationContext validateIntegrity(Insertable<PatientRoutineRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('patient_id')) {
      context.handle(_patientIdMeta,
          patientId.isAcceptableOrUnknown(data['patient_id']!, _patientIdMeta));
    } else if (isInserting) {
      context.missing(_patientIdMeta);
    }
    if (data.containsKey('steps_json')) {
      context.handle(_stepsJsonMeta,
          stepsJson.isAcceptableOrUnknown(data['steps_json']!, _stepsJsonMeta));
    } else if (isInserting) {
      context.missing(_stepsJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {patientId};
  @override
  PatientRoutineRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PatientRoutineRow(
      patientId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}patient_id'])!,
      stepsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}steps_json'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $PatientRoutinesTable createAlias(String alias) {
    return $PatientRoutinesTable(attachedDatabase, alias);
  }
}

class PatientRoutineRow extends DataClass
    implements Insertable<PatientRoutineRow> {
  final String patientId;
  final String stepsJson;
  final DateTime updatedAt;
  const PatientRoutineRow(
      {required this.patientId,
      required this.stepsJson,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['patient_id'] = Variable<String>(patientId);
    map['steps_json'] = Variable<String>(stepsJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PatientRoutinesCompanion toCompanion(bool nullToAbsent) {
    return PatientRoutinesCompanion(
      patientId: Value(patientId),
      stepsJson: Value(stepsJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory PatientRoutineRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PatientRoutineRow(
      patientId: serializer.fromJson<String>(json['patientId']),
      stepsJson: serializer.fromJson<String>(json['stepsJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'patientId': serializer.toJson<String>(patientId),
      'stepsJson': serializer.toJson<String>(stepsJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PatientRoutineRow copyWith(
          {String? patientId, String? stepsJson, DateTime? updatedAt}) =>
      PatientRoutineRow(
        patientId: patientId ?? this.patientId,
        stepsJson: stepsJson ?? this.stepsJson,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  PatientRoutineRow copyWithCompanion(PatientRoutinesCompanion data) {
    return PatientRoutineRow(
      patientId: data.patientId.present ? data.patientId.value : this.patientId,
      stepsJson: data.stepsJson.present ? data.stepsJson.value : this.stepsJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PatientRoutineRow(')
          ..write('patientId: $patientId, ')
          ..write('stepsJson: $stepsJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(patientId, stepsJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PatientRoutineRow &&
          other.patientId == this.patientId &&
          other.stepsJson == this.stepsJson &&
          other.updatedAt == this.updatedAt);
}

class PatientRoutinesCompanion extends UpdateCompanion<PatientRoutineRow> {
  final Value<String> patientId;
  final Value<String> stepsJson;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PatientRoutinesCompanion({
    this.patientId = const Value.absent(),
    this.stepsJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PatientRoutinesCompanion.insert({
    required String patientId,
    required String stepsJson,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : patientId = Value(patientId),
        stepsJson = Value(stepsJson),
        updatedAt = Value(updatedAt);
  static Insertable<PatientRoutineRow> custom({
    Expression<String>? patientId,
    Expression<String>? stepsJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (patientId != null) 'patient_id': patientId,
      if (stepsJson != null) 'steps_json': stepsJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PatientRoutinesCompanion copyWith(
      {Value<String>? patientId,
      Value<String>? stepsJson,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return PatientRoutinesCompanion(
      patientId: patientId ?? this.patientId,
      stepsJson: stepsJson ?? this.stepsJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (patientId.present) {
      map['patient_id'] = Variable<String>(patientId.value);
    }
    if (stepsJson.present) {
      map['steps_json'] = Variable<String>(stepsJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PatientRoutinesCompanion(')
          ..write('patientId: $patientId, ')
          ..write('stepsJson: $stepsJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $GameSessionsTable gameSessions = $GameSessionsTable(this);
  late final $GameActionsTable gameActions = $GameActionsTable(this);
  late final $ReminderEventsTable reminderEvents = $ReminderEventsTable(this);
  late final $SyncQueueTable syncQueue = $SyncQueueTable(this);
  late final $PatientRoutinesTable patientRoutines =
      $PatientRoutinesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [gameSessions, gameActions, reminderEvents, syncQueue, patientRoutines];
}

typedef $$GameSessionsTableCreateCompanionBuilder = GameSessionsCompanion
    Function({
  required String id,
  required String patientId,
  required String gameType,
  Value<int> difficultyLevel,
  Value<int> attempts,
  Value<int> correctCount,
  Value<int> incorrectCount,
  Value<double?> avgResponseTimeMs,
  required DateTime startedAt,
  Value<DateTime?> completedAt,
  Value<bool> synced,
  Value<int> rowid,
});
typedef $$GameSessionsTableUpdateCompanionBuilder = GameSessionsCompanion
    Function({
  Value<String> id,
  Value<String> patientId,
  Value<String> gameType,
  Value<int> difficultyLevel,
  Value<int> attempts,
  Value<int> correctCount,
  Value<int> incorrectCount,
  Value<double?> avgResponseTimeMs,
  Value<DateTime> startedAt,
  Value<DateTime?> completedAt,
  Value<bool> synced,
  Value<int> rowid,
});

final class $$GameSessionsTableReferences
    extends BaseReferences<_$AppDatabase, $GameSessionsTable, GameSessionRow> {
  $$GameSessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$GameActionsTable, List<GameActionRow>>
      _gameActionsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.gameActions,
              aliasName: 'game_sessions__id__game_actions__session_id');

  $$GameActionsTableProcessedTableManager get gameActionsRefs {
    final manager = $$GameActionsTableTableManager($_db, $_db.gameActions)
        .filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_gameActionsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$GameSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $GameSessionsTable> {
  $$GameSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get patientId => $composableBuilder(
      column: $table.patientId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get gameType => $composableBuilder(
      column: $table.gameType, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get difficultyLevel => $composableBuilder(
      column: $table.difficultyLevel,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get correctCount => $composableBuilder(
      column: $table.correctCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get incorrectCount => $composableBuilder(
      column: $table.incorrectCount,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get avgResponseTimeMs => $composableBuilder(
      column: $table.avgResponseTimeMs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get synced => $composableBuilder(
      column: $table.synced, builder: (column) => ColumnFilters(column));

  Expression<bool> gameActionsRefs(
      Expression<bool> Function($$GameActionsTableFilterComposer f) f) {
    final $$GameActionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.gameActions,
        getReferencedColumn: (t) => t.sessionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$GameActionsTableFilterComposer(
              $db: $db,
              $table: $db.gameActions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$GameSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $GameSessionsTable> {
  $$GameSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get patientId => $composableBuilder(
      column: $table.patientId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get gameType => $composableBuilder(
      column: $table.gameType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get difficultyLevel => $composableBuilder(
      column: $table.difficultyLevel,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get correctCount => $composableBuilder(
      column: $table.correctCount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get incorrectCount => $composableBuilder(
      column: $table.incorrectCount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get avgResponseTimeMs => $composableBuilder(
      column: $table.avgResponseTimeMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get synced => $composableBuilder(
      column: $table.synced, builder: (column) => ColumnOrderings(column));
}

class $$GameSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GameSessionsTable> {
  $$GameSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get patientId =>
      $composableBuilder(column: $table.patientId, builder: (column) => column);

  GeneratedColumn<String> get gameType =>
      $composableBuilder(column: $table.gameType, builder: (column) => column);

  GeneratedColumn<int> get difficultyLevel => $composableBuilder(
      column: $table.difficultyLevel, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<int> get correctCount => $composableBuilder(
      column: $table.correctCount, builder: (column) => column);

  GeneratedColumn<int> get incorrectCount => $composableBuilder(
      column: $table.incorrectCount, builder: (column) => column);

  GeneratedColumn<double> get avgResponseTimeMs => $composableBuilder(
      column: $table.avgResponseTimeMs, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);

  Expression<T> gameActionsRefs<T extends Object>(
      Expression<T> Function($$GameActionsTableAnnotationComposer a) f) {
    final $$GameActionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.gameActions,
        getReferencedColumn: (t) => t.sessionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$GameActionsTableAnnotationComposer(
              $db: $db,
              $table: $db.gameActions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$GameSessionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $GameSessionsTable,
    GameSessionRow,
    $$GameSessionsTableFilterComposer,
    $$GameSessionsTableOrderingComposer,
    $$GameSessionsTableAnnotationComposer,
    $$GameSessionsTableCreateCompanionBuilder,
    $$GameSessionsTableUpdateCompanionBuilder,
    (GameSessionRow, $$GameSessionsTableReferences),
    GameSessionRow,
    PrefetchHooks Function({bool gameActionsRefs})> {
  $$GameSessionsTableTableManager(_$AppDatabase db, $GameSessionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GameSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GameSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GameSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> patientId = const Value.absent(),
            Value<String> gameType = const Value.absent(),
            Value<int> difficultyLevel = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<int> correctCount = const Value.absent(),
            Value<int> incorrectCount = const Value.absent(),
            Value<double?> avgResponseTimeMs = const Value.absent(),
            Value<DateTime> startedAt = const Value.absent(),
            Value<DateTime?> completedAt = const Value.absent(),
            Value<bool> synced = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              GameSessionsCompanion(
            id: id,
            patientId: patientId,
            gameType: gameType,
            difficultyLevel: difficultyLevel,
            attempts: attempts,
            correctCount: correctCount,
            incorrectCount: incorrectCount,
            avgResponseTimeMs: avgResponseTimeMs,
            startedAt: startedAt,
            completedAt: completedAt,
            synced: synced,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String patientId,
            required String gameType,
            Value<int> difficultyLevel = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<int> correctCount = const Value.absent(),
            Value<int> incorrectCount = const Value.absent(),
            Value<double?> avgResponseTimeMs = const Value.absent(),
            required DateTime startedAt,
            Value<DateTime?> completedAt = const Value.absent(),
            Value<bool> synced = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              GameSessionsCompanion.insert(
            id: id,
            patientId: patientId,
            gameType: gameType,
            difficultyLevel: difficultyLevel,
            attempts: attempts,
            correctCount: correctCount,
            incorrectCount: incorrectCount,
            avgResponseTimeMs: avgResponseTimeMs,
            startedAt: startedAt,
            completedAt: completedAt,
            synced: synced,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$GameSessionsTable, GameSessionRow>(table),
                    $$GameSessionsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({gameActionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (gameActionsRefs) db.gameActions],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (gameActionsRefs)
                    await $_getPrefetchedData<GameSessionRow, $GameSessionsTable,
                            GameActionRow>(
                        currentTable: table,
                        referencedTable: $$GameSessionsTableReferences
                            ._gameActionsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$GameSessionsTableReferences(db, table, p0)
                                .gameActionsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.sessionId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$GameSessionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $GameSessionsTable,
    GameSessionRow,
    $$GameSessionsTableFilterComposer,
    $$GameSessionsTableOrderingComposer,
    $$GameSessionsTableAnnotationComposer,
    $$GameSessionsTableCreateCompanionBuilder,
    $$GameSessionsTableUpdateCompanionBuilder,
    (GameSessionRow, $$GameSessionsTableReferences),
    GameSessionRow,
    PrefetchHooks Function({bool gameActionsRefs})>;
typedef $$GameActionsTableCreateCompanionBuilder = GameActionsCompanion
    Function({
  required String id,
  required String sessionId,
  required String actionType,
  required String actionData,
  Value<bool?> isCorrect,
  Value<int?> responseTimeMs,
  required DateTime timestamp,
  Value<bool> synced,
  Value<int> rowid,
});
typedef $$GameActionsTableUpdateCompanionBuilder = GameActionsCompanion
    Function({
  Value<String> id,
  Value<String> sessionId,
  Value<String> actionType,
  Value<String> actionData,
  Value<bool?> isCorrect,
  Value<int?> responseTimeMs,
  Value<DateTime> timestamp,
  Value<bool> synced,
  Value<int> rowid,
});

final class $$GameActionsTableReferences
    extends BaseReferences<_$AppDatabase, $GameActionsTable, GameActionRow> {
  $$GameActionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $GameSessionsTable _sessionIdTable(_$AppDatabase db) => db.gameSessions
      .createAlias('game_actions__session_id__game_sessions__id');

  $$GameSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$GameSessionsTableTableManager($_db, $_db.gameSessions)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$GameActionsTableFilterComposer
    extends Composer<_$AppDatabase, $GameActionsTable> {
  $$GameActionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get actionType => $composableBuilder(
      column: $table.actionType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get actionData => $composableBuilder(
      column: $table.actionData, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isCorrect => $composableBuilder(
      column: $table.isCorrect, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get responseTimeMs => $composableBuilder(
      column: $table.responseTimeMs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get synced => $composableBuilder(
      column: $table.synced, builder: (column) => ColumnFilters(column));

  $$GameSessionsTableFilterComposer get sessionId {
    final $$GameSessionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.gameSessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$GameSessionsTableFilterComposer(
              $db: $db,
              $table: $db.gameSessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$GameActionsTableOrderingComposer
    extends Composer<_$AppDatabase, $GameActionsTable> {
  $$GameActionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get actionType => $composableBuilder(
      column: $table.actionType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get actionData => $composableBuilder(
      column: $table.actionData, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isCorrect => $composableBuilder(
      column: $table.isCorrect, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get responseTimeMs => $composableBuilder(
      column: $table.responseTimeMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get synced => $composableBuilder(
      column: $table.synced, builder: (column) => ColumnOrderings(column));

  $$GameSessionsTableOrderingComposer get sessionId {
    final $$GameSessionsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.gameSessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$GameSessionsTableOrderingComposer(
              $db: $db,
              $table: $db.gameSessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$GameActionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GameActionsTable> {
  $$GameActionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get actionType => $composableBuilder(
      column: $table.actionType, builder: (column) => column);

  GeneratedColumn<String> get actionData => $composableBuilder(
      column: $table.actionData, builder: (column) => column);

  GeneratedColumn<bool> get isCorrect =>
      $composableBuilder(column: $table.isCorrect, builder: (column) => column);

  GeneratedColumn<int> get responseTimeMs => $composableBuilder(
      column: $table.responseTimeMs, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);

  $$GameSessionsTableAnnotationComposer get sessionId {
    final $$GameSessionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.gameSessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$GameSessionsTableAnnotationComposer(
              $db: $db,
              $table: $db.gameSessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$GameActionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $GameActionsTable,
    GameActionRow,
    $$GameActionsTableFilterComposer,
    $$GameActionsTableOrderingComposer,
    $$GameActionsTableAnnotationComposer,
    $$GameActionsTableCreateCompanionBuilder,
    $$GameActionsTableUpdateCompanionBuilder,
    (GameActionRow, $$GameActionsTableReferences),
    GameActionRow,
    PrefetchHooks Function({bool sessionId})> {
  $$GameActionsTableTableManager(_$AppDatabase db, $GameActionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GameActionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GameActionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GameActionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> sessionId = const Value.absent(),
            Value<String> actionType = const Value.absent(),
            Value<String> actionData = const Value.absent(),
            Value<bool?> isCorrect = const Value.absent(),
            Value<int?> responseTimeMs = const Value.absent(),
            Value<DateTime> timestamp = const Value.absent(),
            Value<bool> synced = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              GameActionsCompanion(
            id: id,
            sessionId: sessionId,
            actionType: actionType,
            actionData: actionData,
            isCorrect: isCorrect,
            responseTimeMs: responseTimeMs,
            timestamp: timestamp,
            synced: synced,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String sessionId,
            required String actionType,
            required String actionData,
            Value<bool?> isCorrect = const Value.absent(),
            Value<int?> responseTimeMs = const Value.absent(),
            required DateTime timestamp,
            Value<bool> synced = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              GameActionsCompanion.insert(
            id: id,
            sessionId: sessionId,
            actionType: actionType,
            actionData: actionData,
            isCorrect: isCorrect,
            responseTimeMs: responseTimeMs,
            timestamp: timestamp,
            synced: synced,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$GameActionsTable, GameActionRow>(table),
                    $$GameActionsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (sessionId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.sessionId,
                    referencedTable:
                        $$GameActionsTableReferences._sessionIdTable(db),
                    referencedColumn:
                        $$GameActionsTableReferences._sessionIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$GameActionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $GameActionsTable,
    GameActionRow,
    $$GameActionsTableFilterComposer,
    $$GameActionsTableOrderingComposer,
    $$GameActionsTableAnnotationComposer,
    $$GameActionsTableCreateCompanionBuilder,
    $$GameActionsTableUpdateCompanionBuilder,
    (GameActionRow, $$GameActionsTableReferences),
    GameActionRow,
    PrefetchHooks Function({bool sessionId})>;
typedef $$ReminderEventsTableCreateCompanionBuilder = ReminderEventsCompanion
    Function({
  required String id,
  required String scheduleId,
  required String patientId,
  required DateTime scheduledAt,
  Value<DateTime?> deliveredAt,
  Value<DateTime?> acknowledgedAt,
  Value<String> status,
  Value<bool> synced,
  Value<int> rowid,
});
typedef $$ReminderEventsTableUpdateCompanionBuilder = ReminderEventsCompanion
    Function({
  Value<String> id,
  Value<String> scheduleId,
  Value<String> patientId,
  Value<DateTime> scheduledAt,
  Value<DateTime?> deliveredAt,
  Value<DateTime?> acknowledgedAt,
  Value<String> status,
  Value<bool> synced,
  Value<int> rowid,
});

class $$ReminderEventsTableFilterComposer
    extends Composer<_$AppDatabase, $ReminderEventsTable> {
  $$ReminderEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get scheduleId => $composableBuilder(
      column: $table.scheduleId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get patientId => $composableBuilder(
      column: $table.patientId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get scheduledAt => $composableBuilder(
      column: $table.scheduledAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deliveredAt => $composableBuilder(
      column: $table.deliveredAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get acknowledgedAt => $composableBuilder(
      column: $table.acknowledgedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get synced => $composableBuilder(
      column: $table.synced, builder: (column) => ColumnFilters(column));
}

class $$ReminderEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReminderEventsTable> {
  $$ReminderEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get scheduleId => $composableBuilder(
      column: $table.scheduleId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get patientId => $composableBuilder(
      column: $table.patientId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get scheduledAt => $composableBuilder(
      column: $table.scheduledAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deliveredAt => $composableBuilder(
      column: $table.deliveredAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get acknowledgedAt => $composableBuilder(
      column: $table.acknowledgedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get synced => $composableBuilder(
      column: $table.synced, builder: (column) => ColumnOrderings(column));
}

class $$ReminderEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReminderEventsTable> {
  $$ReminderEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get scheduleId => $composableBuilder(
      column: $table.scheduleId, builder: (column) => column);

  GeneratedColumn<String> get patientId =>
      $composableBuilder(column: $table.patientId, builder: (column) => column);

  GeneratedColumn<DateTime> get scheduledAt => $composableBuilder(
      column: $table.scheduledAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deliveredAt => $composableBuilder(
      column: $table.deliveredAt, builder: (column) => column);

  GeneratedColumn<DateTime> get acknowledgedAt => $composableBuilder(
      column: $table.acknowledgedAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);
}

class $$ReminderEventsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ReminderEventsTable,
    ReminderEventRow,
    $$ReminderEventsTableFilterComposer,
    $$ReminderEventsTableOrderingComposer,
    $$ReminderEventsTableAnnotationComposer,
    $$ReminderEventsTableCreateCompanionBuilder,
    $$ReminderEventsTableUpdateCompanionBuilder,
    (
      ReminderEventRow,
      BaseReferences<_$AppDatabase, $ReminderEventsTable, ReminderEventRow>
    ),
    ReminderEventRow,
    PrefetchHooks Function()> {
  $$ReminderEventsTableTableManager(
      _$AppDatabase db, $ReminderEventsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReminderEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReminderEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReminderEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> scheduleId = const Value.absent(),
            Value<String> patientId = const Value.absent(),
            Value<DateTime> scheduledAt = const Value.absent(),
            Value<DateTime?> deliveredAt = const Value.absent(),
            Value<DateTime?> acknowledgedAt = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<bool> synced = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ReminderEventsCompanion(
            id: id,
            scheduleId: scheduleId,
            patientId: patientId,
            scheduledAt: scheduledAt,
            deliveredAt: deliveredAt,
            acknowledgedAt: acknowledgedAt,
            status: status,
            synced: synced,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String scheduleId,
            required String patientId,
            required DateTime scheduledAt,
            Value<DateTime?> deliveredAt = const Value.absent(),
            Value<DateTime?> acknowledgedAt = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<bool> synced = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ReminderEventsCompanion.insert(
            id: id,
            scheduleId: scheduleId,
            patientId: patientId,
            scheduledAt: scheduledAt,
            deliveredAt: deliveredAt,
            acknowledgedAt: acknowledgedAt,
            status: status,
            synced: synced,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$ReminderEventsTable, ReminderEventRow>(table),
                    BaseReferences<_$AppDatabase, $ReminderEventsTable,
                        ReminderEventRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ReminderEventsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ReminderEventsTable,
    ReminderEventRow,
    $$ReminderEventsTableFilterComposer,
    $$ReminderEventsTableOrderingComposer,
    $$ReminderEventsTableAnnotationComposer,
    $$ReminderEventsTableCreateCompanionBuilder,
    $$ReminderEventsTableUpdateCompanionBuilder,
    (
      ReminderEventRow,
      BaseReferences<_$AppDatabase, $ReminderEventsTable, ReminderEventRow>
    ),
    ReminderEventRow,
    PrefetchHooks Function()>;
typedef $$SyncQueueTableCreateCompanionBuilder = SyncQueueCompanion Function({
  required String id,
  Value<String?> patientId,
  Value<String?> accountId,
  required String resourceType,
  required String operation,
  required String resourceId,
  required String payload,
  required DateTime createdAt,
  Value<DateTime?> syncedAt,
  Value<int> retryCount,
  Value<String?> lastError,
  Value<int> rowid,
});
typedef $$SyncQueueTableUpdateCompanionBuilder = SyncQueueCompanion Function({
  Value<String> id,
  Value<String?> patientId,
  Value<String?> accountId,
  Value<String> resourceType,
  Value<String> operation,
  Value<String> resourceId,
  Value<String> payload,
  Value<DateTime> createdAt,
  Value<DateTime?> syncedAt,
  Value<int> retryCount,
  Value<String?> lastError,
  Value<int> rowid,
});

class $$SyncQueueTableFilterComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get patientId => $composableBuilder(
      column: $table.patientId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get resourceType => $composableBuilder(
      column: $table.resourceType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get operation => $composableBuilder(
      column: $table.operation, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get resourceId => $composableBuilder(
      column: $table.resourceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnFilters(column));
}

class $$SyncQueueTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get patientId => $composableBuilder(
      column: $table.patientId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get resourceType => $composableBuilder(
      column: $table.resourceType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get operation => $composableBuilder(
      column: $table.operation, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get resourceId => $composableBuilder(
      column: $table.resourceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnOrderings(column));
}

class $$SyncQueueTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get patientId =>
      $composableBuilder(column: $table.patientId, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get resourceType => $composableBuilder(
      column: $table.resourceType, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get resourceId => $composableBuilder(
      column: $table.resourceId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$SyncQueueTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncQueueTable,
    SyncQueueRow,
    $$SyncQueueTableFilterComposer,
    $$SyncQueueTableOrderingComposer,
    $$SyncQueueTableAnnotationComposer,
    $$SyncQueueTableCreateCompanionBuilder,
    $$SyncQueueTableUpdateCompanionBuilder,
    (
      SyncQueueRow,
      BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueRow>
    ),
    SyncQueueRow,
    PrefetchHooks Function()> {
  $$SyncQueueTableTableManager(_$AppDatabase db, $SyncQueueTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String?> patientId = const Value.absent(),
            Value<String?> accountId = const Value.absent(),
            Value<String> resourceType = const Value.absent(),
            Value<String> operation = const Value.absent(),
            Value<String> resourceId = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> syncedAt = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncQueueCompanion(
            id: id,
            patientId: patientId,
            accountId: accountId,
            resourceType: resourceType,
            operation: operation,
            resourceId: resourceId,
            payload: payload,
            createdAt: createdAt,
            syncedAt: syncedAt,
            retryCount: retryCount,
            lastError: lastError,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String?> patientId = const Value.absent(),
            Value<String?> accountId = const Value.absent(),
            required String resourceType,
            required String operation,
            required String resourceId,
            required String payload,
            required DateTime createdAt,
            Value<DateTime?> syncedAt = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncQueueCompanion.insert(
            id: id,
            patientId: patientId,
            accountId: accountId,
            resourceType: resourceType,
            operation: operation,
            resourceId: resourceId,
            payload: payload,
            createdAt: createdAt,
            syncedAt: syncedAt,
            retryCount: retryCount,
            lastError: lastError,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$SyncQueueTable, SyncQueueRow>(table),
                    BaseReferences<_$AppDatabase, $SyncQueueTable,
                        SyncQueueRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncQueueTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncQueueTable,
    SyncQueueRow,
    $$SyncQueueTableFilterComposer,
    $$SyncQueueTableOrderingComposer,
    $$SyncQueueTableAnnotationComposer,
    $$SyncQueueTableCreateCompanionBuilder,
    $$SyncQueueTableUpdateCompanionBuilder,
    (
      SyncQueueRow,
      BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueRow>
    ),
    SyncQueueRow,
    PrefetchHooks Function()>;
typedef $$PatientRoutinesTableCreateCompanionBuilder = PatientRoutinesCompanion
    Function({
  required String patientId,
  required String stepsJson,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$PatientRoutinesTableUpdateCompanionBuilder = PatientRoutinesCompanion
    Function({
  Value<String> patientId,
  Value<String> stepsJson,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$PatientRoutinesTableFilterComposer
    extends Composer<_$AppDatabase, $PatientRoutinesTable> {
  $$PatientRoutinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get patientId => $composableBuilder(
      column: $table.patientId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get stepsJson => $composableBuilder(
      column: $table.stepsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$PatientRoutinesTableOrderingComposer
    extends Composer<_$AppDatabase, $PatientRoutinesTable> {
  $$PatientRoutinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get patientId => $composableBuilder(
      column: $table.patientId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get stepsJson => $composableBuilder(
      column: $table.stepsJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$PatientRoutinesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PatientRoutinesTable> {
  $$PatientRoutinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get patientId =>
      $composableBuilder(column: $table.patientId, builder: (column) => column);

  GeneratedColumn<String> get stepsJson =>
      $composableBuilder(column: $table.stepsJson, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PatientRoutinesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PatientRoutinesTable,
    PatientRoutineRow,
    $$PatientRoutinesTableFilterComposer,
    $$PatientRoutinesTableOrderingComposer,
    $$PatientRoutinesTableAnnotationComposer,
    $$PatientRoutinesTableCreateCompanionBuilder,
    $$PatientRoutinesTableUpdateCompanionBuilder,
    (
      PatientRoutineRow,
      BaseReferences<_$AppDatabase, $PatientRoutinesTable, PatientRoutineRow>
    ),
    PatientRoutineRow,
    PrefetchHooks Function()> {
  $$PatientRoutinesTableTableManager(
      _$AppDatabase db, $PatientRoutinesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PatientRoutinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PatientRoutinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PatientRoutinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> patientId = const Value.absent(),
            Value<String> stepsJson = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PatientRoutinesCompanion(
            patientId: patientId,
            stepsJson: stepsJson,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String patientId,
            required String stepsJson,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              PatientRoutinesCompanion.insert(
            patientId: patientId,
            stepsJson: stepsJson,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$PatientRoutinesTable, PatientRoutineRow>(
                        table),
                    BaseReferences<_$AppDatabase, $PatientRoutinesTable,
                        PatientRoutineRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PatientRoutinesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PatientRoutinesTable,
    PatientRoutineRow,
    $$PatientRoutinesTableFilterComposer,
    $$PatientRoutinesTableOrderingComposer,
    $$PatientRoutinesTableAnnotationComposer,
    $$PatientRoutinesTableCreateCompanionBuilder,
    $$PatientRoutinesTableUpdateCompanionBuilder,
    (
      PatientRoutineRow,
      BaseReferences<_$AppDatabase, $PatientRoutinesTable, PatientRoutineRow>
    ),
    PatientRoutineRow,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$GameSessionsTableTableManager get gameSessions =>
      $$GameSessionsTableTableManager(_db, _db.gameSessions);
  $$GameActionsTableTableManager get gameActions =>
      $$GameActionsTableTableManager(_db, _db.gameActions);
  $$ReminderEventsTableTableManager get reminderEvents =>
      $$ReminderEventsTableTableManager(_db, _db.reminderEvents);
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db, _db.syncQueue);
  $$PatientRoutinesTableTableManager get patientRoutines =>
      $$PatientRoutinesTableTableManager(_db, _db.patientRoutines);
}
