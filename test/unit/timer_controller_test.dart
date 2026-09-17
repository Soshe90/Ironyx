import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/timer_dao.dart';
import 'package:ironyx/core/l10n/l10n_provider.dart';
import 'package:ironyx/core/providers.dart';
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
