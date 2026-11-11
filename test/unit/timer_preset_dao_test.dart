import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/timer_preset_dao.dart';
import 'package:ironyx/core/database/tables/timer_presets.dart';
import 'package:ironyx/features/timer/domain/timer_preset.dart';

void main() {
  late AppDatabase database;
  late TimerPresetDao dao;

  setUp(() {
    database = AppDatabase.forTesting();
    dao = TimerPresetDao(database);
  });

  tearDown(() => database.close());

  test('saves and restores every phase in a custom preset', () async {
    final preset = TimerPresets.custom(
      workSeconds: 40,
      restSeconds: 20,
      rounds: 3,
      warmupSeconds: 60,
      cooldownSeconds: 30,
    );

    final id = await dao.save(preset);
    final saved = await dao.getAll();

    expect(id, isNot('custom'));
    expect(saved, hasLength(1));
    expect(saved.single.id, id);
    expect(saved.single.name, 'Custom');
    expect(saved.single.phases, preset.phases);
    expect(saved.single.totalDurationSeconds, preset.totalDurationSeconds);
  });

  test('saving the same id updates the preset', () async {
    const first = TimerPreset(
      id: 'preset-1',
      name: 'Morning',
      description: 'old',
      phases: [
        TimerPhase(type: TimerPhaseType.work, durationSeconds: 10),
      ],
    );
    final second = first.copyWith(
      description: 'updated',
      phases: [
        const TimerPhase(type: TimerPhaseType.rest, durationSeconds: 20),
      ],
    );

    await dao.save(first);
    await dao.save(second);
    final saved = await dao.getAll();

    expect(saved, hasLength(1));
    expect(saved.single.description, 'updated');
    expect(saved.single.phases.single.type, TimerPhaseType.rest);
  });

  test('deletes a saved preset', () async {
    final id = await dao.save(TimerPresets.custom(
      workSeconds: 10,
      restSeconds: 5,
      rounds: 1,
    ));

    await dao.remove(id);

    expect(await dao.getAll(), isEmpty);
  });

  test('take removes a preset, and restore puts it back in its place',
      () async {
    // Saved a day apart; the database keeps creation times to the second.
    for (final (String id, String name, int day) in <(String, String, int)>[
      ('first', 'A', 1),
      ('second', 'B', 2),
    ]) {
      await dao.restore(
        TimerPresetsTableData(
          id: id,
          name: name,
          description: '',
          phasesJson: encodeTimerPhases(TimerPresets.tabata().phases),
          createdAt: DateTime.utc(2026, 1, day),
        ),
      );
    }

    final row = await dao.take('first');
    expect(row, isNotNull);
    expect((await dao.getAll()).map((p) => p.id), <String>['second']);
    expect(await dao.take('first'), isNull, reason: 'already gone');

    await dao.restore(row!);
    // Back first, by its own creation time, not at the end.
    expect((await dao.getAll()).map((p) => p.id), <String>['first', 'second']);
    expect((await dao.getAll()).first.name, 'A');
  });
}
