import 'package:fittrack/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Confirms the indexes ADR-1's query paths depend on actually land in the
/// generated SQLite schema, rather than trusting the migration source alone.
void main() {
  test('a freshly created database has the expected indexes', () async {
    final database = AppDatabase.forTesting();

    final rows = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index'",
        )
        .get();
    final indexNames = {for (final row in rows) row.read<String>('name')};

    const expected = {
      'idx_workouts_started_at',
      'idx_workout_exercises_workout_id',
      'idx_workout_exercises_exercise_id',
      'idx_workout_sets_workout_exercise_id',
      'idx_workout_sets_exercise_set_index',
      'idx_program_templates_program_id',
      'idx_program_templates_template_id',
      'idx_template_exercises_template_id',
      'idx_template_exercises_exercise_id',
      'idx_timer_intervals_session_id',
      'idx_body_metrics_date',
    };
    expect(indexNames.containsAll(expected), isTrue,
        reason: 'missing: ${expected.difference(indexNames)}');

    await database.close();
  });
}
