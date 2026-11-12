import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/timer_dao.dart';
import '../../../core/error_reporting.dart';
import '../../../core/formatters/unit_formatters.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/l10n/l10n_provider.dart';
import '../../../core/providers.dart';
import '../../../core/services/clock.dart';
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

  /// Set when a finished session could not be written; read once by the
  /// screen that closes with it ([takeSaveFailure]).
  bool _saveFailed = false;

  /// The app's clock (`clockProvider`): the device clock, or a test's.
  DateTime Function() _now = DateTime.now;
  late final NotificationService _notifications;
  late final WakelockService _wakelock;
  late final TimerAudioService _audio;

  @override
  TimerSnapshot? build() {
    _now = ref.read(clockProvider);
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

  /// Whether the last session to finish could not be saved to the history,
  /// cleared by reading it. The timer screen closes when a session ends,
  /// for whatever reason, and asks this so it can say so.
  bool takeSaveFailure() {
    final bool failed = _saveFailed;
    _saveFailed = false;
    return failed;
  }

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
    // A failure no screen was open to report belongs to that session, not
    // to this one.
    _saveFailed = false;
    _notificationDenied = !notificationGranted;
    _notificationGranted = notificationGranted;
    _startedAt = _now().toUtc();
    _lastIndex = 0;
    _lastCountdownSecond = -1;

    _engine = TimerEngine(phases: preset.phases, clock: _now)..start();
    // Keeping the screen on and the sounds are capabilities: when one
    // fails, the timer still runs without it (ADR-4, ADR-6). A wakelock
    // failure threw out of here with the engine already set and no ticker,
    // so the timer counted as active, showed nothing moving, and the
    // caller said it could not start.
    await _bestEffort('wakelock.enable', _wakelock.enable);
    if (_disposed) return;
    await _bestEffort('audio.preload', _audio.preload);

    _ticker?.cancel();
    _ticker = Timer.periodic(_tickInterval, (_) => _tick());
    _tick();
    await _rescheduleBoundaries();
  }

  Future<void> pause() async {
    _engine?.pause();
    await _bestEffort('notifications.cancelAll', _notifications.cancelAll);
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
      // `_finish` handles its own failures; nothing awaits a tick.
      unawaited(_finish());
      return;
    }

    if (snapshot.isRunning) {
      _maybeCountdown(snapshot);
      _maybeTransition(snapshot);
    }
  }

  void _maybeCountdown(TimerSnapshot snapshot) {
    final int second = UnitFormatters.secondsRoundedUp(snapshot.remaining);
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
    // Already finished, or never started: nothing to end. A second call
    // (the last interval running out as End is pressed, or a tick and a
    // stop in the same frame) played the completion sound and haptic
    // again; only the session write was guarded, by its own null check.
    if (engine == null) return;
    _engine = null;

    // Read before any of the awaits below, which can run past this
    // notifier being disposed — `ref` itself becomes unusable at that
    // point, so the DAO has to be captured while it's still guaranteed
    // safe, or a session completed right as the screen closes would
    // silently never get written.
    final TimerDao dao = ref.read(timerDaoProvider);

    // The record first, then the effects, each on its own. The effects ran
    // first and a wakelock failure skipped the write; with the engine
    // already cleared, nothing could retry it, and the session was lost
    // without a word.
    try {
      await _writeSession(dao, engine);
    } catch (error, stackTrace) {
      reportError(error, stackTrace, context: 'TimerController.writeSession');
      _saveFailed = true;
    }

    await _bestEffort('wakelock.disable', _wakelock.disable);
    await _bestEffort('notifications.cancelAll', _notifications.cancelAll);

    // `ref.mounted`, not `_disposed`: this flag is set from an `onDispose`
    // callback and is not guaranteed to have landed yet at this exact point
    // (this was caught by a test disposing the container mid-await right
    // here — `_disposed` was still false while `ref` itself already
    // rejected reads). `ref.mounted` is Riverpod's own, always up to date.
    if (ref.mounted) {
      final TimerSettings settings = ref.read(timerSettingsControllerProvider);
      if (settings.hapticsEnabled) {
        final HapticsService haptics = ref.read(hapticsServiceProvider);
        await _bestEffort('haptics.heavy', haptics.heavy);
      }
      if (settings.soundEnabled && ref.mounted) {
        final TimerAudioService audio = ref.read(timerAudioServiceProvider);
        await _bestEffort('audio.complete', () => audio.cue(TimerCue.complete));
      }
    }

    await _bestEffort('audio.dispose', _audio.dispose);

    // Same reasoning as the `ref.mounted` check above: `_disposed` can still
    // read false here even though the element has already been torn down,
    // which throws on the assignment below rather than on a read.
    if (ref.mounted) state = null;
  }

  /// Runs a side effect whose failure must not stop the timer: it is
  /// logged and the caller carries on.
  Future<void> _bestEffort(String what, Future<void> Function() run) async {
    try {
      await run();
    } catch (error, stackTrace) {
      reportError(error, stackTrace, context: 'TimerController.$what');
    }
  }

  Future<void> _writeSession(TimerDao dao, TimerEngine? engine) async {
    if (engine == null) return;

    final DateTime endedAt = _now().toUtc();
    final int totalIntervals = _preset.totalIntervals;

    final TimerSnapshot finalSnapshot = engine.snapshot();
    // The time the timer ran: the engine's elapsed time, which pauses do
    // not add to, at most the planned length. It was the wall-clock span
    // from start to end, so a 4-minute timer paused for ten minutes was
    // saved, and shown on Home, as 14 minutes. Start and end stay as they
    // are: they are when the session happened.
    final int actualSeconds = finalSnapshot.elapsed.inSeconds;
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

    await dao.insertSession(
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

  /// Schedules the phase alerts. A failure is logged, not thrown: the
  /// alerts are a capability, and a timer that is running must not be
  /// reported as failed to start, pause or skip because one could not be
  /// scheduled.
  Future<void> _rescheduleBoundaries() =>
      _bestEffort('notifications.schedule', _scheduleBoundaries);

  Future<void> _scheduleBoundaries() async {
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
    final DateTime now = _now().toUtc();
    // `boundary` is the end of phase `index`, which is when phase `index + 1`
    // begins — so that is the phase the notification announces. The last
    // phase has no successor; its end is the timer finishing, not a boundary.
    // The phase that is running right now still needs its own end scheduled,
    // hence `<` rather than `<=` against the current index.
    for (var index = 0; index < _preset.phases.length - 1; index++) {
      boundary += Duration(seconds: _preset.phases[index].durationSeconds);
      if (index < snapshot.currentIndex) continue;
      final Duration untilBoundary = boundary - snapshot.elapsed;
      if (untilBoundary <= Duration.zero) continue;
      final TimerPhase nextPhase = _preset.phases[index + 1];
      await notifications.scheduleBoundary(
        id: 10000 + index,
        at: now.add(untilBoundary),
        title: l10n.timerNotificationTitle(nextPhase.type.label(l10n)),
        body: l10n.timerNotificationBody(nextPhase.type.label(l10n)),
      );
    }

    // The loop above announces each phase that *starts*, so the last
    // phase's end has no boundary of its own. Without this, a locked phone
    // is silent exactly when the session finishes.
    final Duration untilEnd =
        Duration(seconds: _preset.totalDurationSeconds) - snapshot.elapsed;
    if (untilEnd > Duration.zero) {
      await notifications.scheduleCompletion(
        at: now.add(untilEnd),
        title: l10n.timerCompletionNotificationTitle,
        body: l10n.timerCompletionNotificationBody,
      );
    }
  }

  void _dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _ticker = null;
    _engine = null;
    unawaited(_bestEffort('notifications.cancelAll', _notifications.cancelAll));
    unawaited(_bestEffort('wakelock.disable', _wakelock.disable));
    unawaited(_bestEffort('audio.dispose', _audio.dispose));
  }
}
