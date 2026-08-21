import 'timer_preset.dart';

/// A point-in-time view of the timer's state, recomputed from wall clock.
class TimerSnapshot {
  const TimerSnapshot({
    required this.currentIndex,
    required this.currentPhase,
    required this.remaining,
    required this.elapsed,
    required this.total,
    required this.progress,
    required this.isRunning,
    required this.isComplete,
  });

  /// Index of the current phase, or `-1` once complete.
  final int currentIndex;

  /// The phase currently running, or `null` once complete.
  final TimerPhase? currentPhase;

  /// Remaining time in the current phase.
  final Duration remaining;

  /// Total elapsed time across the session.
  final Duration elapsed;

  /// Total planned duration.
  final Duration total;

  /// Progress through the current phase, `0.0..1.0`.
  final double progress;

  final bool isRunning;
  final bool isComplete;
}

/// Wall-clock based interval timer engine (ADR-4).
///
/// The engine never accumulates time from ticks. It stores the elapsed time
/// at pause plus the wall-clock moment it was (re)started, and recomputes
/// every snapshot from `clock()`. This means a backgrounded phone — or a
/// simulated ten-minute gap in a test — simply lands on the correct phase
/// the next time a snapshot is read.
class TimerEngine {
  TimerEngine({
    required List<TimerPhase> phases,
    DateTime Function()? clock,
  })  : _phases = List<TimerPhase>.unmodifiable(phases),
        _clock = clock ?? DateTime.now;

  final List<TimerPhase> _phases;
  final DateTime Function() _clock;

  bool _running = false;
  Duration _accumulated = Duration.zero;
  DateTime? _lastResumeAt;

  Duration get totalDuration {
    var total = Duration.zero;
    for (final TimerPhase phase in _phases) {
      total += Duration(seconds: phase.durationSeconds);
    }
    return total;
  }

  bool get isRunning => _running;

  /// Elapsed session time, recomputed from the wall clock when running.
  Duration get elapsed {
    if (!_running) return _accumulated;
    return _accumulated + _clock().difference(_lastResumeAt!);
  }

  void start() {
    _accumulated = Duration.zero;
    _lastResumeAt = _clock();
    _running = true;
  }

  void pause() {
    if (!_running) return;
    _accumulated = elapsed;
    _lastResumeAt = null;
    _running = false;
  }

  void resume() {
    if (_running) return;
    _lastResumeAt = _clock();
    _running = true;
  }

  /// Skips the current phase by moving elapsed to the end of that phase.
  void skip() {
    final TimerSnapshot snapshot = this.snapshot();
    if (snapshot.isComplete) return;

    _accumulated = _phaseEnds[snapshot.currentIndex];
    _lastResumeAt = _running ? _clock() : null;
  }

  /// Recomputes the current phase and remaining time from the wall clock.
  TimerSnapshot snapshot() {
    final Duration nowElapsed = elapsed;
    final Duration total = totalDuration;

    if (_phases.isEmpty || nowElapsed >= total) {
      return TimerSnapshot(
        currentIndex: -1,
        currentPhase: null,
        remaining: Duration.zero,
        elapsed: nowElapsed >= total ? total : nowElapsed,
        total: total,
        progress: 1,
        isRunning: _running,
        isComplete: true,
      );
    }

    final List<Duration> ends = _phaseEnds;
    var index = 0;
    while (index < ends.length && nowElapsed >= ends[index]) {
      index++;
    }

    final TimerPhase phase = _phases[index];
    final Duration remaining = ends[index] - nowElapsed;
    final Duration phaseTotal = Duration(seconds: phase.durationSeconds);
    final double progress = phaseTotal.inMicroseconds == 0
        ? 0
        : 1 - (remaining.inMicroseconds / phaseTotal.inMicroseconds);

    return TimerSnapshot(
      currentIndex: index,
      currentPhase: phase,
      remaining: remaining,
      elapsed: nowElapsed,
      total: total,
      progress: progress.clamp(0.0, 1.0),
      isRunning: _running,
      isComplete: false,
    );
  }

  List<Duration> get _phaseEnds {
    final List<Duration> ends = <Duration>[];
    var cursor = Duration.zero;
    for (final TimerPhase phase in _phases) {
      cursor += Duration(seconds: phase.durationSeconds);
      ends.add(cursor);
    }
    return ends;
  }
}
