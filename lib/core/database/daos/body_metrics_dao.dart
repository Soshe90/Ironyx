import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/body_metrics.dart';

part 'body_metrics_dao.g.dart';

@DriftAccessor(tables: [BodyMetricsTable])
class BodyMetricsDao extends DatabaseAccessor<AppDatabase>
    with _$BodyMetricsDaoMixin {
  BodyMetricsDao(super.db);

  /// Watch all body metrics, newest first.
  ///
  /// [since] applies the same lower bound the Progress page's range selector
  /// applies to every other series, normalized the way stored rows are so a
  /// local-time boundary cannot include or exclude the wrong day. Null means
  /// all-time.
  Stream<List<BodyMetrics>> watchAll({int? limit, DateTime? since}) {
    final query = select(bodyMetricsTable)
      ..orderBy([(t) => OrderingTerm.desc(t.date)]);
    if (since != null) {
      query.where((t) => t.date.isBiggerOrEqualValue(_dateOnlyUtc(since)));
    }
    if (limit != null) query.limit(limit);
    return query.watch().map(
          (rows) => rows.map<BodyMetrics>(BodyMetrics.fromDrift).toList(),
        );
  }

  /// Get a single entry by date.
  Future<BodyMetrics?> getByDate(DateTime date) {
    final dateOnly = _dateOnlyUtc(date);
    return (select(bodyMetricsTable)..where((t) => t.date.equals(dateOnly)))
        .getSingleOrNull()
        .then((row) => row == null ? null : BodyMetrics.fromDrift(row));
  }

  /// Watch entries in a date range (for charts). Bounds are normalized the
  /// same way stored rows are, so a caller passing a local-time boundary
  /// can't silently exclude or include the wrong day.
  Stream<List<BodyMetrics>> watchInRange(DateTime start, DateTime end) =>
      (select(bodyMetricsTable)
            ..where(
              (t) => t.date.isBetweenValues(
                _dateOnlyUtc(start),
                _dateOnlyUtc(end),
              ),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.date)]))
          .watch()
          .map((rows) => rows.map<BodyMetrics>(BodyMetrics.fromDrift).toList());

  /// Insert or update a body metrics entry (upsert by date).
  Future<void> upsert(BodyMetricsTableCompanion entry) async {
    final normalized = entry.date.present
        ? entry.copyWith(date: Value(_dateOnlyUtc(entry.date.value)))
        : entry;

    if (normalized.date.present) {
      final existing = await (select(bodyMetricsTable)
            ..where((t) => t.date.equals(normalized.date.value)))
          .getSingleOrNull();
      if (existing != null) {
        await into(bodyMetricsTable).insertOnConflictUpdate(
          normalized.copyWith(id: Value(existing.id)),
        );
        return;
      }
    }

    await into(bodyMetricsTable).insertOnConflictUpdate(normalized);
  }

  /// Delete an entry by date.
  Future<void> deleteByDate(DateTime date) {
    final dateOnly = _dateOnlyUtc(date);
    return (delete(
      bodyMetricsTable,
    )..where((t) => t.date.equals(dateOnly)))
        .go();
  }

  DateTime _dateOnlyUtc(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  /// Latest weight entry.
  Stream<BodyMetrics?> watchLatest() => (select(bodyMetricsTable)
        ..orderBy([(t) => OrderingTerm.desc(t.date)])
        ..limit(1))
      .watchSingleOrNull()
      .map((row) => row == null ? null : BodyMetrics.fromDrift(row));

  /// One-shot read of the latest weight entry.
  ///
  /// Prefer this over `watchLatest().first` for a single read: taking the
  /// first event of a query stream sets up and tears down a whole stream
  /// subscription for one value, and — the reason this exists — a drift
  /// query stream never emits under `testWidgets`' fake clock, so anything
  /// awaiting `.first` hangs forever in a widget test.
  Future<BodyMetrics?> getLatest() => (select(bodyMetricsTable)
        ..orderBy([(t) => OrderingTerm.desc(t.date)])
        ..limit(1))
      .getSingleOrNull()
      .then((row) => row == null ? null : BodyMetrics.fromDrift(row));
}
