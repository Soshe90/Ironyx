import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';
import 'exercises.dart';

part 'exercise_sources.freezed.dart';

/// Provenance for a piece of an exercise's data — which external source
/// it came from, under what license, and what it was used for.
///
/// This exists so that months from now, if an exercise turns out to have
/// wrong information, there's a record of where it came from rather than
/// starting from scratch. It's also where license/attribution obligations
/// (e.g. wger's CC-BY-SA 3.0) get tracked per exercise.
class ExerciseSourcesTable extends Table {
  TextColumn get id => text()();

  TextColumn get exerciseId =>
      text().references(ExercisesTable, #id, onDelete: KeyAction.cascade)();

  /// e.g. "wger", "free-exercise-db", "liftmanual", "ironyx".
  TextColumn get sourceName => text()();

  TextColumn get sourceUrl => text().nullable()();

  /// The id/slug this exercise had *in the source system*, for cross-
  /// referencing on re-import.
  TextColumn get sourceExerciseId => text().nullable()();

  TextColumn get license => text().nullable()();
  TextColumn get attribution => text().nullable()();
  DateTimeColumn get retrievedAt => dateTime().nullable()();

  /// e.g. "seed", "verification", "image".
  TextColumn get usedFor => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Freezed model for a source/provenance row.
@freezed
abstract class ExerciseSource with _$ExerciseSource {
  const factory ExerciseSource({
    required String id,
    required String exerciseId,
    required String sourceName,
    String? sourceUrl,
    String? sourceExerciseId,
    String? license,
    String? attribution,
    DateTime? retrievedAt,
    String? usedFor,
  }) = _ExerciseSource;

  factory ExerciseSource.fromDrift(ExerciseSourcesTableData row) =>
      ExerciseSource(
        id: row.id,
        exerciseId: row.exerciseId,
        sourceName: row.sourceName,
        sourceUrl: row.sourceUrl,
        sourceExerciseId: row.sourceExerciseId,
        license: row.license,
        attribution: row.attribution,
        retrievedAt: row.retrievedAt,
        usedFor: row.usedFor,
      );
}
