import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../features/timer/domain/timer_preset.dart';
import '../app_database.dart';
import '../tables/timer_presets.dart';

part 'timer_preset_dao.g.dart';

/// Persistence boundary for user-created timer presets.
@DriftAccessor(tables: [TimerPresetsTable])
class TimerPresetDao extends DatabaseAccessor<AppDatabase>
    with _$TimerPresetDaoMixin {
  TimerPresetDao(super.db);

  Future<List<TimerPreset>> getAll() async => (await (select(timerPresetsTable)
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get())
      .map(_toDomain)
      .toList();

  TimerPreset _toDomain(TimerPresetsTableData row) => TimerPreset(
        id: row.id,
        name: row.name,
        description: row.description,
        phases: decodeTimerPhases(row.phasesJson),
      );

  Future<String> save(TimerPreset preset) async {
    final id = preset.id == 'custom' ? const Uuid().v4() : preset.id;
    await into(timerPresetsTable).insertOnConflictUpdate(
      TimerPresetsTableCompanion.insert(
        id: id,
        name: preset.name,
        description: preset.description,
        phasesJson: encodeTimerPhases(preset.phases),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    return id;
  }

  Future<void> remove(String id) =>
      (delete(timerPresetsTable)..where((t) => t.id.equals(id))).go();
}
