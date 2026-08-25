import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/l10n/l10n_provider.dart';
import '../../../core/providers.dart';
import '../../../core/services/haptics_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/timer_audio_service.dart';
import '../../../core/services/wakelock_service.dart';
import 'timer_engine.dart';
import 'timer_preset.dart';
import 'timer_settings_controller.dart';

part 'timer_controller.g.dart';

const _uuid = Uuid();

/// Owns an active timer session (ADR-4).
///
/// The [TimerEngine] does all wall-clock math; this controller adds the UI
/// tick, side effects (haptics, audio, wakelock, notifications) and the
/// transactional write of a `timer_sessions` row on completion.
@Riverpod(keepAlive: true)
class TimerController extends _$TimerController with WidgetsBindingObserver {
  static const Duration _tickInterval = Duration(milliseconds: 200);

  TimerEngine? _engine;
  Timer? _ticker;
  TimerPreset _preset = TimerPresets.tabata();
  DateTime _startedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastIndex = 0;
  int _lastCountdownSecond = -1;
  bool _notificationDenied = false;
  bool _notificationGranted = false;
  bool _disposed = false;
  late final NotificationService _notifications;
  late final WakelockService _wakelock;
  late final TimerAudioService _audio;

  @override
  TimerSnapshot? build() {
    _notifications = ref.read(notificationServiceProvider);
    _wakelock = ref.read(wakelockServiceProvider);
    _audio = ref.read(timerAudioServiceProvider);
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(_dispose);
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _engine != null) {
      unawaited(_rescheduleBoundaries());
    }
  }

  TimerPreset get preset => _preset;

  bool get isActive => _engine != null;

  /// Whether the user denied notification permission for this session. The
  /// timer still works; the UI shows a one-time banner (ADR-4).
  bool get notificationDenied => _notificationDenied;

  /// Starts a session. [notificationGranted] reflects the result of the
  /// in-context permission request made by the caller; a denial must never
  /// prevent the timer from running.
  Future<void> start(
    TimerPreset preset, {
    required bool notificationGranted,
  }) async {
    _preset = preset;
    _notificationDenied = !notificationGranted;
    _notificationGranted = notificationGranted;
    _startedAt = DateTime.now().toUtc();
    _lastIndex = 0;
    _lastCountdownSecond = -1;

    _engine = TimerEngine(phases: preset.phases)..start();
    await _wakelock.enable();
    if (_disposed) return;
    await _audio.preload();

    _ticker?.cancel();
    _ticker = Timer.periodic(_tickInterval, (_) => _tick());
    _tick();
    await _rescheduleBoundaries();
  }

  Future<void> pause() async {
    _engine?.pause();
    await _notifications.cancelAll();
    if (!_disposed) _tick();
  }

  Future<void> resume() async {
    _engine?.resume();
    if (!_disposed) _tick();
    await _rescheduleBoundaries();
  }

  Future<void> skip() async {
    _engine?.skip();
    await _rescheduleBoundaries();
    if (!_disposed) _tick();
  }

  /// Ends the session early (user exits).
  Future<void> stop() => _finish();

  void _tick() {
    final TimerEngine? engine = _engine;
    if (engine == null || _disposed) return;

    final TimerSnapshot snapshot = engine.snapshot();
    state = snapshot;

    if (snapshot.isComplete) {
      _finish();
      return;
    }

    if (snapshot.isRunning) {
      _maybeCountdown(snapshot);
      _maybeTransition(snapshot);
    }
  }

  void _maybeCountdown(TimerSnapshot snapshot) {
    final int second = snapshot.remaining.inSeconds;
    if (second > 0 && second <= 3 && second != _lastCountdownSecond) {
      _lastCountdownSecond = second;
      if (ref.read(timerSettingsControllerProvider).hapticsEnabled) {
        ref.read(hapticsServiceProvider).selection();
      }
      if (ref.read(timerSettingsControllerProvider).soundEnabled) {
        ref.read(timerAudioServiceProvider).cue(TimerCue.countdown);
      }
    }
  }

  void _maybeTransition(TimerSnapshot snapshot) {
    if (snapshot.currentIndex == _lastIndex) return;
    _lastIndex = snapshot.currentIndex;

    if (ref.read(timerSettingsControllerProvider).hapticsEnabled) {
      ref.read(hapticsServiceProvider).impact();
    }
    if (ref.read(timerSettingsControllerProvider).soundEnabled) {
      ref.read(timerAudioServiceProvider).cue(TimerCue.transition);
    }
  }

  Future<void> _finish() async {
    _ticker?.cancel();
    _ticker = null;
    final TimerEngine? engine = _engine;
    _engine = null;

    await _wakelock.disable();
    await _notifications.cancelAll();
    if (_disposed) return;

    final TimerSettings settings = ref.read(timerSettingsControllerProvider);
    if (settings.hapticsEnabled) {
      await ref.read(hapticsServiceProvider).heavy();
    }
    if (settings.soundEnabled) {
      await ref.read(timerAudioServiceProvider).cue(TimerCue.complete);
    }

    await _writeSession(engine);
    await _audio.dispose();

    if (!_disposed) state = null;
  }

  Future<void> _writeSession(TimerEngine? engine) async {
    if (engine == null) return;

    final DateTime endedAt = DateTime.now().toUtc();
    final int actualSeconds = endedAt.difference(_startedAt).inSeconds;
    final int totalIntervals = _preset.totalIntervals;

    final TimerSnapshot finalSnapshot = engine.snapshot();
    final int intervalsCompleted =
        finalSnapshot.isComplete ? totalIntervals : finalSnapshot.currentIndex;

    final String sessionId = _uuid.v4();
    final List<TimerIntervalsTableCompanion> intervals = [
      for (var i = 0; i < _preset.phases.length; i++)
        TimerIntervalsTableCompanion.insert(
          id: _uuid.v4(),
          sessionId: sessionId,
          intervalIndex: i,
          type: _preset.phases[i].type.name,
          plannedDurationSeconds: _preset.phases[i].durationSeconds,
          actualDurationSeconds: Value(
            i < intervalsCompleted ? _preset.phases[i].durationSeconds : null,
          ),
          isCompleted: Value(i < intervalsCompleted),
        ),
    ];

    await ref.read(timerDaoProvider).insertSession(
          TimerSessionsTableCompanion.insert(
            id: sessionId,
            startedAt: _startedAt,
            endedAt: Value(endedAt),
            plannedDurationSeconds: _preset.totalDurationSeconds,
            actualDurationSeconds: Value(actualSeconds),
            presetName: _preset.name,
            intervalsCompleted: Value(intervalsCompleted),
            totalIntervals: totalIntervals,
          ),
          intervals,
        );
  }

  Future<void> _rescheduleBoundaries() async {
    final TimerEngine? engine = _engine;
    if (engine == null ||
        _disposed ||
        !_notificationGranted ||
        !engine.isRunning) {
      return;
    }

    final NotificationService notifications = _notifications;
    // Resolved once per reschedule: these notifications fire minutes from
    // now, with no widget tree to read a language from by then.
    final AppLocalizations l10n = await ref.read(
      appLocalizationsProvider.future,
    );
    await notifications.cancelAll();
    if (_disposed) return;
    final TimerSnapshot snapshot = engine.snapshot();
    var boundary = Duration.zero;
    final DateTime now = DateTime.now().toUtc();
    for (var index = 0; index < _preset.phases.length; index++) {
      boundary += Duration(seconds: _preset.phases[index].durationSeconds);
      if (index <= snapshot.currentIndex ||
          index == _preset.phases.length - 1) {
        continue;
      }
      final Duration untilBoundary = boundary - snapshot.elapsed;
      if (untilBoundary <= Duration.zero) continue;
      final TimerPhase nextPhase = _preset.phases[index];
      await notifications.scheduleBoundary(
        id: 10000 + index,
        at: now.add(untilBoundary),
        title: l10n.timerNotificationTitle(nextPhase.type.label(l10n)),
        body: l10n.timerNotificationBody(nextPhase.type.label(l10n)),
      );
    }
  }

  void _dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _ticker = null;
    _engine = null;
    unawaited(_notifications.cancelAll());
    unawaited(_wakelock.disable());
    unawaited(_audio.dispose());
  }
}
