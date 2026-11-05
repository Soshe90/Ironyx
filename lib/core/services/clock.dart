import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'clock.g.dart';

/// Where "now" comes from. Production uses the device clock; tests override
/// this with a fixed or steppable function.
///
/// Kept separate from [LocalNow] so a test can control time without also
/// replacing the refresh behaviour it is trying to check.
@Riverpod(keepAlive: true)
DateTime Function() clock(Ref ref) => DateTime.now;

/// The three parts of the day the dashboard greets by.
///
/// The hour boundaries live here, not in the widget, because [LocalNow]
/// has to schedule its refreshes at exactly the same moments the greeting
/// changes.
enum DayPart {
  morning,
  afternoon,
  evening;

  static const int afternoonStartHour = 12;
  static const int eveningStartHour = 18;

  static DayPart of(DateTime time) => switch (time.hour) {
        < afternoonStartHour => DayPart.morning,
        < eveningStartHour => DayPart.afternoon,
        _ => DayPart.evening,
      };

  /// The first moment after [time] at which the calendar day or the
  /// [DayPart] changes: today's 12:00 or 18:00, otherwise next midnight.
  ///
  /// Built from local calendar fields rather than by adding a [Duration],
  /// so a daylight-saving change cannot move the boundary off the hour.
  static DateTime nextBoundaryAfter(DateTime time) {
    for (final int hour in const <int>[afternoonStartHour, eveningStartHour]) {
      final DateTime boundary = DateTime(time.year, time.month, time.day, hour);
      if (boundary.isAfter(time)) return boundary;
    }
    return DateTime(time.year, time.month, time.day + 1);
  }
}

/// A coarse "now" for UI that names the current day or part of the day.
///
/// Widgets that read `DateTime.now()` in `build()` keep showing whatever
/// time they were last built at. A dashboard left in memory overnight
/// greeted the user with "Good evening" and the previous Friday's date on a
/// Tuesday morning. This provider changes only when it matters: at the next
/// [DayPart] or day boundary, and when the app returns to the foreground
/// (timers do not run while Android has the process suspended, so a resume
/// is often the first chance to notice the day has changed).
///
/// The value is the time of the last refresh. It is deliberately not a
/// ticking clock: consumers rebuild at most a few times a day.
@Riverpod(keepAlive: true)
class LocalNow extends _$LocalNow with WidgetsBindingObserver {
  /// Margin past the boundary, so the refresh never lands a hair early and
  /// sees the old period still in force.
  static const Duration _boundarySlack = Duration(seconds: 1);

  Timer? _boundaryTimer;

  @override
  DateTime build() {
    final DateTime current = ref.watch(clockProvider)();
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _boundaryTimer?.cancel();
      _boundaryTimer = null;
    });
    _scheduleNextRefresh(current);
    return current;
  }

  // `state` here is the lifecycle, shadowing the notifier's own `state`;
  // the analyzer requires the overridden name, so this body must not read
  // the notifier value.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  /// Re-reads the clock. Listeners are notified only if the calendar day or
  /// [DayPart] has changed since the last value, so calling this often is
  /// cheap.
  void refresh() {
    if (!ref.mounted) return;
    final DateTime current = ref.read(clockProvider)();
    if (!_samePeriod(current, state)) state = current;
    _scheduleNextRefresh(current);
  }

  void _scheduleNextRefresh(DateTime from) {
    _boundaryTimer?.cancel();
    final Duration wait =
        DayPart.nextBoundaryAfter(from).difference(from) + _boundarySlack;
    _boundaryTimer = Timer(wait, refresh);
  }

  static bool _samePeriod(DateTime a, DateTime b) =>
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day &&
      DayPart.of(a) == DayPart.of(b);
}

/// Today's local date at midnight.
///
/// Riverpod only notifies listeners when this value changes, so queries
/// keyed on it re-run once a day, not at every [DayPart] boundary.
@Riverpod(keepAlive: true)
DateTime today(Ref ref) {
  final DateTime now = ref.watch(localNowProvider);
  return DateTime(now.year, now.month, now.day);
}
