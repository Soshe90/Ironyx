import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';

part 'workouts.freezed.dart';

/// Workout table — one row per completed session.
///
/// The draft (in-progress workout) lives in Riverpod state (ADR-5).
/// Only committed workouts reach this table.
class WorkoutsTable extends Table {
  /// Stable UUID.
  TextColumn get id => text()();

  /// ISO-8601 UTC start timestamp.
  DateTimeColumn get startedAt => dateTime()();

  /// ISO-8601 UTC end timestamp. Null until the workout is finished.
  DateTimeColumn get endedAt => dateTime().nullable()();

  /// Optional user note.
  TextColumn get note => text().nullable()();

  /// Total volume in kg (Σ weight_kg × reps) over completed, non-warmup sets.
  /// Computed on commit, stored for fast dashboard queries.
  RealColumn get totalVolumeKg => real().withDefault(const Constant(0.0))();

  /// Session duration in seconds (endedAt - startedAt).
  IntColumn get durationSeconds => integer().nullable()();

  /// Schema version of the workout format at commit time.
  /// Used by export/import migrations (ADR-7).
  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Freezed model for the workout row.
@freezed
abstract class Workout with _$Workout {
  const factory Workout({
    required String id,
    required DateTime startedAt,
    DateTime? endedAt,
    String? note,
    required double totalVolumeKg,
    int? durationSeconds,
    required int schemaVersion,
  }) = _Workout;

  factory Workout.fromDrift(WorkoutsTableData row) => Workout(
        id: row.id,
        startedAt: row.startedAt,
        endedAt: row.endedAt,
        note: row.note,
        totalVolumeKg: row.totalVolumeKg,
        durationSeconds: row.durationSeconds,
        schemaVersion: row.schemaVersion,
      );
}
