import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/timer_sessions.dart';

part 'timer_dao.g.dart';

@DriftAccessor(tables: [TimerSessionsTable, TimerIntervalsTable])
class TimerDao extends DatabaseAccessor<AppDatabase> with _$TimerDaoMixin {
  TimerDao(super.db);

  /// Watch all timer sessions, newest first.
  Stream<List<TimerSession>> watchAll({int? limit}) {
    final query = select(timerSessionsTable)
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
    if (limit != null) query.limit(limit);
    return query.watch().map(
          (rows) => rows.map<TimerSession>(TimerSession.fromDrift).toList(),
        );
  }

  /// Get a single session with intervals.
  Future<TimerSessionWithIntervals?> getWithIntervals(String sessionId) async {
    final session = await (select(
      timerSessionsTable,
    )..where((t) => t.id.equals(sessionId)))
        .getSingleOrNull();
    if (session == null) return null;

    final intervals = await (select(timerIntervalsTable)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.asc(t.intervalIndex)]))
        .get();

    return TimerSessionWithIntervals(
      session: TimerSession.fromDrift(session),
      intervals: intervals.map<TimerInterval>(TimerInterval.fromDrift).toList(),
    );
  }

  /// Insert a completed timer session with intervals in a transaction.
  Future<String> insertSession(
    TimerSessionsTableCompanion session,
    List<TimerIntervalsTableCompanion> intervals,
  ) {
    return transaction(() async {
      await into(timerSessionsTable).insert(session);
      await batch((b) => b.insertAll(timerIntervalsTable, intervals));
      return session.id.value;
    });
  }

  /// Watch sessions in a date range.
  Stream<List<TimerSession>> watchInRange(DateTime start, DateTime end) =>
      (select(timerSessionsTable)
            ..where((t) => t.startedAt.isBetweenValues(start, end))
            ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
          .watch()
          .map(
            (rows) => rows.map<TimerSession>(TimerSession.fromDrift).toList(),
          );
}

/// Timer session with nested intervals.
class TimerSessionWithIntervals {
  const TimerSessionWithIntervals({
    required this.session,
    required this.intervals,
  });

  final TimerSession session;
  final List<TimerInterval> intervals;
}
