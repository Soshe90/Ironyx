import 'package:fittrack/features/timer/domain/timer_engine.dart';
import 'package:fittrack/features/timer/domain/timer_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimerEngine', () {
    test('starts at the first phase with full remaining time', () {
      final DateTime now = DateTime(2024, 1, 1);
      final engine = TimerEngine(
        phases: [
          const TimerPhase(type: TimerPhaseType.work, durationSeconds: 20),
        ],
        clock: () => now,
      );

      engine.start();

      final TimerSnapshot snapshot = engine.snapshot();
      expect(snapshot.currentIndex, 0);
      expect(snapshot.remaining, const Duration(seconds: 20));
      expect(snapshot.isRunning, isTrue);
      expect(snapshot.isComplete, isFalse);
    });

    test('pause freezes remaining and resume continues from there', () {
      var now = DateTime(2024, 1, 1, 0, 0, 0);
      final engine = TimerEngine(
        phases: [
          const TimerPhase(type: TimerPhaseType.work, durationSeconds: 60)
        ],
        clock: () => now,
      );

      engine.start();
      now = now.add(const Duration(seconds: 10));
      engine.pause();
      expect(engine.snapshot().remaining, const Duration(seconds: 50));

      // While paused, wall-clock time passes but the timer does not.
      now = now.add(const Duration(minutes: 5));
      expect(engine.snapshot().remaining, const Duration(seconds: 50));

      engine.resume();
      now = now.add(const Duration(seconds: 20));
      expect(engine.snapshot().remaining, const Duration(seconds: 30));
    });

    test('a background gap skips multiple phases by wall clock', () {
      var now = DateTime(2024, 1, 1, 0, 0, 0);
      final engine = TimerEngine(
        phases: [
          const TimerPhase(type: TimerPhaseType.work, durationSeconds: 20),
          const TimerPhase(type: TimerPhaseType.rest, durationSeconds: 10),
          const TimerPhase(type: TimerPhaseType.work, durationSeconds: 20),
        ],
        clock: () => now,
      );

      engine.start();

      // 35s elapsed: 20s work + 10s rest + 5s into the third phase.
      now = now.add(const Duration(seconds: 35));
      final TimerSnapshot snapshot = engine.snapshot();
      expect(snapshot.currentIndex, 2);
      expect(snapshot.remaining, const Duration(seconds: 15));
      expect(snapshot.isComplete, isFalse);
    });

    test('a gap longer than the session marks it complete', () {
      var now = DateTime(2024, 1, 1, 0, 0, 0);
      final engine = TimerEngine(
        phases: [
          const TimerPhase(type: TimerPhaseType.work, durationSeconds: 20),
          const TimerPhase(type: TimerPhaseType.rest, durationSeconds: 10),
        ],
        clock: () => now,
      );

      engine.start();
      now = now.add(const Duration(minutes: 10));

      final TimerSnapshot snapshot = engine.snapshot();
      expect(snapshot.isComplete, isTrue);
      expect(snapshot.currentIndex, -1);
    });

    test('skip advances to the next phase', () {
      final DateTime now = DateTime(2024, 1, 1);
      final engine = TimerEngine(
        phases: [
          const TimerPhase(type: TimerPhaseType.work, durationSeconds: 20),
          const TimerPhase(type: TimerPhaseType.rest, durationSeconds: 10),
        ],
        clock: () => now,
      );

      engine.start();
      engine.skip();

      final TimerSnapshot snapshot = engine.snapshot();
      expect(snapshot.currentIndex, 1);
      expect(snapshot.currentPhase?.type, TimerPhaseType.rest);
      expect(snapshot.remaining, const Duration(seconds: 10));
    });

    test('progress runs from 0 to 1 within a phase', () {
      var now = DateTime(2024, 1, 1);
      final engine = TimerEngine(
        phases: [
          const TimerPhase(type: TimerPhaseType.work, durationSeconds: 10)
        ],
        clock: () => now,
      );

      engine.start();
      expect(engine.snapshot().progress, 0);

      now = now.add(const Duration(seconds: 5));
      expect(engine.snapshot().progress, closeTo(0.5, 0.001));

      now = now.add(const Duration(seconds: 5));
      expect(engine.snapshot().isComplete, isTrue);
    });
  });
}
