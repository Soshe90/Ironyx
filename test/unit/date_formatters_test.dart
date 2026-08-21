import 'package:fittrack/core/formatters/date_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DateFormatters', () {
    group('relativeDay', () {
      // Use a fixed reference time to avoid flakiness
      final now = DateTime(2024, 1, 15, 12, 0, 0); // Monday noon

      test('returns "Today" for same day', () {
        final today = DateTime(2024, 1, 15, 8, 0);
        expect(DateFormatters.relativeDay(today, now: now), 'Today');

        // Late at night still today
        final lateNight = DateTime(2024, 1, 15, 23, 55);
        expect(DateFormatters.relativeDay(lateNight, now: now), 'Today');
      });

      test('returns "Yesterday" for previous day', () {
        final yesterday = DateTime(2024, 1, 14, 8, 0);
        expect(DateFormatters.relativeDay(yesterday, now: now), 'Yesterday');

        // Edge case: 23:55 yesterday -> 00:05 today should be "Yesterday"
        // because the date changed but it's only 10 minutes ago
        final lateYesterday = DateTime(2024, 1, 14, 23, 55);
        expect(
          DateFormatters.relativeDay(lateYesterday, now: now),
          'Yesterday',
        );
      });

      test('returns weekday name for 2-6 days ago', () {
        final tuesday = DateTime(2024, 1, 9); // 6 days ago
        expect(DateFormatters.relativeDay(tuesday, now: now), 'Tuesday');

        final wednesday = DateTime(2024, 1, 10); // 5 days ago
        expect(DateFormatters.relativeDay(wednesday, now: now), 'Wednesday');

        final thursday = DateTime(2024, 1, 11); // 4 days ago
        expect(DateFormatters.relativeDay(thursday, now: now), 'Thursday');

        final friday = DateTime(2024, 1, 12); // 3 days ago
        expect(DateFormatters.relativeDay(friday, now: now), 'Friday');

        final saturday = DateTime(2024, 1, 13); // 2 days ago
        expect(DateFormatters.relativeDay(saturday, now: now), 'Saturday');

        final sunday = DateTime(2024, 1, 14); // 1 day ago = Yesterday
        expect(DateFormatters.relativeDay(sunday, now: now), 'Yesterday');
      });

      test('returns "d MMM" for older dates in same year', () {
        final older = DateTime(2024, 1, 1); // 14 days ago
        expect(DateFormatters.relativeDay(older, now: now), '1 Jan');
      });

      test('returns "d MMM yyyy" for different year', () {
        final lastYear = DateTime(2023, 12, 31);
        expect(DateFormatters.relativeDay(lastYear, now: now), '31 Dec 2023');
      });
    });

    group('time', () {
      test('formats time correctly', () {
        expect(DateFormatters.time(DateTime(2024, 1, 15, 8, 5)), '8:05 AM');
        expect(DateFormatters.time(DateTime(2024, 1, 15, 13, 30)), '1:30 PM');
        expect(DateFormatters.time(DateTime(2024, 1, 15, 0, 0)), '12:00 AM');
        expect(DateFormatters.time(DateTime(2024, 1, 15, 12, 0)), '12:00 PM');
      });
    });

    group('full', () {
      test('formats full date', () {
        expect(DateFormatters.full(DateTime(2024, 1, 15)), '15 Jan 2024');
        expect(DateFormatters.full(DateTime(2024, 12, 25)), '25 Dec 2024');
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
}
