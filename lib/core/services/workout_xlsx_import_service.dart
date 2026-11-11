import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/daos/exercise_dao.dart';
import '../database/daos/workout_dao.dart';

import '../formatters/unit_formatters.dart';

const _uuid = Uuid();

/// Largest workbook the importer reads: 10 MB. A training log of years is
/// well under 1 MB; past this the file is not one, and reading it into
/// memory could exhaust it. The Workouts tab checks the size before it
/// reads the file, and [WorkoutXlsxImportService.parse] checks again.
///
/// Not a guard against a "zip bomb": an XLSX is a zip, and a small file
/// can unpack to far more. Checking the unpacked size needs the `archive`
/// package directly, which the owner chose not to add (TODO.md).
const int kMaxWorkoutXlsxBytes = 10 * 1024 * 1024;

/// The workbook is larger than [kMaxWorkoutXlsxBytes].
class WorkoutXlsxTooLargeException implements Exception {
  const WorkoutXlsxTooLargeException(this.bytes);

  final int bytes;

  @override
  String toString() =>
      'WorkoutXlsxTooLargeException: $bytes bytes (limit $kMaxWorkoutXlsxBytes)';
}

/// Imports the workbook layout used by the user's historical training log.
///
/// The workbook contains one sheet per training day and one dated workout
/// column group per session. Each group stores reps, weight, effort, rest and
/// notes. Only populated reps/weight rows become completed workout sets.
class WorkoutXlsxImportService {
  const WorkoutXlsxImportService();

  Future<WorkoutXlsxImportResult> parse(
    List<int> bytes,
    AppDatabase db, {
    required WeightUnit sourceUnit,
  }) async {
    if (bytes.length > kMaxWorkoutXlsxBytes) {
      throw WorkoutXlsxTooLargeException(bytes.length);
    }
    // Unzipping and walking the sheets is the slow part, and it ran on the
    // UI isolate: the app froze while a workbook was read. It runs in the
    // background now and hands back plain values; matching names against
    // the database stays here.
    final List<_RawSession> sessions = await compute(_readSessions, bytes);
    // Names and aliases: the workbooks use coaching names ("Flat Dumbbell
    // Press") for catalogue exercises ("Dumbbell Bench Press"). The aliases
    // live in the seed, where the builder checks no two exercises share one.
    final exercises = await ExerciseDao(db).exerciseIdsByLookupName();
    final workouts = <ImportedHistoricalWorkout>[];
    final unknown = <String>{};

    for (final _RawSession session in sessions) {
      final importedExercises = <ImportedHistoricalExercise>[];
      for (final _RawExercise raw in session.exercises) {
        final exerciseId = exercises[normalizeExerciseName(raw.name)];
        if (exerciseId == null) unknown.add(raw.name);
        importedExercises.add(
          ImportedHistoricalExercise(
            exerciseId: exerciseId,
            name: raw.name,
            sets: <ImportedHistoricalSet>[
              for (final _RawSet set in raw.sets)
                ImportedHistoricalSet(
                  reps: set.reps.round(),
                  weightKg: _toKg(set.weight ?? 0, sourceUnit),
                ),
            ],
          ),
        );
      }
      final populated = importedExercises
          .where((exercise) => exercise.sets.isNotEmpty)
          .toList();
      if (populated.isNotEmpty) {
        workouts.add(
          ImportedHistoricalWorkout(date: session.date, exercises: populated),
        );
      }
    }

    workouts.sort((a, b) => a.date.compareTo(b.date));

    final markedWorkouts = <ImportedHistoricalWorkout>[];
    for (final workout in workouts) {
      markedWorkouts.add(
        workout.copyWith(
          isDuplicate: await _isDuplicateOfExisting(db, workout),
        ),
      );
    }

    return WorkoutXlsxImportResult(
      workouts: markedWorkouts,
      unknownExercises: unknown.toList()..sort(),
      totalSets: markedWorkouts.fold(
        0,
        (sum, workout) =>
            sum + workout.exercises.fold(0, (s, e) => s + e.sets.length),
      ),
    );
  }

