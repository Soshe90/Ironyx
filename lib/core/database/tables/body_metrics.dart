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

    /// The day measured, as local midnight of that calendar day. Its year,
    /// month and day are the day's in every time zone; see [fromDrift].
    required DateTime date,
    required double weightKg,
    double? bodyFatPercentage,
    double? leanMassKg,
    double? waistCm,
    String? note,
  }) = _BodyMetrics;

  /// The row's day is stored as UTC midnight, and drift hands that instant
  /// back as a local time. East of UTC that is a few hours into the right
  /// day. West of UTC it is the evening *before*: read as it came, the entry
  /// showed yesterday's date, and because the DAO finds a row by the year,
  /// month and day of the date it is given, saving an edit overwrote the
  /// previous day's entry and deleting removed it.
  ///
  /// So the calendar day is taken from the UTC value, where it was put, and
  /// carried as local midnight, which is what every reader (formatting,
  /// "today"/"yesterday", chart axes, the DAO's own lookups) expects of a
  /// local date.
  factory BodyMetrics.fromDrift(BodyMetricsTableData row) => BodyMetrics(
        id: row.id,
        date: _storedDay(row.date),
        weightKg: row.weightKg,
        bodyFatPercentage: row.bodyFatPercentage,
        leanMassKg: row.leanMassKg,
        waistCm: row.waistCm,
        note: row.note,
      );

  static DateTime _storedDay(DateTime stored) {
    final DateTime utc = stored.toUtc();
    return DateTime(utc.year, utc.month, utc.day);
  }
}
