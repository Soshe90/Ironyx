import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';

part 'timer_sessions.freezed.dart';

/// TimerSession table — completed interval timer sessions.
///
/// ADR-4: timer is wall-clock based. The session stores absolute
/// start/end timestamps and the phase log.
class TimerSessionsTable extends Table {
  /// Stable UUID.
  TextColumn get id => text()();

  /// ISO-8601 UTC session start.
  DateTimeColumn get startedAt => dateTime()();

  /// ISO-8601 UTC session end. Null if cancelled/incomplete.
  DateTimeColumn get endedAt => dateTime().nullable()();

  /// Total planned duration in seconds (sum of all intervals).
  IntColumn get plannedDurationSeconds => integer()();

  /// Actual duration in seconds (endedAt - startedAt).
  IntColumn get actualDurationSeconds => integer().nullable()();

  /// Timer preset name (e.g., "Tabata", "EMOM 10", "Custom").
  TextColumn get presetName => text()();

  /// Number of intervals completed.
  IntColumn get intervalsCompleted =>
      integer().withDefault(const Constant(0))();

  /// Total intervals in the preset.
  IntColumn get totalIntervals => integer()();

  /// Optional note.
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// TimerInterval table — individual intervals within a session.
///
/// Each interval has a type (work/rest/prepare) and a duration.
class TimerIntervalsTable extends Table {
  /// Stable UUID.
  TextColumn get id => text()();

  /// Parent session.
  TextColumn get sessionId =>
      text().references(TimerSessionsTable, #id, onDelete: KeyAction.cascade)();

  /// Interval index within the session (0-based).
  IntColumn get intervalIndex => integer()();

  /// Type of interval.
  TextColumn get type => text()(); // 'work', 'rest', 'prepare', 'cooldown'

  /// Planned duration in seconds.
  IntColumn get plannedDurationSeconds => integer()();

  /// Actual duration in seconds. Null if the interval was skipped/cancelled.
  IntColumn get actualDurationSeconds => integer().nullable()();

  /// Whether this interval was completed.
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Freezed model for the timer session row.
@freezed
abstract class TimerSession with _$TimerSession {
  const factory TimerSession({
    required String id,
    required DateTime startedAt,
    DateTime? endedAt,
    required int plannedDurationSeconds,
    int? actualDurationSeconds,
    required String presetName,
    required int intervalsCompleted,
    required int totalIntervals,
    String? note,
  }) = _TimerSession;

  factory TimerSession.fromDrift(TimerSessionsTableData row) => TimerSession(
        id: row.id,
        startedAt: row.startedAt,
        endedAt: row.endedAt,
        plannedDurationSeconds: row.plannedDurationSeconds,
        actualDurationSeconds: row.actualDurationSeconds,
        presetName: row.presetName,
        intervalsCompleted: row.intervalsCompleted,
        totalIntervals: row.totalIntervals,
        note: row.note,
      );
}

/// Freezed model for the timer interval row.
@freezed
abstract class TimerInterval with _$TimerInterval {
  const factory TimerInterval({
    required String id,
    required String sessionId,
    required int intervalIndex,
    required TimerIntervalType type,
    required int plannedDurationSeconds,
    int? actualDurationSeconds,
    required bool isCompleted,
  }) = _TimerInterval;

  factory TimerInterval.fromDrift(TimerIntervalsTableData row) => TimerInterval(
        id: row.id,
        sessionId: row.sessionId,
        intervalIndex: row.intervalIndex,
        type: TimerIntervalType.values.byName(row.type),
        plannedDurationSeconds: row.plannedDurationSeconds,
        actualDurationSeconds: row.actualDurationSeconds,
        isCompleted: row.isCompleted,
      );
}

/// Timer interval type enum — stored as TEXT in the DB.
enum TimerIntervalType { work, rest, prepare, cooldown }

// The display names for these live on `TimerPhaseType` in the timer's own
// domain layer, which is the enum the UI and the notification scheduler both
// work with. This one is only ever written to and read from the database.
