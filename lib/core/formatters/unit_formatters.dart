import 'package:intl/intl.dart';

import '../l10n/l10n_extension.dart';

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
  static final NumberFormat _rate = NumberFormat('#,##0.0');

  /// Editable representation of a number: no grouping separators, so the
  /// result can be parsed straight back out of a text field. `_weight`'s
  /// thousands separator would not survive a `double.tryParse` round trip.
  static String plain(double value) => _plain.format(value);

  /// Converts from stored kilograms into the display unit.
  static double fromKg(double kg, WeightUnit unit) => kg * unit.perKilogram;

  /// Converts a user-entered value back into kilograms for storage.
  static double toKg(double value, WeightUnit unit) => value / unit.perKilogram;

  static String weight(
    double kg,
    WeightUnit unit,
    AppLocalizations l10n, {
    bool withUnit = true,
  }) {
    final String n = _weight.format(fromKg(kg, unit));
    return withUnit ? _measure(n, unit, l10n) : n;
  }

  /// A derived, approximate weight — an estimated 1RM above all.
  ///
  /// Rounded to whole units on purpose: Epley is a rough model, so
  /// rendering "138.83 kg" claims a precision the number does not have.
  static String estimate(
    double kg,
    WeightUnit unit,
    AppLocalizations l10n, {
    bool withUnit = true,
  }) {
    final String n = _volume.format(fromKg(kg, unit));
    return withUnit ? _measure(n, unit, l10n) : n;
  }

  /// A rate of change in weight, e.g. an estimated 1RM's monthly trend.
  ///
  /// One decimal: a fitted slope is an estimate of an estimate, so
  /// "11.84 kg" overstates it, while whole units would flatten a real
  /// +0.4 kg/month into "0 kg".
  static String weightRate(double kg, WeightUnit unit, AppLocalizations l10n) =>
      _measure(_rate.format(fromKg(kg, unit)), unit, l10n);

  static String volume(
    double kg,
    WeightUnit unit,
    AppLocalizations l10n, {
    bool withUnit = true,
  }) {
    final String n = _volume.format(fromKg(kg, unit));
    return withUnit ? _measure(n, unit, l10n) : n;
  }

  /// One logged set, "60 kg × 8", held together as a single unit.
  ///
  /// The spaces are non-breaking so a wrapped line never strands "× 8" from
  /// its weight, and in a right-to-left locale the whole expression is one
  /// left-to-right isolate — otherwise the bidi algorithm reorders the
  /// numbers around the Latin unit and "60 kg × 8" renders as "60 8 × kg".
  static String setLine(
    double kg,
    int reps,
    WeightUnit unit,
    AppLocalizations l10n,
  ) {
    const String nbsp = '\u00A0';
    final String line =
        '${_weight.format(fromKg(kg, unit))}$nbsp${unit.label}$nbsp×$nbsp$reps';
    return _isolateForRtl(line, l10n);
  }

  /// "60 kg". Units stay Latin in every locale (see `unitCentimetres` in
  /// the ARB files), so inside right-to-left text the value is wrapped in a
  /// left-to-right isolate: without it, Arabic renders "0 kg" as "kg 0".
  /// Left-to-right locales get the plain string, byte for byte.
  static String _measure(String n, WeightUnit unit, AppLocalizations l10n) =>
      _isolateForRtl('$n ${unit.label}', l10n);

  static String _isolateForRtl(String text, AppLocalizations l10n) =>
      Bidi.isRtlLanguage(l10n.localeName) ? '\u2066$text\u2069' : text;

  /// `1:05:03` or `05:03`. Used by the timer and session durations.
  static String duration(Duration d) {
    final int hours = d.inHours;
    final String mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final String ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  /// Formats a live countdown by rounding up to the next whole second.
  ///
  /// A wall-clock timer can have 3.9 seconds remaining between ticks. Using
  /// [duration] would display `00:03` even though the user still has almost
  /// four seconds; rounding up keeps the countdown and its cue at 3, 2, 1.
  static String durationRoundedUp(Duration d) {
    final int seconds = d.isNegative ? 0 : (d.inMilliseconds + 999) ~/ 1000;
    return duration(Duration(seconds: seconds));
  }

  /// Whole seconds remaining in a live countdown, rounded up at sub-second
  /// boundaries. Negative durations are already complete.
  static int secondsRoundedUp(Duration d) =>
      d.isNegative ? 0 : (d.inMilliseconds + 999) ~/ 1000;

  /// Compact duration for summaries: `48m`, `1h 12m` (Arabic `48 د`,
  /// `1 س 12 د`). The abbreviations come from the ARB files; Latin `m`/`h`
  /// inside Arabic text read as untranslated, unlike the kg/lb units, which
  /// are deliberately Latin everywhere.
  static String durationShort(Duration d, AppLocalizations l10n) {
    final int hours = d.inHours;
    final int minutes = d.inMinutes % 60;
    if (hours == 0) {
      return l10n.durationShortMinutes(d.inMinutes);
    }
    return minutes == 0
        ? l10n.durationShortHours(hours)
        : l10n.durationShortHoursMinutes(hours, minutes);
  }
}