  /// A workout is a duplicate only if one already exists at the exact
  /// neutral timestamp [apply] gives historical imports for that date, with
  /// the same exercises in the same order and identical sets — i.e. this
  /// exact file (or an overlapping one) was already imported. A manually
  /// logged workout on the same calendar day has a different `startedAt`
  /// and is never flagged.
  ///
  /// There can be several workouts at that timestamp: two sessions with one
  /// date in the workbook, or a re-import of an edited file, whose changed
  /// session is not a duplicate and is added beside the old one. This read
  /// them with `getSingleOrNull`, which throws on two, so from then on every
  /// import of the file failed as "could not read". Each is compared now.
  Future<bool> _isDuplicateOfExisting(
    AppDatabase db,
    ImportedHistoricalWorkout workout,
  ) async {
    final candidateStartedAt = DateTime.utc(
      workout.date.year,
      workout.date.month,
      workout.date.day,
      12,
    );
    final List<WorkoutsTableData> existing = await (db.select(db.workoutsTable)
          ..where((t) => t.startedAt.equals(candidateStartedAt)))
        .get();
    for (final WorkoutsTableData existingWorkout in existing) {
      if (await _sameContent(db, existingWorkout, workout)) return true;
    }
    return false;
  }

  /// Whether [existingWorkout] holds exactly [workout]'s exercises, in
  /// order, with identical sets.
  Future<bool> _sameContent(
    AppDatabase db,
    WorkoutsTableData existingWorkout,
    ImportedHistoricalWorkout workout,
  ) async {
    final existingExercises = await (db.select(db.workoutExercisesTable)
          ..where((t) => t.workoutId.equals(existingWorkout.id))
          ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
        .get();
    if (existingExercises.length != workout.exercises.length) return false;

    for (var i = 0; i < existingExercises.length; i++) {
      final existingExercise = existingExercises[i];
      final importedExercise = workout.exercises[i];
      final resolvedExerciseId = importedExercise.exerciseId;
      if (resolvedExerciseId == null ||
          existingExercise.exerciseId != resolvedExerciseId) {
        return false;
      }

      final existingSets = await (db.select(db.workoutSetsTable)
            ..where((t) => t.workoutExerciseId.equals(existingExercise.id))
            ..orderBy([(t) => OrderingTerm.asc(t.setIndex)]))
          .get();
      if (existingSets.length != importedExercise.sets.length) return false;
      for (var j = 0; j < existingSets.length; j++) {
        final existingSet = existingSets[j];
        final importedSet = importedExercise.sets[j];
        if (existingSet.reps != importedSet.reps ||
            existingSet.weightKg != importedSet.weightKg) {
          return false;
        }
      }
    }
    return true;
  }

  /// Writes all imported sessions. Historical sessions receive a neutral
  /// one-hour duration because the workbook contains no session timestamps.
  Future<void> apply(AppDatabase db, WorkoutXlsxImportResult result) {
    final workoutsToApply =
        result.workouts.where((w) => !w.isDuplicate).toList();
    return db.transaction(() async {
      final dao = WorkoutDao(db);
      final customExerciseIds = <String, String>{};
      for (final imported in workoutsToApply) {
        for (final exercise in imported.exercises) {
          if (exercise.exerciseId != null ||
              customExerciseIds.containsKey(exercise.name)) {
            continue;
          }
          final id = _uuid.v4();
          // Only `[a-z0-9]` survives into the slug, so a non-Latin name
          // (e.g. Arabic) leaves nothing — the id suffix still keeps the
          // slug unique, but `-imported-a1b2c3d4` with no prefix reads as a
          // display bug rather than a name that just doesn't romanize.
          final String normalizedName = exercise.name
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
              .trim();
          final String slugPrefix =
              normalizedName.isEmpty ? 'exercise' : normalizedName;
          await db.into(db.exercisesTable).insert(
                ExercisesTableCompanion.insert(
                  id: id,
                  slug: '$slugPrefix-imported-${id.substring(0, 8)}',
                  name: exercise.name,
                  category: 'other',
                  difficulty: 'intermediate',
                  movementPattern: 'other',
                  isBodyweight: const Value(false),
                  seedVersion: 0,
                  isCustom: const Value(true),
                ),
              );
          customExerciseIds[exercise.name] = id;
        }
      }
      for (final imported in workoutsToApply) {
        final startedAt = DateTime.utc(
          imported.date.year,
          imported.date.month,
          imported.date.day,
          12,
        );
        final endedAt = startedAt.add(const Duration(hours: 1));
        final workoutId = _uuid.v4();
        final exercises = <WorkoutExercisesTableCompanion>[];
        final sets = <WorkoutSetsTableCompanion>[];
        var volumeKg = 0.0;

        for (var exerciseIndex = 0;
            exerciseIndex < imported.exercises.length;
            exerciseIndex++) {
          final exercise = imported.exercises[exerciseIndex];
          final exerciseId =
              exercise.exerciseId ?? customExerciseIds[exercise.name]!;
          final workoutExerciseId = _uuid.v4();
          exercises.add(
            WorkoutExercisesTableCompanion.insert(
              id: workoutExerciseId,
              workoutId: workoutId,
              exerciseId: exerciseId,
              orderIndex: exerciseIndex,
            ),
          );
          for (var setIndex = 0; setIndex < exercise.sets.length; setIndex++) {
            final importedSet = exercise.sets[setIndex];
            sets.add(
              WorkoutSetsTableCompanion.insert(
                id: _uuid.v4(),
                workoutExerciseId: workoutExerciseId,
                setIndex: setIndex,
                weightKg: importedSet.weightKg,
                reps: importedSet.reps,
                isCompleted: const Value(true),
              ),
            );
            volumeKg += importedSet.weightKg * importedSet.reps;
          }
        }

        await dao.insertWorkout(
          WorkoutsTableCompanion.insert(
            id: workoutId,
            startedAt: startedAt,
            endedAt: Value(endedAt),
            note: const Value('Imported from XLSX workout log'),
            totalVolumeKg: Value(volumeKg),
            durationSeconds: const Value(3600),
          ),
          exercises,
          sets,
        );
      }
    });
  }

  static const List<int> _workoutGroupColumns = [3, 8, 13, 18, 23, 28, 33, 38];

  static Data? _rowCell(List<Data?>? row, int column) {
    if (row == null || column >= row.length) return null;
    return row[column];
  }

  static String? _exerciseName(List<Data?>? row) {
    if (row == null) return null;
    final candidates = [
      _text(row.isNotEmpty ? row[0] : null),
      _text(row.length > 2 ? row[2] : null),
    ];
    for (final candidate in candidates) {
      if (candidate == null || candidate.isEmpty) continue;
      if (candidate == 'See Tutorial Video' ||
          candidate.startsWith('Set ') ||
          candidate.startsWith('SUPERSET') ||
          RegExp(r'^[A-Z]\d+$').hasMatch(candidate)) {
        continue;
      }
      if (_effortLabels.contains(candidate)) continue;
      return candidate;
    }
    return null;
  }

  static double? _number(Data? data) {
    final value = data?.value;
    return switch (value) {
      IntCellValue(:final value) => value.toDouble(),
      DoubleCellValue(:final value) => value,
      _ => double.tryParse(_text(data) ?? ''),
    };
  }

  static DateTime? _dateValue(Data? data) {
    final value = data?.value;
    if (value is DateCellValue) return value.asDateTimeUtc();
    final serial = _number(data);
    if (serial == null || serial < 1) return null;
    return DateTime.utc(1899, 12, 30).add(Duration(days: serial.floor()));
  }

  static String? _text(Data? data) {
    final value = data?.value;
    return switch (value) {
      TextCellValue(:final value) => value.text,
      null => null,
      _ => value.toString(),
    };
  }

  static double _toKg(double value, WeightUnit sourceUnit) =>
      sourceUnit == WeightUnit.lb ? value * 0.45359237 : value;

  static const Set<String> _effortLabels = {
    'Easy - I could have done 3 more reps',
    'Medium - I could have done 2 more reps',
    'Hard - I could have done 1 more rep',
    'Max effort - I could not have done any more reps',
    "Failed - I tried to do another rep but couldn't",
  };
}

/// One dated session as read from the workbook, before any database
/// lookup: plain values, so it can come back from the background isolate.
class _RawSession {
  const _RawSession(this.date, this.exercises);

