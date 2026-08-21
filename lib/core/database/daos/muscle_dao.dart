import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/muscles.dart';

part 'muscle_dao.g.dart';

@DriftAccessor(tables: [MusclesTable])
class MuscleDao extends DatabaseAccessor<AppDatabase> with _$MuscleDaoMixin {
  MuscleDao(super.db);

  Stream<List<Muscle>> watchAll() =>
      (select(musclesTable)..orderBy([(t) => OrderingTerm.asc(t.displayName)]))
          .watch()
          .map((rows) => rows.map<Muscle>(Muscle.fromDrift).toList());

  Future<Muscle?> getById(String id) =>
      (select(musclesTable)..where((t) => t.id.equals(id)))
          .getSingleOrNull()
          .then((row) => row == null ? null : Muscle.fromDrift(row));

  /// Upserts by id — safe to call on every reseed even if a muscle is
  /// already referenced by `exercise_muscles` (a real `UPDATE`, not a
  /// delete-then-insert; see `ExerciseDao.upsertExercises` for why that
  /// distinction matters).
  Future<void> upsertAll(List<MusclesTableCompanion> muscles) =>
      batch((b) => b.insertAllOnConflictUpdate(musclesTable, muscles));
}
