/// Shared Dart models mirroring the FastAPI schemas — used by mobile + web.
///
/// Enum values are stored on the backend as snake_case strings
/// (e.g. `family_caregiver`, `match_it`, `MCI`), so parsing goes through the
/// explicit maps below rather than `Enum.values.byName` (which would expect
/// `familyCaregiver`).
library;

// =====================================================================
// Enums with API serialization
// =====================================================================

enum Role { patient, familyCaregiver, ashaWorker, clinician, admin }

Role roleFromApi(String value) {
  switch (value) {
    case 'family_caregiver':
      return Role.familyCaregiver;
    case 'asha_worker':
      return Role.ashaWorker;
    case 'clinician':
      return Role.clinician;
    case 'admin':
      return Role.admin;
    default:
      return Role.patient;
  }
}

String roleToApi(Role role) {
  switch (role) {
    case Role.familyCaregiver:
      return 'family_caregiver';
    case Role.ashaWorker:
      return 'asha_worker';
    case Role.clinician:
      return 'clinician';
    case Role.admin:
      return 'admin';
    case Role.patient:
      return 'patient';
  }
}

enum CognitiveBaseline { healthy, mci, mildDementia, moderateDementia }

CognitiveBaseline baselineFromApi(String value) {
  switch (value.toLowerCase().replaceAll('_', '')) {
    case 'mci':
      return CognitiveBaseline.mci;
    case 'milddementia':
      return CognitiveBaseline.mildDementia;
    case 'moderatedementia':
      return CognitiveBaseline.moderateDementia;
    default:
      return CognitiveBaseline.healthy;
  }
}

String baselineToApi(CognitiveBaseline baseline) {
  switch (baseline) {
    case CognitiveBaseline.healthy:
      return 'healthy';
    case CognitiveBaseline.mci:
      return 'MCI';
    case CognitiveBaseline.mildDementia:
      return 'mild_dementia';
    case CognitiveBaseline.moderateDementia:
      return 'moderate_dementia';
  }
}

enum GameType { matchIt, routineSequencing, numberRecall, oddOneOut }

GameType gameTypeFromApi(String value) {
  switch (value) {
    case 'routine_sequencing':
      return GameType.routineSequencing;
    case 'number_recall':
      return GameType.numberRecall;
    case 'odd_one_out':
      return GameType.oddOneOut;
    default:
      return GameType.matchIt;
  }
}

String gameTypeToApi(GameType type) {
  switch (type) {
    case GameType.routineSequencing:
      return 'routine_sequencing';
    case GameType.numberRecall:
      return 'number_recall';
    case GameType.oddOneOut:
      return 'odd_one_out';
    case GameType.matchIt:
      return 'match_it';
  }
}

enum ReminderType { medicine, water, food, exercise }

ReminderType reminderTypeFromApi(String value) {
  switch (value) {
    case 'water':
      return ReminderType.water;
    case 'food':
      return ReminderType.food;
    case 'exercise':
      return ReminderType.exercise;
    default:
      return ReminderType.medicine;
  }
}

enum ReminderStatus { pending, acknowledged, missed, escalated }

ReminderStatus reminderStatusFromApi(String value) {
  switch (value) {
    case 'acknowledged':
      return ReminderStatus.acknowledged;
    case 'missed':
      return ReminderStatus.missed;
    case 'escalated':
      return ReminderStatus.escalated;
    default:
      return ReminderStatus.pending;
  }
}

// =====================================================================
// User
// =====================================================================

class UserModel {
  final String id;
  final String phone;
  final String? email;
  final Role role;
  final String preferredLanguage;

  const UserModel({
    required this.id,
    required this.phone,
    this.email,
    required this.role,
    required this.preferredLanguage,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String,
        phone: json['phone'] as String,
        email: json['email'] as String?,
        role: roleFromApi(json['role'] as String? ?? 'patient'),
        preferredLanguage: json['preferred_language'] as String? ?? 'english',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'email': email,
        'role': roleToApi(role),
        'preferred_language': preferredLanguage,
      };
}

// =====================================================================
// Patient profile
// =====================================================================

class PatientModel {
  final String id;
  final String? userId;
  final String name;
  final CognitiveBaseline cognitiveBaseline;
  final String? region;
  final String? district;

  const PatientModel({
    required this.id,
    this.userId,
    required this.name,
    required this.cognitiveBaseline,
    this.region,
    this.district,
  });

