import 'package:drift/drift.dart' show OrderingTerm;
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

    // What is on disk is UTC midnight of the day logged. The model carries
    // that day as a local date, so the stored instant is read from the row.
    final stored = await db.select(db.bodyMetricsTable).getSingle();
    expect(stored.date.toUtc(), DateTime.utc(2026, 8, 22));
    expect(entry, isNotNull);
    expect(entry!.date, DateTime(2026, 8, 22));
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

  // A day is stored as UTC midnight and comes back from the database as a
  // local time. West of UTC that local time is the evening before. These
  // only tell the old code from the new when run in such a zone:
  //   TZ=PST8PDT flutter test test/unit/body_metrics_dao_test.dart
  group('a stored day survives the round trip in any time zone', () {
    Future<void> log(String id, DateTime day, double kg) => dao.upsert(
          BodyMetricsTableCompanion.insert(id: id, date: day, weightKg: kg),
        );

    Future<List<BodyMetricsTableData>> rows() => (db.select(db.bodyMetricsTable)
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .get();

    test('it reads back as the calendar day it was logged for', () async {
      await log('m1', DateTime(2026, 8, 22, 14, 37), 80);

      final entry = await dao.getByDate(DateTime(2026, 8, 22));

      expect(entry!.date, DateTime(2026, 8, 22));
      expect((await dao.getLatest())!.date, DateTime(2026, 8, 22));
      expect((await dao.watchAll().first).single.date, DateTime(2026, 8, 22));
    });

    test('saving an edit under the date read back updates that row', () async {
      await log('m1', DateTime(2026, 8, 22), 80);
      final entry = (await dao.getLatest())!;

      await log(entry.id, entry.date, 81);

      final stored = await rows();
      expect(stored, hasLength(1));
      expect(stored.single.id, 'm1');
      expect(stored.single.weightKg, 81);
      expect(stored.single.date.toUtc(), DateTime.utc(2026, 8, 22));
    });

    test('an edit never lands on the day before', () async {
      await log('m21', DateTime(2026, 8, 21), 79);
      await log('m22', DateTime(2026, 8, 22), 80);
      final entry = (await dao.getByDate(DateTime(2026, 8, 22)))!;

      await log(entry.id, entry.date, 81);

      final stored = await rows();
      expect(stored.map((r) => r.id), <String>['m21', 'm22']);
      expect(stored.map((r) => r.weightKg), <double>[79, 81]);
    });

    test('repeated edits do not walk the date backwards', () async {
      await log('m1', DateTime(2026, 8, 22), 80);
      for (int i = 0; i < 5; i++) {
        final entry = (await dao.getLatest())!;
        await log(entry.id, entry.date, 80.0 + i);
      }

      final stored = await rows();
      expect(stored, hasLength(1));
      expect(stored.single.date.toUtc(), DateTime.utc(2026, 8, 22));
    });

    test('deleting by the date read back removes that row and no other',
        () async {
      await log('m21', DateTime(2026, 8, 21), 79);
      await log('m22', DateTime(2026, 8, 22), 80);
      final entry = (await dao.getByDate(DateTime(2026, 8, 22)))!;

      await dao.deleteByDate(entry.date);

      expect((await rows()).map((r) => r.id), <String>['m21']);
    });

    test('a range bounded by days read back includes exactly those days',
        () async {
      await log('m20', DateTime(2026, 8, 20), 78);
      await log('m21', DateTime(2026, 8, 21), 79);
      await log('m22', DateTime(2026, 8, 22), 80);
      final from = (await dao.getByDate(DateTime(2026, 8, 21)))!.date;
      final to = (await dao.getByDate(DateTime(2026, 8, 22)))!.date;

      final inRange = await dao.watchInRange(from, to).first;
      final since = await dao.watchAll(since: from).first;

      expect(inRange.map((e) => e.id), <String>['m21', 'm22']);
      expect(since.map((e) => e.id), <String>['m22', 'm21']);
    });

    test('the first and last days of a year keep their year', () async {
      await log('a', DateTime(2026, 1, 1), 80);
      await log('b', DateTime(2026, 12, 31, 23, 59), 81);

      expect((await dao.getByDate(DateTime(2026, 1, 1)))!.date,
          DateTime(2026, 1, 1));
      expect((await dao.getByDate(DateTime(2026, 12, 31)))!.date,
          DateTime(2026, 12, 31));
    });
  });
}
