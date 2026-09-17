import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/body_metrics_dao.dart';

void main() {
  late AppDatabase db;
  late BodyMetricsDao dao;

  setUp(() {
    db = AppDatabase.forTesting();
    dao = BodyMetricsDao(db);
  });

  tearDown(() => db.close());

  test('normalizes timestamps to UTC midnight and supports date lookup',
      () async {
    await dao.upsert(
      BodyMetricsTableCompanion.insert(
        id: 'measurement-1',
        date: DateTime(2026, 8, 22, 14, 37),
        weightKg: 80,
      ),
    );

    final entry = await dao.getByDate(DateTime(2026, 8, 22, 23, 59));

    expect(entry, isNotNull);
    expect(entry!.date.toUtc(), DateTime.utc(2026, 8, 22));
  });

  test('deletes an entry when given a timestamp on that day', () async {
    await dao.upsert(
      BodyMetricsTableCompanion.insert(
        id: 'measurement-1',
        date: DateTime(2026, 8, 22, 14, 37),
        weightKg: 80,
      ),
    );

    await dao.deleteByDate(DateTime(2026, 8, 22, 18, 5));

    expect(await dao.getByDate(DateTime(2026, 8, 22)), isNull);
  });

  test('upserts measurements by calendar day', () async {
    await dao.upsert(
      BodyMetricsTableCompanion.insert(
        id: 'measurement-1',
        date: DateTime(2026, 8, 22, 8),
        weightKg: 80,
      ),
    );
    await dao.upsert(
      BodyMetricsTableCompanion.insert(
        id: 'measurement-2',
        date: DateTime(2026, 8, 22, 19),
        weightKg: 81,
      ),
    );

    final entries = await dao.watchAll().first;

    expect(entries, hasLength(1));
    expect(entries.single.weightKg, 81);
  });
}
