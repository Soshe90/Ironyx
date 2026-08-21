import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';

part 'muscles.freezed.dart';

/// Muscle table — canonical muscle taxonomy.
///
/// Replaces the old `MuscleGroup` enum-on-exercise approach so exercises
/// can be queried relationally ("exercises that train lats"). Supports a
/// hierarchy via [MusclesTable.parentId], though the seeded taxonomy
/// starts flat (one row per former `MuscleGroup` value) — inventing a
/// parent structure isn't something to fabricate without real curation.
class MusclesTable extends Table {
  /// Stable slug, e.g. "lats". Never reused.
  TextColumn get id => text()();

  /// Canonical key. Matches [id] today but kept distinct for future
  /// aliasing without a migration.
  TextColumn get name => text()();

  /// Human-facing label, e.g. "Latissimus Dorsi".
  TextColumn get displayName => text()();

  /// Broad region grouping, e.g. "upper_body". Nullable — not curated yet.
  TextColumn get region => text().nullable()();

  /// Parent muscle in the hierarchy. Nullable — the initial seed is flat.
  TextColumn get parentId => text()
      .nullable()
      .references(MusclesTable, #id, onDelete: KeyAction.setNull)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Freezed model for a muscle row.
@freezed
abstract class Muscle with _$Muscle {
  const factory Muscle({
    required String id,
    required String name,
    required String displayName,
    String? region,
    String? parentId,
  }) = _Muscle;

  factory Muscle.fromDrift(MusclesTableData row) => Muscle(
        id: row.id,
        name: row.name,
        displayName: row.displayName,
        region: row.region,
        parentId: row.parentId,
      );
}
