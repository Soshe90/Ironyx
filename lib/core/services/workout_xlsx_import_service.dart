import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/daos/workout_dao.dart';

import '../formatters/unit_formatters.dart';

const _uuid = Uuid();

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
    final excel = Excel.decodeBytes(bytes);
    final exercises = await _exerciseNameToId(db);
    final workouts = <ImportedHistoricalWorkout>[];
    final unknown = <String>{};

    for (final sheet in excel.tables.values) {
      final rows = sheet.rows;
      for (final groupStart in _workoutGroupColumns) {
        final date = _dateValue(_rowCell(rows[0], groupStart));
        if (date == null) continue;

        ImportedHistoricalExercise? currentExercise;
        final importedExercises = <ImportedHistoricalExercise>[];
        for (var rowIndex = 2; rowIndex < rows.length; rowIndex++) {
          final row = rows[rowIndex];
          final candidate = _exerciseName(row);
          final reps = _number(_rowCell(row, groupStart));
          final weight = _number(_rowCell(row, groupStart + 1));

          if (candidate != null && reps == null && weight == null) {
            final exerciseId = exercises[_normalize(candidate)] ??
                exercises[_historicalAliases[_normalize(candidate)]];
            if (exerciseId == null) unknown.add(candidate);
            currentExercise = ImportedHistoricalExercise(
              exerciseId: exerciseId,
              name: candidate,
              sets: [],
            );
            importedExercises.add(currentExercise);
            continue;
          }

          if (currentExercise == null || reps == null || reps <= 0) continue;
          currentExercise.sets.add(
            ImportedHistoricalSet(
              reps: reps.round(),
              weightKg: _toKg(weight ?? 0, sourceUnit),
            ),
          );
        }

        final populated = importedExercises
            .where((exercise) => exercise.sets.isNotEmpty)
            .toList();
        if (populated.isNotEmpty) {
          workouts.add(
            ImportedHistoricalWorkout(date: date, exercises: populated),
          );
        }
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
    final existingWorkout = await (db.select(db.workoutsTable)
          ..where((t) => t.startedAt.equals(candidateStartedAt)))
        .getSingleOrNull();
    if (existingWorkout == null) return false;

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
          await db.into(db.exercisesTable).insert(
                ExercisesTableCompanion.insert(
                  id: id,
                  slug:
                      '${_normalize(exercise.name)}-imported-${id.substring(0, 8)}',
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

  Future<Map<String, String>> _exerciseNameToId(AppDatabase db) async {
    final rows = await db
        .customSelect(
          'SELECT id, name FROM exercises_table',
        )
        .get();
    return {
      for (final row in rows)
        _normalize(row.read<String>('name')): row.read<String>('id'),
    };
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

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static double _toKg(double value, WeightUnit sourceUnit) =>
      sourceUnit == WeightUnit.lb ? value * 0.45359237 : value;

  /// The workbook uses coaching names while the catalogue uses canonical
  /// exercise names. These mappings are deliberately explicit rather than
  /// fuzzy, so an import can never silently choose the wrong movement.
  static const Map<String, String> _historicalAliases = {
    'banded push ups': 'push up',
    'barbell romanian deadlift': 'romanian deadlift',
    'bird dog': 'bird dog',
    'bulgarian split squat quad focus': 'bulgarian split squat',
    'chest supported machine row': 'seated cable row',
    'cross cable tricep extensions': 'tricep pushdown',
    'dumbbell lateral raise': 'lateral raise',
    'dumbbell spider curls': 'dumbbell curl',
    'flat dumbbell press': 'dumbbell bench press',
    'hyperextensions back hamstring': 'back extension',
    'lean in lateral raise': 'lateral raise',
    'leg press calf raise': 'calf raise',
    'low incline dumbbell press': 'dumbbell bench press',
    'lying leg curls': 'leg curl',
    'quad focused leg press': 'leg press',
    'rkc plank': 'plank',
    'seated cable row mid upper back': 'seated cable row',
    'seated leg extensions': 'leg extension',
    'seated weighted calf raise': 'seated calf raise',
    'standing barbell overhead press': 'overhead press',
    'standing face pulls': 'face pull',
    'standing mid chest cable fly': 'cable fly',
  };

  static const Set<String> _effortLabels = {
    'Easy - I could have done 3 more reps',
    'Medium - I could have done 2 more reps',
    'Hard - I could have done 1 more rep',
    'Max effort - I could not have done any more reps',
    "Failed - I tried to do another rep but couldn't",
  };
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
