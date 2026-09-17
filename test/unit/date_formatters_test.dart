import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ironyx/core/formatters/date_formatters.dart';
import 'package:ironyx/l10n/app_localizations_ar.dart';
import 'package:ironyx/l10n/app_localizations_en.dart';

void main() {
  // The display formatters are locale-bound now, so the English ones are
  // built once here rather than reached through a widget tree.
  //
  // `initializeDateFormatting` first: `DateFormat` throws when handed a
  // locale whose symbols have not been loaded. The app never has to do this
  // because `GlobalMaterialLocalizations` loads them for the active locale
  // before the first frame, but a bare unit test has no such delegate.
  late final DateFormatters dates;

  setUpAll(() async {
    await initializeDateFormatting('en');
    dates = DateFormatters.forLocalizations(AppLocalizationsEn());
  });

  group('DateFormatters', () {
    group('relativeDay', () {
      // Use a fixed reference time to avoid flakiness
      final now = DateTime(2024, 1, 15, 12, 0, 0); // Monday noon

      test('returns "Today" for same day', () {
        final today = DateTime(2024, 1, 15, 8, 0);
        expect(dates.relativeDay(today, now: now), 'Today');

        // Late at night still today
        final lateNight = DateTime(2024, 1, 15, 23, 55);
        expect(dates.relativeDay(lateNight, now: now), 'Today');
      });

      test('returns "Yesterday" for previous day', () {
        final yesterday = DateTime(2024, 1, 14, 8, 0);
        expect(dates.relativeDay(yesterday, now: now), 'Yesterday');

        // Edge case: 23:55 yesterday -> 00:05 today should be "Yesterday"
        // because the date changed but it's only 10 minutes ago
        final lateYesterday = DateTime(2024, 1, 14, 23, 55);
        expect(
          dates.relativeDay(lateYesterday, now: now),
          'Yesterday',
        );
      });

      test('returns weekday name for 2-6 days ago', () {
        final tuesday = DateTime(2024, 1, 9); // 6 days ago
        expect(dates.relativeDay(tuesday, now: now), 'Tuesday');

        final wednesday = DateTime(2024, 1, 10); // 5 days ago
        expect(dates.relativeDay(wednesday, now: now), 'Wednesday');

        final thursday = DateTime(2024, 1, 11); // 4 days ago
        expect(dates.relativeDay(thursday, now: now), 'Thursday');

        final friday = DateTime(2024, 1, 12); // 3 days ago
        expect(dates.relativeDay(friday, now: now), 'Friday');

        final saturday = DateTime(2024, 1, 13); // 2 days ago
        expect(dates.relativeDay(saturday, now: now), 'Saturday');

        final sunday = DateTime(2024, 1, 14); // 1 day ago = Yesterday
        expect(dates.relativeDay(sunday, now: now), 'Yesterday');
      });

      test('returns "d MMM" for older dates in same year', () {
        final older = DateTime(2024, 1, 1); // 14 days ago
        expect(dates.relativeDay(older, now: now), '1 Jan');
      });

      test('returns "d MMM yyyy" for different year', () {
        final lastYear = DateTime(2023, 12, 31);
        expect(dates.relativeDay(lastYear, now: now), '31 Dec 2023');
      });
    });

    group('time', () {
      test('formats time correctly', () {
        expect(dates.time(DateTime(2024, 1, 15, 8, 5)), '8:05 AM');
        expect(dates.time(DateTime(2024, 1, 15, 13, 30)), '1:30 PM');
        expect(dates.time(DateTime(2024, 1, 15, 0, 0)), '12:00 AM');
        expect(dates.time(DateTime(2024, 1, 15, 12, 0)), '12:00 PM');
      });
    });

    group('full', () {
      test('formats full date', () {
        expect(dates.full(DateTime(2024, 1, 15)), '15 Jan 2024');
        expect(dates.full(DateTime(2024, 12, 25)), '25 Dec 2024');
      });
    });

    group('startOfWeek', () {
      test('returns Monday for any day of the week', () {
        // Monday
        expect(
          DateFormatters.startOfWeek(DateTime(2024, 1, 15)),
          DateTime(2024, 1, 15),
        );
        // Tuesday
        expect(
          DateFormatters.startOfWeek(DateTime(2024, 1, 16)),
          DateTime(2024, 1, 15),
        );
        // Wednesday
        expect(
          DateFormatters.startOfWeek(DateTime(2024, 1, 17)),
          DateTime(2024, 1, 15),
        );
        // Thursday
        expect(
          DateFormatters.startOfWeek(DateTime(2024, 1, 18)),
          DateTime(2024, 1, 15),
        );
        // Friday
        expect(
          DateFormatters.startOfWeek(DateTime(2024, 1, 19)),
          DateTime(2024, 1, 15),
        );
        // Saturday
        expect(
          DateFormatters.startOfWeek(DateTime(2024, 1, 20)),
          DateTime(2024, 1, 15),
        );
        // Sunday
        expect(
          DateFormatters.startOfWeek(DateTime(2024, 1, 21)),
          DateTime(2024, 1, 15),
        );
      });

      test('handles month/year boundaries', () {
        // Sunday Dec 31, 2023 -> Monday Dec 25, 2023
        expect(
          DateFormatters.startOfWeek(DateTime(2023, 12, 31)),
          DateTime(2023, 12, 25),
        );
        // Monday Jan 1, 2024 -> Monday Jan 1, 2024
        expect(
          DateFormatters.startOfWeek(DateTime(2024, 1, 1)),
          DateTime(2024, 1, 1),
        );
      });
    });
  });

  group('DateFormatters in Arabic', () {
    late final DateFormatters arabic;

    setUpAll(() async {
      await initializeDateFormatting('ar');
      arabic = DateFormatters.forLocalizations(AppLocalizationsAr());
    });

    test('uses Arabic month and weekday names', () {
      // 15 Jan 2024 was a Monday.
      expect(arabic.full(DateTime(2024, 1, 15)), contains('يناير'));
      expect(
        arabic.dayHeadline(DateTime(2024, 1, 15)),
        contains('الاثنين'),
      );
    });

    test('renders dates with Western digits', () {
      // `intl` emits Arabic-Indic digits for `ar` by default. Every other
      // number in the app is Western — `NumberFormat` already gives `1,234`
      // for this locale — so dates are normalised to match.
      const String arabicIndic = '٠١٢٣٤٥٦٧٨٩';
      for (final String rendered in <String>[
        arabic.full(DateTime(2024, 1, 15)),
        arabic.time(DateTime(2024, 1, 15, 13, 30)),
        arabic.axisLabel(DateTime(2024, 1, 15)),
      ]) {
        expect(
          rendered.split('').any(arabicIndic.contains),
          isFalse,
          reason: rendered,
        );
      }
      // The day number survives as ASCII rather than being stripped.
      expect(arabic.full(DateTime(2024, 1, 15)), contains('15'));
      expect(arabic.time(DateTime(2024, 1, 15, 13, 30)), contains('1:30'));
    });

    test('translates Today and Yesterday', () {
      final DateTime now = DateTime(2024, 1, 15, 12);
      expect(arabic.relativeDay(now, now: now), 'اليوم');
      expect(
        arabic.relativeDay(DateTime(2024, 1, 14, 12), now: now),
        'أمس',
      );
    });
  });
}
