import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/body_metrics.dart';

part 'body_metrics_dao.g.dart';

@DriftAccessor(tables: [BodyMetricsTable])
class BodyMetricsDao extends DatabaseAccessor<AppDatabase>
    with _$BodyMetricsDaoMixin {
  BodyMetricsDao(super.db);

  /// Watch all body metrics, newest first.
  Stream<List<BodyMetrics>> watchAll({int? limit}) {
    final query = select(bodyMetricsTable)
      ..orderBy([(t) => OrderingTerm.desc(t.date)]);
    if (limit != null) query.limit(limit);
    return query.watch().map(
          (rows) => rows.map<BodyMetrics>(BodyMetrics.fromDrift).toList(),
        );
  }

  /// Get a single entry by date.
  Future<BodyMetrics?> getByDate(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    return (select(bodyMetricsTable)..where((t) => t.date.equals(dateOnly)))
        .getSingleOrNull()
        .then((row) => row == null ? null : BodyMetrics.fromDrift(row));
  }

  /// Watch entries in a date range (for charts).
  Stream<List<BodyMetrics>> watchInRange(DateTime start, DateTime end) =>
      (select(bodyMetricsTable)
            ..where((t) => t.date.isBetweenValues(start, end))
            ..orderBy([(t) => OrderingTerm.asc(t.date)]))
          .watch()
          .map((rows) => rows.map<BodyMetrics>(BodyMetrics.fromDrift).toList());

  /// Insert or update a body metrics entry (upsert by date).
  Future<void> upsert(BodyMetricsTableCompanion entry) =>
      into(bodyMetricsTable).insertOnConflictUpdate(entry);

  /// Delete an entry by date.
  Future<void> deleteByDate(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    return (delete(
      bodyMetricsTable,
    )..where((t) => t.date.equals(dateOnly)))
        .go();
  }

  /// Latest weight entry.
  Stream<BodyMetrics?> watchLatest() => (select(bodyMetricsTable)
        ..orderBy([(t) => OrderingTerm.desc(t.date)])
        ..limit(1))
      .watchSingleOrNull()
      .map((row) => row == null ? null : BodyMetrics.fromDrift(row));
}
