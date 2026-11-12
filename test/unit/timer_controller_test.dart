import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/timer_dao.dart';
import 'package:ironyx/core/l10n/l10n_provider.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/core/services/clock.dart';
import 'package:ironyx/core/services/haptics_service.dart';
import 'package:ironyx/core/services/notification_service.dart';
import 'package:ironyx/core/services/timer_audio_service.dart';
import 'package:ironyx/core/services/wakelock_service.dart';
import 'package:ironyx/features/timer/domain/timer_controller.dart';
import 'package:ironyx/features/timer/domain/timer_preset.dart';
import 'package:ironyx/features/timer/domain/timer_settings_controller.dart';
import 'package:ironyx/l10n/app_localizations_en.dart';
import 'package:mocktail/mocktail.dart';

/// Mock classes for services
class _MockHapticsService extends Mock implements HapticsService {}

class _MockNotificationService extends Mock implements NotificationService {}

class _MockTimerAudioService extends Mock implements TimerAudioService {}

class _MockWakelockService extends Mock implements WakelockService {}

void main() {
  setUpAll(() {
    registerFallbackValue(TimerCue.countdown);
  });

  group('TimerController', () {
    late AppDatabase database;
    late TimerDao timerDao;
    late ProviderContainer container;
    late TimerController controller;

    late _MockHapticsService mockHaptics;
    late _MockNotificationService mockNotifications;
    late _MockTimerAudioService mockAudio;
    late _MockWakelockService mockWakelock;
    late TimerSettings mockSettings;

    setUp(() async {
      database = AppDatabase.forTesting();
      timerDao = TimerDao(database);

      mockHaptics = _MockHapticsService();
      mockNotifications = _MockNotificationService();
      mockAudio = _MockTimerAudioService();
      mockWakelock = _MockWakelockService();
      mockSettings =
          const TimerSettings(soundEnabled: true, hapticsEnabled: true);

      // Default stubs
      when(() => mockNotifications.cancelAll()).thenAnswer((_) async {});
      when(() => mockNotifications.scheduleBoundary(
            id: any(named: 'id'),
            at: any(named: 'at'),
            title: any(named: 'title'),
            body: any(named: 'body'),
          )).thenAnswer((_) async {});
      when(() => mockNotifications.scheduleCompletion(
            at: any(named: 'at'),
            title: any(named: 'title'),
            body: any(named: 'body'),
          )).thenAnswer((_) async {});
      when(() => mockAudio.preload()).thenAnswer((_) async {});
      when(() => mockAudio.cue(any())).thenAnswer((_) async {});
      when(() => mockAudio.dispose()).thenAnswer((_) async {});
      when(() => mockWakelock.enable()).thenAnswer((_) async {});
      when(() => mockWakelock.disable()).thenAnswer((_) async {});
      when(() => mockHaptics.selection()).thenAnswer((_) async {});
      when(() => mockHaptics.impact()).thenAnswer((_) async {});
      when(() => mockHaptics.heavy()).thenAnswer((_) async {});

      container = ProviderContainer(
        overrides: [
          timerDaoProvider.overrideWithValue(timerDao),
          hapticsServiceProvider.overrideWithValue(mockHaptics),
          notificationServiceProvider.overrideWithValue(mockNotifications),
          timerAudioServiceProvider.overrideWithValue(mockAudio),
          wakelockServiceProvider.overrideWithValue(mockWakelock),
          timerSettingsControllerProvider.overrideWithValue(mockSettings),
          // Boundary notifications carry translated text, so the controller
          // resolves localizations while scheduling them. Pinned to English
          // here rather than reached through SharedPreferences, which this
          // test has no reason to stand up.
          appLocalizationsProvider
              .overrideWith((_) async => AppLocalizationsEn()),
        ],
      );

      controller = container.read(timerControllerProvider.notifier);
    });

    tearDown(() async {
      if (controller.isActive) {
        await controller.stop();
      }
      container.dispose();
      await database.close();
    });

    test('start creates engine and ticker', () async {
      final preset = TimerPresets.tabata();

      await controller.start(
        preset,
        notificationGranted: true,
      );

      expect(controller.isActive, isTrue);
      expect(controller.preset, equals(preset));
      expect(controller.state, isNotNull);
      expect(controller.state!.isRunning, isTrue);
    });

    test('pause stops the engine', () async {
      final preset = TimerPresets.tabata();
      await controller.start(preset, notificationGranted: true);

      await controller.pause();

      expect(controller.state!.isRunning, isFalse);
    });

    test('resume continues from paused state', () async {
      final preset = TimerPresets.tabata();
      await controller.start(preset, notificationGranted: true);
      await controller.pause();

      await controller.resume();

      expect(controller.state!.isRunning, isTrue);
    });

    test('skip advances to next phase', () async {
      const preset = TimerPreset(
        id: 'test',
        name: 'Test',
        description: 'Test',
        phases: [
          TimerPhase(type: TimerPhaseType.work, durationSeconds: 20),
          TimerPhase(type: TimerPhaseType.rest, durationSeconds: 10),
        ],
      );
      await controller.start(preset, notificationGranted: true);

      await controller.skip();

      expect(controller.state!.currentIndex, 1);
      expect(controller.state!.currentPhase?.type, TimerPhaseType.rest);
    });

    test('stop writes session to database', () async {
      final preset = TimerPresets.tabata();
      await controller.start(preset, notificationGranted: true);

      await controller.stop();

      expect(controller.isActive, isFalse);
      expect(controller.state, isNull);

      // Verify session was written
      final sessions = await timerDao.watchAll().first;
      expect(sessions, hasLength(1));
      expect(sessions.first.presetName, 'Tabata');
    });

    test('the saved duration is the time run, without pauses', () async {
      DateTime fakeNow = DateTime.utc(2026, 11, 11, 9);
      final ProviderContainer timed = ProviderContainer(
        overrides: [
          timerDaoProvider.overrideWithValue(timerDao),
          hapticsServiceProvider.overrideWithValue(mockHaptics),
          notificationServiceProvider.overrideWithValue(mockNotifications),
          timerAudioServiceProvider.overrideWithValue(mockAudio),
          wakelockServiceProvider.overrideWithValue(mockWakelock),
          timerSettingsControllerProvider.overrideWithValue(mockSettings),
          appLocalizationsProvider
              .overrideWith((_) async => AppLocalizationsEn()),
          clockProvider.overrideWithValue(() => fakeNow),
        ],
      );
      addTearDown(timed.dispose);
      final TimerController timer =
          timed.read(timerControllerProvider.notifier);

      await timer.start(TimerPresets.tabata(), notificationGranted: true);
      fakeNow = fakeNow.add(const Duration(seconds: 5));
      await timer.pause();
      // Ten minutes on pause.
      fakeNow = fakeNow.add(const Duration(minutes: 10));
      await timer.resume();
      fakeNow = fakeNow.add(const Duration(seconds: 7));
      await timer.stop();

      final session = (await timerDao.watchAll().first).single;
      expect(session.actualDurationSeconds, 12,
          reason: 'it was the span from start to end, 612 s');
      // When it happened is unchanged: start to end, pause included.
      expect(session.endedAt!.difference(session.startedAt).inSeconds, 612);
    });

    test('a finished session is saved at its planned length', () async {
      DateTime fakeNow = DateTime.utc(2026, 11, 11, 9);
      final ProviderContainer timed = ProviderContainer(
        overrides: [
          timerDaoProvider.overrideWithValue(timerDao),
          hapticsServiceProvider.overrideWithValue(mockHaptics),
          notificationServiceProvider.overrideWithValue(mockNotifications),
          timerAudioServiceProvider.overrideWithValue(mockAudio),
          wakelockServiceProvider.overrideWithValue(mockWakelock),
          timerSettingsControllerProvider.overrideWithValue(mockSettings),
          appLocalizationsProvider
              .overrideWith((_) async => AppLocalizationsEn()),
          clockProvider.overrideWithValue(() => fakeNow),
        ],
      );
      addTearDown(timed.dispose);
      final TimerController timer =
          timed.read(timerControllerProvider.notifier);
      final preset = TimerPresets.custom(
        workSeconds: 3,
        restSeconds: 2,
        rounds: 1,
      );

      await timer.start(preset, notificationGranted: true);
      // Well past the end before the next tick notices.
      fakeNow = fakeNow.add(const Duration(seconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final session = (await timerDao.watchAll().first).single;
      expect(session.actualDurationSeconds, 5);
    });

    test('ending twice plays the completion cues once', () async {
      await controller.start(TimerPresets.tabata(), notificationGranted: true);
      clearInteractions(mockHaptics);
      clearInteractions(mockAudio);

      await Future.wait(<Future<void>>[controller.stop(), controller.stop()]);
      await controller.stop();

      verify(() => mockHaptics.heavy()).called(1);
      verify(() => mockAudio.cue(TimerCue.complete)).called(1);
      expect(await timerDao.watchAll().first, hasLength(1));
    });

    group('failures (production review 2026-11-12, finding 2)', () {
      test(
          'a wakelock that cannot be held does not stop the timer from '
          'starting and ticking', () async {
        // It threw out of start() with the engine set and no ticker: the
        // timer counted as active, nothing moved, and the caller said it
        // could not start.
        when(() => mockWakelock.enable()).thenThrow(StateError('no wakelock'));

        await controller.start(TimerPresets.tabata(),
            notificationGranted: true);
        final Duration before = controller.state!.remaining;
        await Future<void>.delayed(const Duration(milliseconds: 1100));

        expect(controller.isActive, isTrue);
        expect(controller.state!.remaining, lessThan(before));
      });

      test('alerts that cannot be scheduled do not fail the start', () async {
        when(() => mockNotifications.scheduleCompletion(
              at: any(named: 'at'),
              title: any(named: 'title'),
              body: any(named: 'body'),
            )).thenThrow(StateError('alarm manager'));

        await controller.start(TimerPresets.tabata(),
            notificationGranted: true);

        expect(controller.isActive, isTrue);
      });

      test('a wakelock that cannot be released does not lose the session',
          () async {
        // The release came before the write; its failure skipped the
        // write, and with the engine cleared nothing could retry it.
        when(() => mockWakelock.disable()).thenThrow(StateError('no wakelock'));
        await controller.start(TimerPresets.tabata(),
            notificationGranted: true);

        await controller.stop();

        expect(await timerDao.watchAll().first, hasLength(1));
        expect(controller.state, isNull);
        expect(controller.takeSaveFailure(), isFalse);
        verify(() => mockAudio.cue(TimerCue.complete)).called(1);
      });

      test(
          'a session that cannot be written still ends cleanly and is '
          'reported once', () async {
        final ProviderContainer broken = ProviderContainer(
          overrides: [
            timerDaoProvider.overrideWithValue(_FailingTimerDao(database)),
            hapticsServiceProvider.overrideWithValue(mockHaptics),
            notificationServiceProvider.overrideWithValue(mockNotifications),
            timerAudioServiceProvider.overrideWithValue(mockAudio),
            wakelockServiceProvider.overrideWithValue(mockWakelock),
            timerSettingsControllerProvider.overrideWithValue(mockSettings),
            appLocalizationsProvider
                .overrideWith((_) async => AppLocalizationsEn()),
          ],
        );
        addTearDown(broken.dispose);
        final TimerController timer =
            broken.read(timerControllerProvider.notifier);
        await timer.start(TimerPresets.tabata(), notificationGranted: true);

        await timer.stop();

        expect(timer.isActive, isFalse);
        expect(timer.state, isNull);
        verify(() => mockWakelock.disable()).called(1);
        verify(() => mockNotifications.cancelAll()).called(greaterThan(0));
        expect(timer.takeSaveFailure(), isTrue);
        expect(timer.takeSaveFailure(), isFalse, reason: 'read once');
      });
    });

    test('notification denied flag is set when permission not granted',
        () async {
      final preset = TimerPresets.tabata();
      await controller.start(preset, notificationGranted: false);

      expect(controller.notificationDenied, isTrue);
    });

    test('pause cancels scheduled notifications', () async {
      final preset = TimerPresets.tabata();
      await controller.start(preset, notificationGranted: true);

      await controller.pause();

      verify(() => mockNotifications.cancelAll()).called(greaterThan(0));
    });

    test('resume reschedules boundaries', () async {
      final preset = TimerPresets.tabata();
      await controller.start(preset, notificationGranted: true);
      await controller.pause();

      await controller.resume();

      verify(() => mockNotifications.scheduleBoundary(
            id: any(named: 'id'),
            at: any(named: 'at'),
            title: any(named: 'title'),
            body: any(named: 'body'),
          )).called(greaterThan(0));
    });

    group('boundary notifications', () {
      const TimerPreset threePhases = TimerPreset(
        id: 'test',
        name: 'Test',
        description: 'Test',
        phases: [
          TimerPhase(type: TimerPhaseType.work, durationSeconds: 20),
          TimerPhase(type: TimerPhaseType.rest, durationSeconds: 10),
          TimerPhase(type: TimerPhaseType.work, durationSeconds: 20),
        ],
      );

      /// Every `scheduleBoundary` call since the last interaction reset, as
      /// (id, at, title, body).
      List<({int id, DateTime at, String title, String body})> scheduled() {
        final List<dynamic> captured = verify(
          () => mockNotifications.scheduleBoundary(
            id: captureAny(named: 'id'),
            at: captureAny(named: 'at'),
            title: captureAny(named: 'title'),
            body: captureAny(named: 'body'),
          ),
        ).captured;
        return [
          for (var i = 0; i < captured.length; i += 4)
            (
              id: captured[i] as int,
              at: captured[i + 1] as DateTime,
              title: captured[i + 2] as String,
              body: captured[i + 3] as String,
            ),
        ];
      }

      test('fires at the end of each phase, announcing the one that starts',
          () async {
        final DateTime before = DateTime.now().toUtc();
        await controller.start(threePhases, notificationGranted: true);

        final calls = scheduled();

        // Work 20s -> Rest at +20s, Rest 10s -> Work at +30s. The final
        // work phase's end is the timer finishing, not a boundary.
        expect(calls, hasLength(2));
        expect(calls[0].title, 'Rest phase');
        expect(calls[0].body, 'Rest starts now');
        expect(calls[1].title, 'Work phase');
        expect(calls[1].body, 'Work starts now');
        expect(
          calls[0].at.difference(before).inMilliseconds,
          inInclusiveRange(19000, 21000),
        );
        expect(
          calls[1].at.difference(before).inMilliseconds,
          inInclusiveRange(29000, 31000),
        );
        expect(calls[0].id, isNot(calls[1].id));
      });

      test('the end of the phase already running is still scheduled', () async {
        // Regression guard: the loop used to skip `index <= currentIndex`,
        // which dropped the very next boundary — the one due first.
        final DateTime before = DateTime.now().toUtc();
        await controller.start(threePhases, notificationGranted: true);

        // The first phase is 20s, so the first notification is due then —
        // not at the +30s boundary that used to be the earliest one.
        final first = scheduled().first;
        expect(
          first.at.difference(before).inMilliseconds,
          inInclusiveRange(19000, 21000),
        );
      });

      test('after a skip only the remaining boundaries are scheduled',
          () async {
        await controller.start(threePhases, notificationGranted: true);
        clearInteractions(mockNotifications);

        await controller.skip();

        final calls = scheduled();
        expect(calls, hasLength(1));
        expect(calls.single.title, 'Work phase');
      });

      test('a single-phase timer has no boundaries to announce', () async {
        const TimerPreset single = TimerPreset(
          id: 'single',
          name: 'Single',
          description: 'Single',
          phases: [TimerPhase(type: TimerPhaseType.work, durationSeconds: 60)],
        );
        await controller.start(single, notificationGranted: true);

        verifyNever(
          () => mockNotifications.scheduleBoundary(
            id: any(named: 'id'),
            at: any(named: 'at'),
            title: any(named: 'title'),
            body: any(named: 'body'),
          ),
        );
      });

      test('nothing is scheduled without notification permission', () async {
        await controller.start(threePhases, notificationGranted: false);

        verifyNever(
          () => mockNotifications.scheduleBoundary(
            id: any(named: 'id'),
            at: any(named: 'at'),
            title: any(named: 'title'),
            body: any(named: 'body'),
          ),
        );
      });
    });

    group('completion notification', () {
      const TimerPreset threePhases = TimerPreset(
        id: 'test',
        name: 'Test',
        description: 'Test',
        phases: [
          TimerPhase(type: TimerPhaseType.work, durationSeconds: 20),
          TimerPhase(type: TimerPhaseType.rest, durationSeconds: 10),
          TimerPhase(type: TimerPhaseType.work, durationSeconds: 20),
        ],
      );

      /// Every `scheduleCompletion` call since the last interaction reset,
      /// as (at, title, body).
      List<({DateTime at, String title, String body})> scheduled() {
        final List<dynamic> captured = verify(
          () => mockNotifications.scheduleCompletion(
            at: captureAny(named: 'at'),
            title: captureAny(named: 'title'),
            body: captureAny(named: 'body'),
          ),
        ).captured;
        return [
          for (var i = 0; i < captured.length; i += 3)
            (
              at: captured[i] as DateTime,
              title: captured[i + 1] as String,
              body: captured[i + 2] as String,
            ),
        ];
      }

      test('is scheduled for the end of the last phase', () async {
        final DateTime before = DateTime.now().toUtc();
        await controller.start(threePhases, notificationGranted: true);

        // 20 + 10 + 20 seconds. The last phase's end is not a boundary,
        // so `scheduleBoundary` never announces it; this does.
        final calls = scheduled();
        expect(calls, hasLength(1));
        expect(calls.single.title, 'Timer complete');
        expect(calls.single.body, 'Your session is finished.');
        expect(
          calls.single.at.difference(before).inMilliseconds,
          inInclusiveRange(49000, 51000),
        );
      });

      test('a single-phase timer still announces its end', () async {
        const TimerPreset single = TimerPreset(
          id: 'single',
          name: 'Single',
          description: 'Single',
          phases: [TimerPhase(type: TimerPhaseType.work, durationSeconds: 60)],
        );
        final DateTime before = DateTime.now().toUtc();
        await controller.start(single, notificationGranted: true);

        expect(
          scheduled().single.at.difference(before).inMilliseconds,
          inInclusiveRange(59000, 61000),
        );
      });

      test('is rescheduled from the new position after a skip', () async {
        await controller.start(threePhases, notificationGranted: true);
        clearInteractions(mockNotifications);
        final DateTime before = DateTime.now().toUtc();

        await controller.skip();

        // Skipping the first 20 s phase leaves 10 + 20 s.
        expect(
          scheduled().single.at.difference(before).inMilliseconds,
          inInclusiveRange(29000, 31000),
        );
      });

      test('resume schedules it again', () async {
        await controller.start(threePhases, notificationGranted: true);
        await controller.pause();
        clearInteractions(mockNotifications);

        await controller.resume();

        expect(scheduled(), hasLength(1));
      });

      test('nothing is scheduled without notification permission', () async {
        await controller.start(threePhases, notificationGranted: false);

        verifyNever(
          () => mockNotifications.scheduleCompletion(
            at: any(named: 'at'),
            title: any(named: 'title'),
            body: any(named: 'body'),
          ),
        );
      });
    });

    test('settings toggles trigger haptics and audio on phase transition',
        () async {
      const preset = TimerPreset(
        id: 'test',
        name: 'Test',
        description: 'Test',
        phases: [
          TimerPhase(type: TimerPhaseType.work, durationSeconds: 1),
          TimerPhase(type: TimerPhaseType.rest, durationSeconds: 1),
        ],
      );
      await controller.start(preset, notificationGranted: true);

      // Wait for phase transition
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.skip();

      verify(() => mockHaptics.impact()).called(1);
      verify(() => mockAudio.cue(TimerCue.transition)).called(1);
    });

    test(
        'a session completed right as the controller is disposed is still '
        'written', () async {
      // Regression guard: `_finish()` used to bail out on `_disposed` before
      // reaching the database write, so a session that completed in the same
      // window as the screen closing was silently dropped. The DAO now has
      // to be captured before any await that can run past disposal.
      final Completer<void> wakelockDisabled = Completer<void>();
      when(() => mockWakelock.disable())
          .thenAnswer((_) => wakelockDisabled.future);

      await controller.start(TimerPresets.tabata(), notificationGranted: true);
      final Future<void> stopFuture = controller.stop();

      // Dispose the whole container while `_finish()` is suspended awaiting
      // `_wakelock.disable()` — the exact window the fix protects. `dispose`
      // is idempotent, so `tearDown`'s own call below is a no-op after this.
      container.dispose();
      wakelockDisabled.complete();
      await stopFuture;

      final int sessionCount = await database
          .customSelect(
            'SELECT COUNT(*) AS count FROM timer_sessions_table',
          )
          .getSingle()
          .then((row) => row.read<int>('count'));
      expect(sessionCount, 1);
    });
  });
}

/// A timer DAO whose session write fails, as a full disk would.
class _FailingTimerDao extends TimerDao {
  _FailingTimerDao(super.db);

  @override
  Future<String> insertSession(
    TimerSessionsTableCompanion session,
    List<TimerIntervalsTableCompanion> intervals,
  ) async =>
      throw StateError('disk full');
}