  factory PatientModel.fromJson(Map<String, dynamic> json) => PatientModel(
        id: json['id'] as String,
        userId: json['user_id'] as String?,
        name: json['name'] as String? ?? 'Elder',
        cognitiveBaseline: baselineFromApi(json['cognitive_baseline'] as String? ?? 'healthy'),
        region: json['region'] as String?,
        district: json['district'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'cognitive_baseline': baselineToApi(cognitiveBaseline),
        'region': region,
        'district': district,
      };
}

// =====================================================================
// Game sessions
// =====================================================================

class GameSessionModel {
  final String id;
  final String patientId;
  final GameType gameType;
  final int difficultyLevel;
  final int attempts;
  final int correctCount;
  final int incorrectCount;
  final double? avgResponseTimeMs;
  final DateTime startedAt;
  final DateTime? completedAt;

  const GameSessionModel({
    required this.id,
    required this.patientId,
    required this.gameType,
    required this.difficultyLevel,
    required this.attempts,
    required this.correctCount,
    required this.incorrectCount,
    this.avgResponseTimeMs,
    required this.startedAt,
    this.completedAt,
  });

  factory GameSessionModel.fromJson(Map<String, dynamic> json) => GameSessionModel(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        gameType: gameTypeFromApi(json['game_type'] as String? ?? 'match_it'),
        difficultyLevel: json['difficulty_level'] as int? ?? 1,
        attempts: json['attempts'] as int? ?? 0,
        correctCount: json['correct_count'] as int? ?? 0,
        incorrectCount: json['incorrect_count'] as int? ?? 0,
        avgResponseTimeMs: (json['avg_response_time_ms'] as num?)?.toDouble(),
        startedAt: DateTime.parse(json['started_at'] as String),
        completedAt: json['completed_at'] != null
            ? DateTime.parse(json['completed_at'] as String)
            : null,
      );
}

// =====================================================================
// Reminders
// =====================================================================

class ReminderScheduleModel {
  final String id;
  final String patientId;
  final ReminderType reminderType;
  final String cadence;
  final bool isActive;
  final DateTime createdAt;

  const ReminderScheduleModel({
    required this.id,
    required this.patientId,
    required this.reminderType,
    required this.cadence,
    required this.isActive,
    required this.createdAt,
  });

  factory ReminderScheduleModel.fromJson(Map<String, dynamic> json) =>
      ReminderScheduleModel(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        reminderType: reminderTypeFromApi(json['reminder_type'] as String? ?? 'medicine'),
        cadence: json['cadence'] as String? ?? '',
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class ReminderEventModel {
  final String id;
  final String scheduleId;
  final String patientId;
  final DateTime scheduledAt;
  final DateTime? deliveredAt;
  final DateTime? acknowledgedAt;
  final String? acknowledgmentMethod;
  final ReminderStatus status;
  final DateTime? syncedAt;

  const ReminderEventModel({
    required this.id,
    required this.scheduleId,
    required this.patientId,
    required this.scheduledAt,
    this.deliveredAt,
    this.acknowledgedAt,
    this.acknowledgmentMethod,
    required this.status,
    this.syncedAt,
  });

  factory ReminderEventModel.fromJson(Map<String, dynamic> json) => ReminderEventModel(
        id: json['id'] as String,
        scheduleId: json['schedule_id'] as String,
        patientId: json['patient_id'] as String,
        scheduledAt: DateTime.parse(json['scheduled_at'] as String),
        deliveredAt: json['delivered_at'] != null
            ? DateTime.parse(json['delivered_at'] as String)
            : null,
        acknowledgedAt: json['acknowledged_at'] != null
            ? DateTime.parse(json['acknowledged_at'] as String)
            : null,
        acknowledgmentMethod: json['acknowledgment_method'] as String?,
        status: reminderStatusFromApi(json['status'] as String? ?? 'pending'),
        syncedAt: json['synced_at'] != null
            ? DateTime.parse(json['synced_at'] as String)
            : null,
      );
}

// =====================================================================
// Voice companion reply
// =====================================================================

class CompanionReply {
  final String replyText;
  final String patientLanguage;
  final bool fallback;
  final String? reason;

  const CompanionReply({
    required this.replyText,
    required this.patientLanguage,
    this.fallback = false,
    this.reason,
  });

  factory CompanionReply.fromJson(Map<String, dynamic> json) => CompanionReply(
        replyText: json['reply_text'] as String? ?? '',
        patientLanguage: json['patient_language'] as String? ?? 'english',
        fallback: json['fallback'] as bool? ?? false,
        reason: json['reason'] as String?,
      );
}

// =====================================================================
// Game content packs
// =====================================================================

class ContentPackSummary {
  final String id;
  final String name;
  final String region;
  final String description;
  final int itemCount;

  const ContentPackSummary({
    required this.id,
    required this.name,
    required this.region,
    required this.description,
    required this.itemCount,
  });

  factory ContentPackSummary.fromJson(Map<String, dynamic> json) =>
      ContentPackSummary(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Pack',
        region: json['region'] as String? ?? 'NER',
        description: json['description'] as String? ?? '',
        itemCount: json['item_count'] as int? ?? 0,
      );
}
