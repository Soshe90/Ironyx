import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/body_metrics_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/services/clock.dart';
import 'package:ironyx/features/profile/domain/profile_controller.dart';

/// Saving Personal details logs the weight as a measurement for today.
///
/// "Today" is the user's day. It used to be taken from UTC, which is a
/// different day for part of every 24 hours in every zone but UTC itself:
/// the small hours east of it, the evening west of it. The two times below
/// are chosen so that one of them is on the other side of UTC midnight
/// wherever these tests run.
void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase.forTesting());
  tearDown(() => database.close());

  Future<ProviderContainer> containerAt(DateTime now) async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    // Autodispose: keep it alive across the awaits below.
    container.listen(profileControllerProvider, (_, __) {});
    await container.read(profileControllerProvider.future);
    return container;
  }

  Future<void> saveWeightAt(DateTime now, double weightKg) async {
    final ProviderContainer container = await containerAt(now);
    final ProfileController controller =
        container.read(profileControllerProvider.notifier);
    controller.setWeightKg(weightKg);
    await controller.save();
  }

  for (final (String label, DateTime now) in <(String, DateTime)>[
    ('just after midnight', DateTime(2026, 8, 22, 0, 30)),
    ('just before midnight', DateTime(2026, 8, 22, 23, 30)),
    ('at noon', DateTime(2026, 8, 22, 12)),
  ]) {
    test('a weight saved $label is logged for that local day', () async {
      await saveWeightAt(now, 94);

      final dao = BodyMetricsDao(database);
      final entry = await dao.getLatest();
      expect(entry!.date, DateTime(2026, 8, 22));
      expect(entry.weightKg, 94);
      expect(await dao.getByDate(DateTime(2026, 8, 21)), isNull);
      expect(await dao.getByDate(DateTime(2026, 8, 23)), isNull);
    });
  }

  test('saving twice on one day keeps a single entry with the later weight',
      () async {
    await saveWeightAt(DateTime(2026, 8, 22, 0, 30), 94);
    await saveWeightAt(DateTime(2026, 8, 22, 23, 30), 93.5);

    final rows = await database.select(database.bodyMetricsTable).get();
    expect(rows, hasLength(1));
    expect(rows.single.weightKg, 93.5);
  });

  test('saving on the next day adds a second entry', () async {
    await saveWeightAt(DateTime(2026, 8, 22, 23, 30), 94);
    await saveWeightAt(DateTime(2026, 8, 23, 0, 30), 93.5);

    final rows = await database.select(database.bodyMetricsTable).get();
    expect(rows, hasLength(2));
  });

  test('no weight, or a weight of zero, logs nothing', () async {
    final ProviderContainer container =
        await containerAt(DateTime(2026, 8, 22, 12));
    final ProfileController controller =
        container.read(profileControllerProvider.notifier);
    await controller.save();
    controller.setWeightKg(0);
    await controller.save();

    expect(await database.select(database.bodyMetricsTable).get(), isEmpty);
  });
}
