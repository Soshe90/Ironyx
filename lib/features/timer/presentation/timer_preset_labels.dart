import '../../../core/l10n/l10n_extension.dart';
import '../domain/timer_preset.dart';

/// Display names and descriptions for timer presets.
///
/// Presets are persisted with the name they were created under, so the
/// stored string cannot be the translated one — a preset saved in Arabic
/// would still read Arabic after switching the app to English. Instead the
/// built-ins are looked up by their stable [TimerPreset.id] and everything
/// else falls back to whatever the user typed, which is already in their
/// language because they wrote it.
extension TimerPresetL10n on TimerPreset {
  String displayName(AppLocalizations l10n) => switch (id) {
        // Both are the accepted names for these protocols in Arabic too, so
        // they are deliberately not translated.
        'tabata' => 'Tabata',
        'hiit' => 'HIIT',
        'strength' => l10n.timerPresetStrength,
        'custom' => l10n.timerCustomTitle,
        _ => name,
      };

  /// `20s work / 10s rest × 8`, rebuilt from the phases rather than read
  /// from [description].
  ///
  /// The stored description was written in whatever language was active when
  /// the preset was saved. Deriving it means the summary always matches the
  /// current language, and it stays correct if a preset is ever edited.
  String displayDescription(AppLocalizations l10n) {
    final int work = _firstDuration(TimerPhaseType.work);
    final int rest = _firstDuration(TimerPhaseType.rest);
    final int rounds =
        phases.where((TimerPhase p) => p.type == TimerPhaseType.work).length;

    // A preset with no work phase is not something the builder can produce,
    // but a row from a future version might be. Fall back rather than render
    // "0s work".
    if (work == 0 || rounds == 0) return description;
    return l10n.timerPresetFormula(work, rest, rounds);
  }

  int _firstDuration(TimerPhaseType type) {
    for (final TimerPhase phase in phases) {
      if (phase.type == type) return phase.durationSeconds;
    }
    return 0;
  }
}
