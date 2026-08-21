import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/equipment.dart';
import '../tables/exercise_aliases.dart';
import '../tables/exercise_equipment.dart';
import '../tables/exercise_instructions.dart';
import '../tables/exercise_media.dart';
import '../tables/exercise_muscles.dart';
import '../tables/exercise_sources.dart';
import '../tables/exercise_tags.dart';
import '../tables/exercises.dart';
import '../tables/muscles.dart';

part 'exercise_dao.g.dart';

@DriftAccessor(
  tables: [
    ExercisesTable,
    MusclesTable,
    EquipmentTable,
    ExerciseMusclesTable,
    ExerciseEquipmentTable,
    ExerciseInstructionsTable,
    ExerciseAliasesTable,
    ExerciseMediaTable,
    ExerciseTagsTable,
    ExerciseSourcesTable,
  ],
)
class ExerciseDao extends DatabaseAccessor<AppDatabase>
    with _$ExerciseDaoMixin {
  ExerciseDao(super.db);

  // ---- List/search/filter (returns a display-ready summary) ----

  /// All exercises, ordered by name, with their primary muscle joined in.
  Stream<List<ExerciseSummary>> watchAll() => _watchSummaries();

  /// Search exercises by name or alias (case-insensitive, partial match).
  Stream<List<ExerciseSummary>> searchByName(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return watchAll();

    final aliasMatch = existsQuery(
      select(exerciseAliasesTable)
        ..where(
          (a) =>
              a.exerciseId.equalsExp(exercisesTable.id) &
              a.alias.lower().like('%$normalized%'),
        ),
    );

    return _watchSummaries(
      exercisesTable.name.lower().like('%$normalized%') | aliasMatch,
    );
  }

  /// Filter exercises by muscle, equipment, and/or movement pattern.
  Stream<List<ExerciseSummary>> filterBy({
    String? muscleId,
    String? equipmentId,
    MovementPattern? pattern,
  }) {
    Expression<bool>? where;
    void and(Expression<bool> expr) {
      where = where == null ? expr : where! & expr;
    }

    if (muscleId != null) {
      and(
        existsQuery(
          select(exerciseMusclesTable)
            ..where(
              (em) =>
                  em.exerciseId.equalsExp(exercisesTable.id) &
                  em.muscleId.equals(muscleId),
            ),
        ),
      );
    }
    if (equipmentId != null) {
      and(
        existsQuery(
          select(exerciseEquipmentTable)
            ..where(
              (ee) =>
                  ee.exerciseId.equalsExp(exercisesTable.id) &
                  ee.equipmentId.equals(equipmentId),
            ),
        ),
      );
    }
    if (pattern != null) {
      and(exercisesTable.movementPattern.equals(pattern.name));
    }

    return _watchSummaries(where);
  }

  Stream<List<ExerciseSummary>> _watchSummaries([Expression<bool>? where]) {
    final query = select(exercisesTable).join([
      leftOuterJoin(
        exerciseMusclesTable,
        exerciseMusclesTable.exerciseId.equalsExp(exercisesTable.id) &
            exerciseMusclesTable.role.equals('primary'),
      ),
      leftOuterJoin(
        musclesTable,
        musclesTable.id.equalsExp(exerciseMusclesTable.muscleId),
      ),
    ])
      ..orderBy([OrderingTerm.asc(exercisesTable.name)]);
    if (where != null) {
      query.where(where);
    }
    return query.watch().asyncMap(_enrich);
  }

  /// Batches the per-exercise equipment names and picture (from media, if
  /// any) for a page of exercises in a small, fixed number of queries —
  /// not one query per card.
  Future<List<ExerciseSummary>> _enrich(List<TypedResult> rows) async {
    if (rows.isEmpty) return const [];

    final exercises = <Exercise>[];
    final primaryMuscles = <String, Muscle>{};
    for (final row in rows) {
      final exercise = Exercise.fromDrift(row.readTable(exercisesTable));
      exercises.add(exercise);
      final muscleRow = row.readTableOrNull(musclesTable);
      if (muscleRow != null) {
        primaryMuscles[exercise.id] = Muscle.fromDrift(muscleRow);
      }
    }

    final ids = exercises.map((e) => e.id).toList();

    final equipmentRows = await (select(exerciseEquipmentTable).join([
      innerJoin(
        equipmentTable,
        equipmentTable.id.equalsExp(exerciseEquipmentTable.equipmentId),
      ),
    ])
          ..where(exerciseEquipmentTable.exerciseId.isIn(ids)))
        .get();
    final equipmentByExercise = <String, List<String>>{};
    for (final row in equipmentRows) {
      final exerciseId = row.readTable(exerciseEquipmentTable).exerciseId;
      (equipmentByExercise[exerciseId] ??= []).add(
        row.readTable(equipmentTable).name,
      );
    }

    final mediaRows = await (select(exerciseMediaTable)
          ..where((t) => t.exerciseId.isIn(ids))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    final mediaByExercise = <String, List<ExerciseMedia>>{};
    for (final row in mediaRows) {
      (mediaByExercise[row.exerciseId] ??= [])
          .add(ExerciseMedia.fromDrift(row));
    }

    return [
      for (final exercise in exercises)
        ExerciseSummary(
          exercise: exercise,
          primaryMuscle: primaryMuscles[exercise.id],
          equipmentNames: equipmentByExercise[exercise.id] ?? const [],
          media: bestMedia(mediaByExercise[exercise.id] ?? const []),
          fallbackMedia: _videoMedia(mediaByExercise[exercise.id] ?? const []),
        ),
    ];
  }

  // ---- Single exercise, fully assembled ----

  Future<Exercise?> getById(String id) =>
      (select(exercisesTable)..where((t) => t.id.equals(id)))
          .getSingleOrNull()
          .then((row) => row == null ? null : Exercise.fromDrift(row));

  /// The full nested view for the detail sheet: muscles by role, equipment,
  /// ordered instructions, aliases, media, and tags.
  Future<ExerciseDetail?> getWithDetails(String exerciseId) async {
    final exercise = await getById(exerciseId);
    if (exercise == null) return null;

    final muscleRows = await (select(exerciseMusclesTable).join([
      innerJoin(musclesTable,
          musclesTable.id.equalsExp(exerciseMusclesTable.muscleId)),
    ])
          ..where(exerciseMusclesTable.exerciseId.equals(exerciseId)))
        .get();
    final muscles = [
      for (final row in muscleRows)
        (
          muscle: Muscle.fromDrift(row.readTable(musclesTable)),
          role: MuscleRole.values
              .byName(row.readTable(exerciseMusclesTable).role),
        ),
    ];

    final equipmentRows = await (select(exerciseEquipmentTable).join([
      innerJoin(
        equipmentTable,
        equipmentTable.id.equalsExp(exerciseEquipmentTable.equipmentId),
      ),
    ])
          ..where(exerciseEquipmentTable.exerciseId.equals(exerciseId)))
        .get();
    final equipmentList = [
      for (final row in equipmentRows)
        (
          equipment: Equipment.fromDrift(row.readTable(equipmentTable)),
          isRequired: row.readTable(exerciseEquipmentTable).isRequired,
        ),
    ];

    final instructions = await (select(exerciseInstructionsTable)
          ..where((t) => t.exerciseId.equals(exerciseId))
          ..orderBy([(t) => OrderingTerm.asc(t.stepNumber)]))
        .map(ExerciseInstruction.fromDrift)
        .get();

    final aliases = await (select(exerciseAliasesTable)
          ..where((t) => t.exerciseId.equals(exerciseId)))
        .map((row) => row.alias)
        .get();

    final media = await (select(exerciseMediaTable)
          ..where((t) => t.exerciseId.equals(exerciseId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .map(ExerciseMedia.fromDrift)
        .get();

    final tags = await (select(exerciseTagsTable)
          ..where((t) => t.exerciseId.equals(exerciseId)))
        .map((row) => row.tag)
        .get();

    return ExerciseDetail(
      exercise: exercise,
      muscles: muscles,
      equipment: equipmentList,
      instructions: instructions,
      aliases: aliases,
      media: media,
      tags: tags,
    );
  }

  // ---- Dashboard ----

  /// Total exercise count and the most recently added exercise's name, for
  /// the Library dashboard card. A single watched query so both numbers
  /// update together.
  Stream<LibrarySummary> watchLibrarySummary() {
    final query = select(exercisesTable)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch().map((rows) {
      if (rows.isEmpty) {
        return const LibrarySummary(count: 0, mostRecentName: null);
      }
      return LibrarySummary(
          count: rows.length, mostRecentName: rows.first.name);
    });
  }

  // ---- Seeding ----

  /// Upserts by id — a real `UPDATE` for an exercise a logged workout
  /// already references, never a delete-then-insert (SQLite's `INSERT OR
  /// REPLACE` *is* a delete-then-insert internally and would throw on the
  /// `RESTRICT` foreign key from `workout_exercises.exercise_id` — this
  /// bit a real reseed once already, see `exercise_reseed_test.dart`).
  Future<void> upsertExercises(List<ExercisesTableCompanion> exercises) =>
      batch((b) => b.insertAllOnConflictUpdate(exercisesTable, exercises));

  /// Delete exercises that fell out of the current seed version — but
  /// never one a logged workout still references.
  Future<void> deleteOrphanedSeed(int currentSeedVersion) => customStatement(
        'DELETE FROM exercises_table '
        'WHERE seed_version < ? '
        'AND id NOT IN (SELECT DISTINCT exercise_id FROM workout_exercises_table)',
        [currentSeedVersion],
      );

  /// Replaces all of an exercise's muscle links. Safe to delete-then-insert
  /// (unlike the exercises table itself) — nothing outside the exercise
  /// feature holds a foreign key into this table.
  Future<void> replaceMuscleLinks(
    String exerciseId,
    List<ExerciseMusclesTableCompanion> links,
  ) =>
      transaction(() async {
        await (delete(exerciseMusclesTable)
              ..where((t) => t.exerciseId.equals(exerciseId)))
            .go();
        await batch((b) => b.insertAll(exerciseMusclesTable, links));
      });

  Future<void> replaceEquipmentLinks(
    String exerciseId,
    List<ExerciseEquipmentTableCompanion> links,
  ) =>
      transaction(() async {
        await (delete(exerciseEquipmentTable)
              ..where((t) => t.exerciseId.equals(exerciseId)))
            .go();
        await batch((b) => b.insertAll(exerciseEquipmentTable, links));
      });

  Future<void> replaceInstructions(
    String exerciseId,
    List<ExerciseInstructionsTableCompanion> steps,
  ) =>
      transaction(() async {
        await (delete(exerciseInstructionsTable)
              ..where((t) => t.exerciseId.equals(exerciseId)))
            .go();
        await batch((b) => b.insertAll(exerciseInstructionsTable, steps));
      });

  Future<void> replaceAliases(
    String exerciseId,
    List<ExerciseAliasesTableCompanion> aliases,
  ) =>
      transaction(() async {
        await (delete(exerciseAliasesTable)
              ..where((t) => t.exerciseId.equals(exerciseId)))
            .go();
        await batch((b) => b.insertAll(exerciseAliasesTable, aliases));
      });

  Future<void> replaceMedia(
    String exerciseId,
    List<ExerciseMediaTableCompanion> media,
  ) =>
      transaction(() async {
        await (delete(exerciseMediaTable)
              ..where((t) => t.exerciseId.equals(exerciseId)))
            .go();
        await batch((b) => b.insertAll(exerciseMediaTable, media));
      });

  Future<void> replaceTags(
    String exerciseId,
    List<ExerciseTagsTableCompanion> tags,
  ) =>
      transaction(() async {
        await (delete(exerciseTagsTable)
              ..where((t) => t.exerciseId.equals(exerciseId)))
            .go();
        await batch((b) => b.insertAll(exerciseTagsTable, tags));
      });

  Future<void> replaceSources(
    String exerciseId,
    List<ExerciseSourcesTableCompanion> sources,
  ) =>
      transaction(() async {
        await (delete(exerciseSourcesTable)
              ..where((t) => t.exerciseId.equals(exerciseId)))
            .go();
        await batch((b) => b.insertAll(exerciseSourcesTable, sources));
      });
}

/// Picks the media item the UI should show as *the* picture: an image
/// wins over a video link (which still needs a YouTube-thumbnail lookup
/// to become a picture), falling back to whatever's first.
ExerciseMedia? bestMedia(List<ExerciseMedia> media) {
  for (final m in media) {
    if (m.type == ExerciseMediaType.image) return m;
  }
  for (final m in media) {
    if (m.type == ExerciseMediaType.video) return m;
  }
  return media.isEmpty ? null : media.first;
}

ExerciseMedia? _videoMedia(List<ExerciseMedia> media) {
  for (final m in media) {
    if (m.type == ExerciseMediaType.video) return m;
  }
  return null;
}

/// Exercise counts for the Library dashboard card.
class LibrarySummary {
  const LibrarySummary({required this.count, required this.mostRecentName});

  final int count;
  final String? mostRecentName;
}

/// Lightweight, display-ready exercise for list/grid views — assembled
/// from a handful of batched queries rather than one query per card.
class ExerciseSummary {
  const ExerciseSummary({
    required this.exercise,
    required this.primaryMuscle,
    required this.equipmentNames,
    required this.media,
    required this.fallbackMedia,
  });

  final Exercise exercise;
  final Muscle? primaryMuscle;
  final List<String> equipmentNames;

  /// First media item by `sortOrder`, if any.
  final ExerciseMedia? media;

  /// Video media used as a remote-thumbnail fallback if the primary image
  /// host rejects hotlinking or is unavailable.
  final ExerciseMedia? fallbackMedia;
}

/// The fully assembled view for the exercise detail sheet.
class ExerciseDetail {
  const ExerciseDetail({
    required this.exercise,
    required this.muscles,
    required this.equipment,
    required this.instructions,
    required this.aliases,
    required this.media,
    required this.tags,
  });

  final Exercise exercise;
  final List<({Muscle muscle, MuscleRole role})> muscles;
  final List<({Equipment equipment, bool isRequired})> equipment;
  final List<ExerciseInstruction> instructions;
  final List<String> aliases;
  final List<ExerciseMedia> media;
  final List<String> tags;
}
