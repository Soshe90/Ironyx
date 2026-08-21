import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../app_database.dart';

part 'body_metrics.freezed.dart';

/// BodyMetrics table — body weight and composition tracking.
///
/// Weight is stored in **kilograms** (ADR-1).
/// One entry per day per user (enforced by unique index on date).
class BodyMetricsTable extends Table {
  /// Stable UUID.
  TextColumn get id => text()();

  /// Date of the measurement (date only, UTC midnight).
  DateTimeColumn get date => dateTime()();

  /// Body weight in kilograms.
  RealColumn get weightKg => real()();

  /// Body fat percentage. Null if not measured.
  RealColumn get bodyFatPercentage => real().nullable()();

  /// Lean mass in kg. Null if not measured.
  RealColumn get leanMassKg => real().nullable()();

  /// Waist circumference in cm. Null if not measured.
  RealColumn get waistCm => real().nullable()();

  /// Optional note.
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        // One entry per day
        'UNIQUE (date)',
      ];
}

/// Freezed model for the body metrics row.
@freezed
abstract class BodyMetrics with _$BodyMetrics {
  const factory BodyMetrics({
    required String id,
    required DateTime date,
    required double weightKg,
    double? bodyFatPercentage,
    double? leanMassKg,
    double? waistCm,
    String? note,
  }) = _BodyMetrics;

  factory BodyMetrics.fromDrift(BodyMetricsTableData row) => BodyMetrics(
        id: row.id,
        date: row.date,
        weightKg: row.weightKg,
        bodyFatPercentage: row.bodyFatPercentage,
        leanMassKg: row.leanMassKg,
        waistCm: row.waistCm,
        note: row.note,
      );
}
