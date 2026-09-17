import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';

part 'exercises.freezed.dart';

/// Exercise table — scalar fields only.
///
/// Muscles, equipment, instructions, aliases, media, variations, tags, and
/// source/provenance all live in their own tables (`exercise_muscles`,
/// `exercise_equipment`, `exercise_instructions`, `exercise_aliases`,
/// `exercise_media`, `exercise_variations`, `exercise_tags`,
/// `exercise_sources`) joined on [id], rather than being packed into
/// columns here — see `ExerciseDao.getWithDetails` for the assembled view.
class ExercisesTable extends Table {
  /// Stable UUID, never reused.
  TextColumn get id => text()();

  /// URL/asset-safe identifier, e.g. "dumbbell-incline-row".
  TextColumn get slug => text().unique()();

  /// Display name, unique. e.g. "Barbell Bench Press".
  TextColumn get name => text().unique()();

  /// Short summary, distinct from the step-by-step [ExerciseInstructionsTable].
  TextColumn get description => text().withDefault(const Constant(''))();

  /// One of [ExerciseCategory].
  TextColumn get category => text()();

  /// One of [Difficulty].
  TextColumn get difficulty => text()();

  /// Movement pattern. One of [MovementPattern].
  TextColumn get movementPattern => text()();

  /// One of [ForceType]. Nullable — not curated for every exercise.
  TextColumn get forceType => text().nullable()();

  /// One of [Mechanic]. Nullable — not curated for every exercise.
  TextColumn get mechanic => text().nullable()();

  /// Whether the exercise trains one side at a time (e.g. single-arm row).
  BoolColumn get isUnilateral => boolean().withDefault(const Constant(false))();

  /// Whether this is a bodyweight movement (affects default weight = 0).
  BoolColumn get isBodyweight => boolean().withDefault(const Constant(false))();

  /// Whether sets are logged as a held duration (e.g. a plank) rather than
  /// repetitions. Drives the reps-vs-duration input in the set logger.
  BoolColumn get isTimeBased => boolean().withDefault(const Constant(false))();

  /// Seed version this row belongs to. Bumped when the seed file changes
  /// so the idempotent seeder can detect diffs.
  IntColumn get seedVersion => integer()();

  /// Whether this row was created locally (e.g. an unmatched name from a
  /// historical XLSX import) rather than shipped in the seed catalogue.
  /// Explicit rather than inferred from `seedVersion == 0`, since that was
  /// a de facto convention with no named meaning of its own.
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Broad exercise classification — stored as TEXT in the DB.
enum ExerciseCategory { strength, cardio, mobility, balance, plyometric, other }

extension ExerciseCategoryX on ExerciseCategory {
  String get label => switch (this) {
        ExerciseCategory.strength => 'Strength',
        ExerciseCategory.cardio => 'Cardio',
        ExerciseCategory.mobility => 'Mobility',
        ExerciseCategory.balance => 'Balance',
        ExerciseCategory.plyometric => 'Plyometric',
        ExerciseCategory.other => 'Other',
      };
}

/// Stored as TEXT in the DB.
enum Difficulty { beginner, intermediate, advanced }

extension DifficultyX on Difficulty {
  String get label => switch (this) {
        Difficulty.beginner => 'Beginner',
        Difficulty.intermediate => 'Intermediate',
        Difficulty.advanced => 'Advanced',
      };
}

/// Stored as TEXT in the DB.
enum ForceType { push, pull, isometric }

extension ForceTypeX on ForceType {
  String get label => switch (this) {
        ForceType.push => 'Push',
        ForceType.pull => 'Pull',
        ForceType.isometric => 'Isometric',
      };
}

/// Stored as TEXT in the DB.
enum Mechanic { compound, isolation }

extension MechanicX on Mechanic {
  String get label => switch (this) {
        Mechanic.compound => 'Compound',
        Mechanic.isolation => 'Isolation',
      };
}

/// Movement pattern enum — stored as TEXT in the DB.
enum MovementPattern {
  horizontalPush,
  verticalPush,
  horizontalPull,
  verticalPull,
  kneeDominant,
  hipDominant,
  carry,
  rotation,
  antiRotation,
  other,
}

extension MovementPatternX on MovementPattern {
  String get label => switch (this) {
        MovementPattern.horizontalPush => 'Horizontal Push',
        MovementPattern.verticalPush => 'Vertical Push',
        MovementPattern.horizontalPull => 'Horizontal Pull',
        MovementPattern.verticalPull => 'Vertical Pull',
        MovementPattern.kneeDominant => 'Knee Dominant',
        MovementPattern.hipDominant => 'Hip Dominant',
        MovementPattern.carry => 'Carry',
        MovementPattern.rotation => 'Rotation',
        MovementPattern.antiRotation => 'Anti-Rotation',
        MovementPattern.other => 'Other',
      };
}

/// Freezed model for the exercise row (scalar fields only — see
/// `ExerciseDetail` in the DAO layer for the fully assembled view).
@freezed
abstract class Exercise with _$Exercise {
  const factory Exercise({
    required String id,
    required String slug,
    required String name,
    required String description,
    required ExerciseCategory category,
    required Difficulty difficulty,
    required MovementPattern movementPattern,
    ForceType? forceType,
    Mechanic? mechanic,
    required bool isUnilateral,
    required bool isBodyweight,
    required bool isTimeBased,
    required int seedVersion,
    required bool isCustom,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Exercise;

  factory Exercise.fromDrift(ExercisesTableData row) => Exercise(
        id: row.id,
        slug: row.slug,
        name: row.name,
        description: row.description,
        category: ExerciseCategory.values.byName(row.category),
        difficulty: Difficulty.values.byName(row.difficulty),
        movementPattern: MovementPattern.values.byName(row.movementPattern),
        forceType: row.forceType == null
            ? null
            : ForceType.values.byName(row.forceType!),
        mechanic:
            row.mechanic == null ? null : Mechanic.values.byName(row.mechanic!),
        isUnilateral: row.isUnilateral,
        isBodyweight: row.isBodyweight,
        isTimeBased: row.isTimeBased,
        seedVersion: row.seedVersion,
        isCustom: row.isCustom,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
}
