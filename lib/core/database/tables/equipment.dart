import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';

part 'equipment.freezed.dart';

/// Equipment table — canonical equipment taxonomy.
///
/// Replaces the old `Equipment` enum-on-exercise approach with a real
/// table, joined via [ExerciseEquipmentTable], so equipment isn't limited
/// to a fixed, closed set baked into the app binary.
class EquipmentTable extends Table {
  /// Stable slug, e.g. "dumbbell". Never reused.
  TextColumn get id => text()();

  /// Human-facing label, e.g. "Dumbbell".
  TextColumn get name => text()();

  /// Broad grouping, e.g. "free_weight" / "machine" / "bodyweight" /
  /// "accessory". Nullable — not curated for every row.
  TextColumn get category => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Freezed model for an equipment row.
@freezed
abstract class Equipment with _$Equipment {
  const factory Equipment({
    required String id,
    required String name,
    String? category,
  }) = _Equipment;

  factory Equipment.fromDrift(EquipmentTableData row) => Equipment(
        id: row.id,
        name: row.name,
        category: row.category,
      );
}
