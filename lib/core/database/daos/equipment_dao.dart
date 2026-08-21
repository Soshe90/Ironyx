import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/equipment.dart';

part 'equipment_dao.g.dart';

@DriftAccessor(tables: [EquipmentTable])
class EquipmentDao extends DatabaseAccessor<AppDatabase>
    with _$EquipmentDaoMixin {
  EquipmentDao(super.db);

  Stream<List<Equipment>> watchAll() =>
      (select(equipmentTable)..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch()
          .map((rows) => rows.map<Equipment>(Equipment.fromDrift).toList());

  Future<Equipment?> getById(String id) =>
      (select(equipmentTable)..where((t) => t.id.equals(id)))
          .getSingleOrNull()
          .then((row) => row == null ? null : Equipment.fromDrift(row));

  /// Upserts by id — see `MuscleDao.upsertAll` for why this must be a real
  /// `UPDATE` rather than delete-then-insert.
  Future<void> upsertAll(List<EquipmentTableCompanion> equipment) =>
      batch((b) => b.insertAllOnConflictUpdate(equipmentTable, equipment));
}
