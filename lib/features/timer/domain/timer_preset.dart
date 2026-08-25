import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/l10n/l10n_extension.dart';

part 'timer_preset.freezed.dart';

/// Phase type within a timer preset.
///
/// Kept in the domain layer (rather than reusing the Drift enum) so the
/// engine and presets have no dependency on the database schema. The
/// controller maps this to `TimerIntervalType` when it writes a session.
enum TimerPhaseType { work, rest, prepare, cooldown }

extension TimerPhaseTypeX on TimerPhaseType {
  /// The phase name as the user sees it.
  ///
  /// Takes the localizations rather than reading a global: this is called
  /// both from the timer screen and from the notification scheduler, and the
  /// latter has no `BuildContext` (see `appLocalizationsProvider`).
  String label(AppLocalizations l10n) => switch (this) {
        TimerPhaseType.work => l10n.timerPhaseWork,
        TimerPhaseType.rest => l10n.timerPhaseRest,
        TimerPhaseType.prepare => l10n.timerPhasePrepare,
        TimerPhaseType.cooldown => l10n.timerPhaseCooldown,
      };
}

/// One immutable phase of a timer preset.
@freezed
abstract class TimerPhase with _$TimerPhase {
  const factory TimerPhase({
    required TimerPhaseType type,
    required int durationSeconds,
  }) = _TimerPhase;
}

/// An immutable, expandable interval-timer preset.
@freezed
abstract class TimerPreset with _$TimerPreset {
  const factory TimerPreset({
    required String id,
    required String name,
    required String description,
    required List<TimerPhase> phases,
  }) = _TimerPreset;
}

extension TimerPresetX on TimerPreset {
  int get totalDurationSeconds => phases.fold(
      0, (int sum, TimerPhase phase) => sum + phase.durationSeconds);

  int get totalIntervals => phases.length;
}

/// Built-in quick-start presets and the custom-builder factory.
abstract final class TimerPresets {
  static TimerPreset tabata() => TimerPreset(
        id: 'tabata',
        name: 'Tabata',
        description: '20s work / 10s rest × 8',
        phases: _rounds(8, workSeconds: 20, restSeconds: 10),
      );

  static TimerPreset hiit() => TimerPreset(
        id: 'hiit',
        name: 'HIIT',
        description: '30s work / 10s rest × 8',
        phases: _rounds(8, workSeconds: 30, restSeconds: 10),
      );

  static TimerPreset strength() => TimerPreset(
        id: 'strength',
        name: 'Strength',
        description: '60s work / 30s rest × 5',
        phases: _rounds(5, workSeconds: 60, restSeconds: 30),
      );

  static TimerPreset custom({
    required int workSeconds,
    required int restSeconds,
    required int rounds,
    int warmupSeconds = 0,
    int cooldownSeconds = 0,
  }) {
    return TimerPreset(
      id: 'custom',
      name: 'Custom',
      description: '$workSeconds s work / $restSeconds s rest × $rounds',
      phases: [
        if (warmupSeconds > 0)
          TimerPhase(
            type: TimerPhaseType.prepare,
            durationSeconds: warmupSeconds,
          ),
        ..._rounds(rounds, workSeconds: workSeconds, restSeconds: restSeconds),
        if (cooldownSeconds > 0)
          TimerPhase(
            type: TimerPhaseType.cooldown,
            durationSeconds: cooldownSeconds,
          ),
      ],
    );
  }

  static List<TimerPhase> _rounds(
    int count, {
    required int workSeconds,
    required int restSeconds,
  }) {
    return [
      for (var i = 0; i < count; i++) ...[
        TimerPhase(type: TimerPhaseType.work, durationSeconds: workSeconds),
        if (restSeconds > 0)
          TimerPhase(type: TimerPhaseType.rest, durationSeconds: restSeconds),
      ],
    ];
  }
}
