import 'package:intl/intl.dart';

/// Weight unit for display only.
///
/// ADR-1: storage is always kilograms. Conversion happens here and nowhere
/// else. A pound value must never reach the database.
enum WeightUnit {
  kg('kg', 1),
  lb('lb', 2.2046226218);

  const WeightUnit(this.label, this.perKilogram);

  final String label;
  final double perKilogram;
}

abstract final class UnitFormatters {
  static final NumberFormat _weight = NumberFormat('#,##0.##');
  static final NumberFormat _volume = NumberFormat('#,##0');
  static final NumberFormat _plain = NumberFormat('0.##');

  /// Editable representation of a number: no grouping separators, so the
  /// result can be parsed straight back out of a text field. `_weight`'s
  /// thousands separator would not survive a `double.tryParse` round trip.
  static String plain(double value) => _plain.format(value);

  /// Converts from stored kilograms into the display unit.
  static double fromKg(double kg, WeightUnit unit) => kg * unit.perKilogram;

  /// Converts a user-entered value back into kilograms for storage.
  static double toKg(double value, WeightUnit unit) => value / unit.perKilogram;

  static String weight(double kg, WeightUnit unit, {bool withUnit = true}) {
    final String n = _weight.format(fromKg(kg, unit));
    return withUnit ? '$n ${unit.label}' : n;
  }

  /// A derived, approximate weight — an estimated 1RM above all.
  ///
  /// Rounded to whole units on purpose: Epley is a rough model, so
  /// rendering "138.83 kg" claims a precision the number does not have.
  static String estimate(double kg, WeightUnit unit, {bool withUnit = true}) {
    final String n = _volume.format(fromKg(kg, unit));
    return withUnit ? '$n ${unit.label}' : n;
  }

  static String volume(double kg, WeightUnit unit, {bool withUnit = true}) {
    final String n = _volume.format(fromKg(kg, unit));
    return withUnit ? '$n ${unit.label}' : n;
  }

  /// `1:05:03` or `05:03`. Used by the timer and session durations.
  static String duration(Duration d) {
    final int hours = d.inHours;
    final String mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final String ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  /// Compact duration for summaries: `48m`, `1h 12m`.
  static String durationShort(Duration d) {
    final int hours = d.inHours;
    final int minutes = d.inMinutes % 60;
    if (hours == 0) {
      return '${d.inMinutes}m';
    }
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }
}