  final DateTime date;

  /// Every exercise heading under the date, in order, including ones with
  /// no sets: their names still count as unknown when nothing matches.
  final List<_RawExercise> exercises;
}

class _RawExercise {
  _RawExercise(this.name);

  final String name;
  final List<_RawSet> sets = <_RawSet>[];
}

class _RawSet {
  const _RawSet(this.reps, this.weight);

  final double reps;
  final double? weight;
}

/// Unzips the workbook and walks its sheets: run through `compute`, off
/// the UI isolate. The rules are the ones [WorkoutXlsxImportService.parse]
/// had inline.
List<_RawSession> _readSessions(List<int> bytes) {
  final excel = Excel.decodeBytes(bytes);
  final sessions = <_RawSession>[];
  for (final sheet in excel.tables.values) {
    final rows = sheet.rows;
    // A blank or near-empty sheet (common as a trailing tab in a real
    // workbook) has no header row group to read a date from. Row 0 is that
    // header, rows from index 2 on are data — fewer than that and there is
    // nothing here to import, not a malformed file.
    if (rows.length < 3) continue;
    for (final groupStart in WorkoutXlsxImportService._workoutGroupColumns) {
      final date = WorkoutXlsxImportService._dateValue(
        WorkoutXlsxImportService._rowCell(rows[0], groupStart),
      );
      if (date == null) continue;

      _RawExercise? current;
      final exercises = <_RawExercise>[];
      for (var rowIndex = 2; rowIndex < rows.length; rowIndex++) {
        final row = rows[rowIndex];
        final candidate = WorkoutXlsxImportService._exerciseName(row);
        final reps = WorkoutXlsxImportService._number(
          WorkoutXlsxImportService._rowCell(row, groupStart),
        );
        final weight = WorkoutXlsxImportService._number(
          WorkoutXlsxImportService._rowCell(row, groupStart + 1),
        );

        if (candidate != null && reps == null && weight == null) {
          current = _RawExercise(candidate);
          exercises.add(current);
          continue;
        }
        if (current == null || reps == null || reps <= 0) continue;
        current.sets.add(_RawSet(reps, weight));
      }
      sessions.add(_RawSession(date, exercises));
    }
  }
  return sessions;
}

class WorkoutXlsxImportResult {
  const WorkoutXlsxImportResult({
    required this.workouts,
    required this.unknownExercises,
    required this.totalSets,
  });

