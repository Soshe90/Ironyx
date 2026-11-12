import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/timer_preset_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/formatters/number_input.dart';
import 'package:ironyx/core/services/notification_service.dart';
import 'package:ironyx/features/timer/domain/timer_controller.dart';
import 'package:ironyx/features/timer/domain/timer_engine.dart';
import 'package:ironyx/features/timer/domain/timer_preset.dart';
import 'package:ironyx/features/timer/presentation/active_timer_page.dart';

import '../helpers/pump_app.dart';

/// Counts starts instead of running a session; [fail] makes start throw.
class _CountingController extends TimerController {
  int starts = 0;
  bool fail = false;

  @override
  TimerSnapshot? build() => null;

  @override
  bool get isActive => state != null;

  @override
  Future<void> start(
    TimerPreset preset, {
    required bool notificationGranted,
  }) async {
    starts++;
    if (fail) throw StateError('no wakelock');
    state = const TimerSnapshot(
      currentIndex: 0,
      currentPhase: TimerPhase(type: TimerPhaseType.work, durationSeconds: 20),
      remaining: Duration(seconds: 20),
      elapsed: Duration.zero,
      total: Duration(minutes: 4),
      progress: 0,
      isRunning: true,
      isComplete: false,
    );
  }

  @override
  Future<void> stop() async => state = null;
}

/// Granted, after a moment: the wait a real permission check takes.
class _SlowNotifications extends NoopNotificationService {
  @override
  Future<bool> get isPermissionGranted =>
      Future<bool>.delayed(const Duration(milliseconds: 200), () => true);
}

class _FailingPresetDao extends TimerPresetDao {
  _FailingPresetDao(super.db);

  @override
  Future<String> save(TimerPreset preset) =>
      Future<String>.error(StateError('disk full'));
}

