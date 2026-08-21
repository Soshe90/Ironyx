import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../features/timer/domain/timer_preset.dart';

/// User-created interval timer presets.
///
/// Phases are stored as JSON so the domain model can evolve without coupling
/// the timer engine to Drift's generated row types.
class TimerPresetsTable extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get description => text()();

  TextColumn get phasesJson => text()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

String encodeTimerPhases(List<TimerPhase> phases) => jsonEncode([
      for (final phase in phases)
        {'type': phase.type.name, 'durationSeconds': phase.durationSeconds},
    ]);

List<TimerPhase> decodeTimerPhases(String value) {
  final decoded = jsonDecode(value) as List<dynamic>;

  return [
    for (final item in decoded)
      if (item is! Map<String, dynamic>)
        throw const FormatException('Invalid timer preset phase')
      else
        TimerPhase(
          type: TimerPhaseType.values.byName(item['type'] as String),
          durationSeconds: item['durationSeconds'] as int,
        ),
  ];
}