  final List<ImportedHistoricalWorkout> workouts;
  final List<String> unknownExercises;
  final int totalSets;

  /// Workouts that already exist in history and [apply] will skip.
  int get duplicateCount => workouts.where((w) => w.isDuplicate).length;
}

class ImportedHistoricalWorkout {
  ImportedHistoricalWorkout({
    required this.date,
    required this.exercises,
    this.isDuplicate = false,
  });

  final DateTime date;
  final List<ImportedHistoricalExercise> exercises;

  /// Whether an identical workout (same date, exercises, and sets) is
  /// already in local history — see [WorkoutXlsxImportService.parse].
  final bool isDuplicate;

  ImportedHistoricalWorkout copyWith({bool? isDuplicate}) =>
      ImportedHistoricalWorkout(
        date: date,
        exercises: exercises,
        isDuplicate: isDuplicate ?? this.isDuplicate,
      );
}

class ImportedHistoricalExercise {
  ImportedHistoricalExercise({
    required this.exerciseId,
    required this.name,
    required this.sets,
  });

  final String? exerciseId;
  final String name;
  final List<ImportedHistoricalSet> sets;
}

class ImportedHistoricalSet {
  const ImportedHistoricalSet({required this.reps, required this.weightKg});

  final int reps;
  final double weightKg;
}
