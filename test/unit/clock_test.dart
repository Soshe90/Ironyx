import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/services/clock.dart';

/// `LocalNow` replaced `DateTime.now()` reads in dashboard `build()`
/// methods, which went stale while the app sat in memory: on 2026-11-03 a
/// phone showed "Good evening" and Friday 30 October on a Tuesday morning.
void main() {
  group('DayPart.of', () {
    test('splits the day at 12:00 and 18:00', () {
      expect(DayPart.of(DateTime(2026, 11, 3)), DayPart.morning);
      expect(DayPart.of(DateTime(2026, 11, 3, 11, 59, 59)), DayPart.morning);
      expect(DayPart.of(DateTime(2026, 11, 3, 12)), DayPart.afternoon);
      expect(DayPart.of(DateTime(2026, 11, 3, 17, 59, 59)), DayPart.afternoon);
      expect(DayPart.of(DateTime(2026, 11, 3, 18)), DayPart.evening);
      expect(DayPart.of(DateTime(2026, 11, 3, 23, 59, 59)), DayPart.evening);
    });
  });

  group('DayPart.nextBoundaryAfter', () {
    test('morning -> noon', () {
      expect(
        DayPart.nextBoundaryAfter(DateTime(2026, 11, 3, 9, 30)),
        DateTime(2026, 11, 3, 12),
      );
    });

    test('exactly on a boundary -> the next one, never itself', () {
      expect(
        DayPart.nextBoundaryAfter(DateTime(2026, 11, 3, 12)),
        DateTime(2026, 11, 3, 18),
      );
      expect(
        DayPart.nextBoundaryAfter(DateTime(2026, 11, 3, 18)),
        DateTime(2026, 11, 4),
      );
      expect(
        DayPart.nextBoundaryAfter(DateTime(2026, 11, 3)),
        DateTime(2026, 11, 3, 12),
      );
    });

    test('evening -> next midnight, across month and year ends', () {
      expect(
        DayPart.nextBoundaryAfter(DateTime(2026, 10, 31, 23, 59)),
        DateTime(2026, 11, 1),
      );
      expect(
        DayPart.nextBoundaryAfter(DateTime(2026, 12, 31, 19)),
        DateTime(2027, 1, 1),
      );
      expect(
        DayPart.nextBoundaryAfter(DateTime(2028, 2, 28, 20)),
        DateTime(2028, 2, 29),
      );
    });

    test('is always strictly in the future', () {
      // A boundary at or before `time` would make LocalNow schedule a
      // zero-length timer and spin.
      DateTime t = DateTime(2026, 11, 1);
      for (int i = 0; i < 24 * 4 * 3; i++) {
        expect(DayPart.nextBoundaryAfter(t).isAfter(t), isTrue, reason: '$t');
        t = t.add(const Duration(minutes: 15));
      }
    });
  });

  group('LocalNow', () {
    late DateTime fakeNow;
    late ProviderContainer container;

    final List<ProviderContainer> live = <ProviderContainer>[];

    ProviderContainer makeContainer({bool autoDispose = true}) {
      final ProviderContainer c = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(() => fakeNow)],
      );
      if (autoDispose) live.add(c);
      return c;
    }

    /// `testWidgets` checks for pending timers at the end of the body,
    /// before any `tearDown` runs, and LocalNow always has its next
    /// boundary timer queued. Disposing here, inside the body, is what a
    /// real app does when its `ProviderScope` unmounts.
    void clockTest(String description, WidgetTesterCallback body) {
      testWidgets(description, (tester) async {
        try {
          await body(tester);
        } finally {
          for (final ProviderContainer c in live) {
            c.dispose();
          }
          live.clear();
        }
      });
    }

    clockTest('starts at the clock value', (tester) async {
      fakeNow = DateTime(2026, 10, 30, 19, 50);
      container = makeContainer();

      expect(container.read(localNowProvider), fakeNow);
      expect(container.read(todayProvider), DateTime(2026, 10, 30));
    });

    clockTest('a resume after the day changed refreshes now and today',
        (tester) async {
      fakeNow = DateTime(2026, 10, 30, 19, 50);
      container = makeContainer();
      final List<DateTime> days = <DateTime>[];
      container.listen<DateTime>(
        todayProvider,
        (_, next) => days.add(next),
        fireImmediately: true,
      );

      // The phone sat in the background from Friday evening to Tuesday.
      fakeNow = DateTime(2026, 11, 3, 11, 37);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      expect(container.read(localNowProvider), fakeNow);
      expect(DayPart.of(container.read(localNowProvider)), DayPart.morning);
      // Reading forces Riverpod to recompute the dependent provider now;
      // in the app its frame-driven scheduler does the same on the next
      // frame (covered end to end in dashboard_page_test.dart).
      expect(container.read(todayProvider), DateTime(2026, 11, 3));
      expect(days, <DateTime>[DateTime(2026, 10, 30), DateTime(2026, 11, 3)]);
    });

    clockTest('a refresh within the same day part notifies nobody',
        (tester) async {
      fakeNow = DateTime(2026, 11, 3, 9);
      container = makeContainer();
      int notifications = 0;
      container.listen<DateTime>(localNowProvider, (_, __) => notifications++);

      fakeNow = DateTime(2026, 11, 3, 11, 59);
      container.read(localNowProvider.notifier).refresh();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      expect(notifications, 0);
      expect(container.read(localNowProvider), DateTime(2026, 11, 3, 9));
    });

    clockTest('a day-part change notifies now but not today', (tester) async {
      fakeNow = DateTime(2026, 11, 3, 11);
      container = makeContainer();
      int nowChanges = 0;
      int dayChanges = 0;
      container.listen<DateTime>(localNowProvider, (_, __) => nowChanges++);
      container.listen<DateTime>(todayProvider, (_, __) => dayChanges++);

      fakeNow = DateTime(2026, 11, 3, 12, 0, 1);
      container.read(localNowProvider.notifier).refresh();
      // Force the recompute, so "today did not notify" is checked rather
      // than merely not yet scheduled.
      expect(container.read(todayProvider), DateTime(2026, 11, 3));

      expect(nowChanges, 1);
      expect(dayChanges, 0, reason: 'week queries must not re-run at noon');
    });

    clockTest('the boundary timer fires at noon without any resume',
        (tester) async {
      fakeNow = DateTime(2026, 11, 3, 11, 59);
      container = makeContainer();
      container.read(localNowProvider);

      // Just short of the boundary plus slack: still morning.
      fakeNow = DateTime(2026, 11, 3, 11, 59, 59);
      await tester.pump(const Duration(seconds: 59));
      expect(DayPart.of(container.read(localNowProvider)), DayPart.morning);

      fakeNow = DateTime(2026, 11, 3, 12, 0, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(DayPart.of(container.read(localNowProvider)), DayPart.afternoon);
    });

    clockTest('the boundary timer rolls the day over at midnight',
        (tester) async {
      fakeNow = DateTime(2026, 11, 2, 23, 59);
      container = makeContainer();
      container.read(localNowProvider);

      fakeNow = DateTime(2026, 11, 3, 0, 0, 1);
      await tester.pump(const Duration(minutes: 1, seconds: 2));

      expect(container.read(todayProvider), DateTime(2026, 11, 3));
    });

    clockTest(
        'an early timer (clock behind) reschedules instead of '
        'notifying', (tester) async {
      fakeNow = DateTime(2026, 11, 3, 11, 59);
      container = makeContainer();
      int notifications = 0;
      container.listen<DateTime>(localNowProvider, (_, __) => notifications++);

      // The timer fires on schedule but the device clock was set back.
      fakeNow = DateTime(2026, 11, 3, 11, 30);
      await tester.pump(const Duration(minutes: 1, seconds: 2));
      expect(notifications, 0);

      // Its replacement still catches the real boundary later.
      fakeNow = DateTime(2026, 11, 3, 12, 0, 1);
      await tester.pump(const Duration(minutes: 31));
      expect(notifications, 1);
    });

    clockTest('disposing stops the timer and the lifecycle observer',
        (tester) async {
      fakeNow = DateTime(2026, 11, 3, 11, 59);
      container = makeContainer(autoDispose: false);
      final LocalNow notifier = container.read(localNowProvider.notifier);
      container.dispose();

      // Neither may throw on a disposed provider, and nothing may stay
      // pending; the test binding fails the test on a leaked timer.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      notifier.refresh();
      await tester.pump(const Duration(hours: 1));
    });
  });
}
