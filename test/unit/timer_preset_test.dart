import 'package:fittrack/features/timer/domain/timer_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimerPresets', () {
    test('tabata is 8 rounds of 20s work / 10s rest', () {
      final TimerPreset preset = TimerPresets.tabata();
      expect(preset.totalIntervals, 16);
      expect(preset.totalDurationSeconds, 8 * 30);
      expect(preset.phases.first.type, TimerPhaseType.work);
      expect(preset.phases[1].type, TimerPhaseType.rest);
    });

    test('strength is 5 rounds of 60s work / 30s rest', () {
      final TimerPreset preset = TimerPresets.strength();
      expect(preset.totalIntervals, 10);
      expect(preset.totalDurationSeconds, 5 * 90);
    });

    test('hiit is 8 rounds of 30s work / 10s rest', () {
      final TimerPreset preset = TimerPresets.hiit();
      expect(preset.totalIntervals, 16);
      expect(preset.totalDurationSeconds, 8 * 40);
    });

    test('custom wraps rounds with optional warm-up and cool-down', () {
      final TimerPreset preset = TimerPresets.custom(
        workSeconds: 40,
        restSeconds: 20,
        rounds: 3,
        warmupSeconds: 60,
        cooldownSeconds: 30,
      );

      expect(preset.phases.first.type, TimerPhaseType.prepare);
      expect(preset.phases.last.type, TimerPhaseType.cooldown);
      expect(preset.totalIntervals, 1 + 3 * 2 + 1);
      expect(preset.totalDurationSeconds, 60 + 3 * 60 + 30);
    });

    test('custom omits zero-length warm-up and cool-down', () {
      final TimerPreset preset = TimerPresets.custom(
        workSeconds: 30,
        restSeconds: 15,
        rounds: 4,
      );

      expect(preset.phases.first.type, TimerPhaseType.work);
      expect(preset.phases.last.type, TimerPhaseType.rest);
      expect(preset.totalIntervals, 8);
    });
  });
}