void main() {
  group('TimerPage', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.forTesting();
    });

    tearDown(() async {
      await database.close();
    });

    testWidgets(
        'shows quick-start presets and the custom builder; feedback toggles '
        'live in Settings, and saved presets appear only once there are some',
        (tester) async {
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        initialLocation: '/timer',
        prefs: const {'exercise_seed_version': 999999},
        surfaceSize: const Size(400, 1400),
      );

      expect(find.text('Tabata'), findsOneWidget);
      expect(find.text('HIIT'), findsOneWidget);
      expect(find.text('Strength'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('Work (s)'), findsOneWidget);
      final Iterable<TextField> fields =
          tester.widgetList<TextField>(find.byType(TextField));
      expect(fields, hasLength(5));
      for (final TextField field in fields) {
        expect(field.style?.fontSize, 18);
        expect(field.decoration?.labelText, isNull);
        expect(field.decoration?.enabledBorder, isA<OutlineInputBorder>());
        expect(field.decoration?.focusedBorder, isA<OutlineInputBorder>());
        // Arabic digits typed into a timer field are kept as digits.
        expect(
          field.inputFormatters,
          contains(isA<NumberInputFormatter>()
              .having((f) => f.decimal, 'decimal', isFalse)),
        );
      }
      expect(find.text('Sound cues'), findsNothing);
      expect(find.text('Haptics'), findsNothing);
      expect(find.text('Saved presets'), findsNothing);
    });

    testWidgets('quick start comes before the saved preset section',
        (tester) async {
      await tester.runAsync(
        () => TimerPresetDao(database).save(
          TimerPresets.tabata().copyWith(id: 'mine', name: 'My EMOM'),
        ),
      );
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        initialLocation: '/timer',
        prefs: const {'exercise_seed_version': 999999},
        surfaceSize: const Size(400, 1400),
        awaitDatabase: true,
      );
      await tester.pump();

      expect(find.text('Saved presets'), findsOneWidget);
      expect(find.text('My EMOM'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Quick start')).dy,
        lessThan(tester.getTopLeft(find.text('Saved presets')).dy),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
    testWidgets('a custom timer past the limits does not start',
        (tester) async {
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        initialLocation: '/timer',
        prefs: const {'exercise_seed_version': 999999},
        surfaceSize: const Size(400, 1400),
      );
      final Finder rounds = find.byType(TextField).at(2);
      await tester.enterText(rounds, '80000');
      await tester.tap(find.text('Start custom'));
      await tester.pumpAndSettle();

      // Said under the field at fault, not at the foot of the screen.
      expect(find.text('At most 99'), findsOneWidget);
      expect(find.text('Start custom'), findsOneWidget,
          reason: 'still on the Timer tab, nothing started');
    });
    testWidgets('a preset is saved under a name, and can be deleted',
        (tester) async {
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        initialLocation: '/timer',
        prefs: const {'exercise_seed_version': 999999},
        surfaceSize: const Size(400, 1800),
        awaitDatabase: true,
      );

      await tester.tap(find.text('Save preset'));
      await tester.pumpAndSettle();
      // Filled in with the formula; replaced with a name of one's own.
      expect(find.text('Name this preset'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        '30s work / 10s rest × 8',
      );
      await tester.enterText(find.byType(TextField).last, 'Leg day finisher');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Leg day finisher'), findsOneWidget,
          reason: 'every saved preset used to read "Custom"');

      await tester.tap(find.byTooltip('Preset options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Leg day finisher'), findsNothing);
      expect(find.text('Preset deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Leg day finisher'), findsOneWidget);
    });

    testWidgets('a blank name saves the formula', (tester) async {
      await pumpApp(
        tester,
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        initialLocation: '/timer',
        prefs: const {'exercise_seed_version': 999999},
        surfaceSize: const Size(400, 1800),
        awaitDatabase: true,
      );

      await tester.tap(find.text('Save preset'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final presets = await tester.runAsync(
        () => TimerPresetDao(database).getAll(),
      );
      expect(presets!.single.name, '30s work / 10s rest × 8');
    });
    group('starting a timer', () {
      late _CountingController controller;

      Future<void> open(WidgetTester tester,
              {List<dynamic> extra = const []}) =>
          pumpApp(
            tester,
            overrides: [
              appDatabaseProvider.overrideWithValue(database),
              timerControllerProvider.overrideWith(() => controller),
              notificationServiceProvider
                  .overrideWithValue(_SlowNotifications()),
              ...extra,
            ],
            initialLocation: '/timer',
            prefs: const {'exercise_seed_version': 999999},
            surfaceSize: const Size(400, 1800),
          );

      Future<void> frames(WidgetTester tester) async {
        for (int i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
      }

      setUp(() => controller = _CountingController());

      testWidgets('a double tap starts one session', (tester) async {
        await open(tester);
        await tester.tap(find.text('Tabata'));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.tap(find.text('Tabata'));
        await frames(tester);

        expect(controller.starts, 1,
            reason: 'the second tap, during the wait, started a second one');
        expect(find.byType(ActiveTimerPage), findsOneWidget);
      });

      testWidgets('with a session running, a preset opens it', (tester) async {
        await open(tester);
        // Through the container, which attaches the notifier first; set
        // before that, its state was reset by build() on the first read.
        await tester.runAsync(
          () => ProviderScope.containerOf(tester.element(find.text('Tabata')))
              .read(timerControllerProvider.notifier)
              .start(TimerPresets.tabata(), notificationGranted: true),
        );
        controller.starts = 0;
        await tester.pump();

        await tester.tap(find.text('HIIT'));
        await frames(tester);

        expect(controller.starts, 0,
            reason: 'starting again threw the running session away');
        expect(find.byType(ActiveTimerPage), findsOneWidget);
      });

      testWidgets('a start that fails says so', (tester) async {
        controller.fail = true;
        await open(tester);
        await tester.tap(find.text('Tabata'));
        await frames(tester);

        expect(find.text("Couldn't start the timer."), findsOneWidget);
        expect(find.byType(ActiveTimerPage), findsNothing);
      });

      testWidgets('a save that fails says so', (tester) async {
        await open(
          tester,
          extra: [
            timerPresetDaoProvider
                .overrideWith((ref) => _FailingPresetDao(database)),
          ],
        );
        await tester.tap(find.text('Save preset'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await frames(tester);

        expect(find.text("Couldn't save the preset."), findsOneWidget);
      });
    });
    group('the custom builder', () {
      Future<void> openBuilder(WidgetTester tester) => pumpApp(
            tester,
            overrides: [appDatabaseProvider.overrideWithValue(database)],
            initialLocation: '/timer',
            prefs: const {'exercise_seed_version': 999999},
            surfaceSize: const Size(400, 1800),
          );
      Finder field(int i) => find.byType(TextField).at(i);

      testWidgets('shows the total as it is typed', (tester) async {
        await openBuilder(tester);
        // 30 s work, 10 s rest, 8 rounds: 16 intervals, 5:20.
        expect(find.text('Total 05:20 · 16 intervals'), findsOneWidget);

        await tester.enterText(field(2), '4');
        await tester.pump();
        expect(find.text('Total 02:40 · 8 intervals'), findsOneWidget);
      });

      testWidgets('marks a field only after Start, then follows the typing',
          (tester) async {
        await openBuilder(tester);
        await tester.enterText(field(0), '0');
        await tester.pump();
        expect(find.text('At least 1'), findsNothing,
            reason: 'not while it is still being typed');
        expect(find.textContaining('Total'), findsNothing);

        await tester.tap(find.text('Start custom'));
        await tester.pump();
        expect(find.text('At least 1'), findsOneWidget);

        await tester.enterText(field(0), '45');
        await tester.pump();
        expect(find.text('At least 1'), findsNothing);
      });

      testWidgets('allows a work-only timer', (tester) async {
        await openBuilder(tester);
        await tester.enterText(field(1), '0');
        await tester.pump();

        // 8 rounds of 30 s, no rest phases.
        expect(find.text('Total 04:00 · 8 intervals'), findsOneWidget);
        await tester.tap(find.text('Save preset'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byType(TextField).last)
              .controller!
              .text,
          '30s work × 8',
        );
      });
    });
  });
}
