import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/features/timer/presentation/active_timer_page.dart';

import 'helpers/e2e_harness.dart';

/// Interval timer on a real device: real wall-clock time, real alarms.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// What Android actually has queued for this app, straight from the
  /// plugin, rather than what the app believes it asked for.
  Future<List<PendingNotificationRequest>> pendingAlarms(
    WidgetTester tester,
  ) =>
      io(
        tester,
        () => FlutterLocalNotificationsPlugin().pendingNotificationRequests(),
      );

  Future<E2eApp> openTimerTab(WidgetTester tester) async {
    final E2eApp app = await E2eApp.install(prefs: {
      'onboarding_complete': true,
    });
    await app.launch(tester);
    await pumpUntilFound(tester, find.byType(NavigationBar));
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Timer'),
    ));
    await pumpUntilFound(tester, find.text('Start custom'));
    return app;
  }

  Finder field(String label) => find.descendant(
        of: semanticsLabelled(label),
        matching: find.byType(TextField),
      );

  Future<void> setCustom(
    WidgetTester tester, {
    String work = '30',
    String rest = '10',
    String rounds = '8',
    String warmup = '0',
    String cooldown = '0',
  }) async {
    for (final MapEntry<String, String> e in <String, String>{
      'Work (s)': work,
      'Rest (s)': rest,
      'Rounds': rounds,
      'Warm-up (s)': warmup,
      'Cool-down (s)': cooldown,
    }.entries) {
      await tester.scrollUntilVisible(
        field(e.key),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(field(e.key), e.value);
    }
    await tester.pump();
  }

  Future<void> startCustom(WidgetTester tester) async {
    await scrollToAndTap(tester, find.text('Start custom'));
    await pumpUntilFound(tester, find.byType(ActiveTimerPage));
  }

  /// Ending early asks for confirmation, so a stray tap mid-set cannot
  /// throw the session away.
  Future<void> endTimer(WidgetTester tester) async {
    await tester.tap(find.byTooltip('End timer').last);
    await pumpUntilFound(tester, find.text('End this timer?'));
    await tester.tap(find.widgetWithText(FilledButton, 'End timer'));
    await pumpUntilGone(tester, find.byType(ActiveTimerPage));
  }

  Future<List<TimerSessionsTableData>> sessions(
    WidgetTester tester,
    E2eApp app,
  ) =>
      io(tester, () => app.db.select(app.db.timerSessionsTable).get());

  testWidgets(
      'a short custom timer runs to completion in real time, schedules its '
      'alarms with Android, and records the session', (tester) async {
    final E2eApp app = await openTimerTab(tester);
    // 2 s work, 1 s rest, 2 rounds: W R W R = 4 intervals, 6 s.
    await setCustom(tester, work: '2', rest: '1', rounds: '2');
    final Stopwatch clock = Stopwatch()..start();
    await startCustom(tester);

    expect(find.text('INTERVAL 1 OF 4'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);

    // Three phase boundaries plus the completion alert. On Android 12 the
    // permission is granted at install, so all four should be queued.
    final List<PendingNotificationRequest> queued = await pendingAlarms(tester);
    // ignore: avoid_print
    print('[e2e] pending alarms after start: '
        '${queued.map((p) => '${p.id}:${p.title}').join(', ')}');
    expect(queued.map((p) => p.id), containsAll(<int>[10000, 10001, 10002]));
    expect(queued.map((p) => p.id), contains(20000));
    expect(queued.where((p) => p.id == 20000).single.title, 'Timer complete');

    await pumpUntilGone(
      tester,
      find.byType(ActiveTimerPage),
      timeout: const Duration(seconds: 20),
    );
    clock.stop();
    // ignore: avoid_print
    print('[e2e] 6 s timer took ${clock.elapsedMilliseconds} ms end to end');
    expect(clock.elapsed, greaterThanOrEqualTo(const Duration(seconds: 6)));
    expect(clock.elapsed, lessThan(const Duration(seconds: 12)));

    // Back on the Timer tab, the session recorded as complete, and nothing
    // left queued to go off later.
    expect(find.text('Start custom'), findsOneWidget);
    final List<TimerSessionsTableData> rows = await sessions(tester, app);
    expect(rows, hasLength(1));
    expect(rows.single.totalIntervals, 4);
    expect(rows.single.intervalsCompleted, 4);
    expect(rows.single.plannedDurationSeconds, 6);
    expect(await pendingAlarms(tester), isEmpty);
  });

  testWidgets(
      'pausing freezes the countdown and clears alarms; resuming restores '
      'both', (tester) async {
    await openTimerTab(tester);
    await setCustom(tester, work: '30', rest: '10', rounds: '2');
    await startCustom(tester);

    await tester.tap(semanticsLabelled('Pause timer'));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(semanticsLabelled('Resume timer'), findsOneWidget);
    expect(await pendingAlarms(tester), isEmpty,
        reason: 'a paused timer must not buzz later');

    final String frozen = _countdownText(tester);
    await pumpFor(tester, const Duration(milliseconds: 2500));
    expect(_countdownText(tester), frozen, reason: 'time passed while paused');

    await tester.tap(semanticsLabelled('Resume timer'));
    await pumpFor(tester, const Duration(milliseconds: 2200));
    expect(_countdownText(tester), isNot(frozen));
    expect(await pendingAlarms(tester), isNotEmpty);

    await endTimer(tester);
  });

  testWidgets(
      'skipping moves to the next interval, and ending early records a '
      'partial session', (tester) async {
    final E2eApp app = await openTimerTab(tester);
    await setCustom(tester, work: '30', rest: '10', rounds: '3');
    await startCustom(tester);
    expect(find.text('INTERVAL 1 OF 6'), findsOneWidget);

    await tester.tap(find.byTooltip('Skip interval'));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.text('INTERVAL 2 OF 6'), findsOneWidget);
    expect(find.text('Rest'), findsOneWidget);
    // The alarm for the phase just skipped is gone; later ones remain.
    final Iterable<int> ids = (await pendingAlarms(tester)).map((p) => p.id);
    expect(ids, isNot(contains(10000)));
    expect(ids, contains(20000));

    await endTimer(tester);

    final List<TimerSessionsTableData> rows = await sessions(tester, app);
    expect(rows.single.totalIntervals, 6);
    expect(rows.single.intervalsCompleted, 1);
    expect(await pendingAlarms(tester), isEmpty);
  });

  testWidgets('going to the background and back keeps wall-clock time',
      (tester) async {
    await openTimerTab(tester);
    await setCustom(tester, work: '30', rest: '10', rounds: '2');
    await startCustom(tester);
    final int before = _secondsLeft(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpFor(tester, const Duration(milliseconds: 400));

    // The engine measures from the wall clock, so time away counts.
    final int after = _secondsLeft(tester);
    expect(before - after, inInclusiveRange(3, 5));
    // Resuming re-queues the alarms still ahead.
    expect(await pendingAlarms(tester), isNotEmpty);

    await endTimer(tester);
  });

  testWidgets('invalid custom values are refused with a message',
      (tester) async {
    final E2eApp app = await openTimerTab(tester);
    const String message = 'Work, rest and rounds must be positive.';

    final List<Map<String, String>> invalid = <Map<String, String>>[
      <String, String>{'work': '0'},
      <String, String>{'rest': '0'},
      <String, String>{'rounds': '0'},
      <String, String>{'work': ''},
      <String, String>{'rounds': ''},
    ];
    for (final Map<String, String> values in invalid) {
      await setCustom(
        tester,
        work: values['work'] ?? '30',
        rest: values['rest'] ?? '10',
        rounds: values['rounds'] ?? '8',
      );
      await scrollToAndTap(tester, find.text('Start custom'));
      await pumpUntilFound(tester, find.text(message));
      expect(find.byType(ActiveTimerPage), findsNothing, reason: '$values');
      ScaffoldMessenger.of(tester.element(find.text('Start custom')))
          .removeCurrentSnackBar();
      await tester.pump();
    }

    // Non-digits never get into a field.
    await tester.enterText(field('Rounds'), '-3x');
    await tester.pump();
    expect(tester.widget<TextField>(field('Rounds')).controller!.text, '3');

    // Saving a preset validates the same way, and writes nothing.
    await setCustom(tester, work: '0');
    await scrollToAndTap(tester, find.text('Save preset'));
    await pumpUntilFound(tester, find.text(message));
    expect(
      await io(tester, () => app.db.select(app.db.timerPresetsTable).get()),
      isEmpty,
    );
    expect(await sessions(tester, app), isEmpty);
  });

  testWidgets(
      'a saved preset appears under Saved presets and survives a '
      'relaunch', (tester) async {
    final E2eApp app = await openTimerTab(tester);
    await setCustom(tester, work: '45', rest: '15', rounds: '4');
    await scrollToAndTap(tester, find.text('Save preset'));
    await pumpUntilFound(tester, find.text('Preset saved.'));

    await app.kill(tester);
    await app.launch(tester);
    await pumpUntilFound(tester, find.byType(NavigationBar));
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Timer'),
    ));
    await pumpUntilFound(tester, find.text('Saved presets'));
    expect(
      await io(tester, () => app.db.select(app.db.timerPresetsTable).get()),
      hasLength(1),
    );
  });
}

/// The big countdown digits on the active timer.
String _countdownText(WidgetTester tester) {
  final Finder digits = find.descendant(
    of: find.byType(ActiveTimerPage),
    matching: find.byWidgetPredicate(
      (w) => w is Text && RegExp(r'^\d{1,2}:\d{2}$').hasMatch(w.data ?? ''),
    ),
  );
  return tester.widget<Text>(digits.first).data!;
}

int _secondsLeft(WidgetTester tester) {
  final List<String> parts = _countdownText(tester).split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}
