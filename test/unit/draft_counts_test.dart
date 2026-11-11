import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/features/dashboard/domain/dashboard_providers.dart';
import 'package:ironyx/features/tracker/domain/active_workout_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Home's start card shows an open draft's exercise and completed-set
/// counts, and should rebuild only when one of them changes.
void main() {
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  });

  tearDown(() => container.dispose());

  test('no draft is null', () {
    expect(draftCounts(null), isNull);
  });

  test('the card hears only changes to what it shows', () async {
    final List<DraftCounts?> heard = <DraftCounts?>[];
    container.listen(
      activeWorkoutProvider.select(draftCounts),
      (_, DraftCounts? next) => heard.add(next),
    );
    final notifier = container.read(activeWorkoutProvider.notifier);

    await notifier.start();
    await notifier.addExercise(exerciseId: 'squat', name: 'Squat');
    final String exerciseId =
        container.read(activeWorkoutProvider)!.exercises.single.id;
    await notifier.addSet(exerciseId);
    final String setId =
        container.read(activeWorkoutProvider)!.exercises.single.sets.last.id;
    final int before = heard.length;
    expect(heard.last, (exercises: 1, completedSets: 0));

    // Typing a weight and reps changes the draft but not the counts.
    await notifier.updateSet(exerciseId, setId, weightKg: 100);
    await notifier.updateSet(exerciseId, setId, reps: 5);
    expect(heard, hasLength(before), reason: 'no rebuild for typing');

    // Ticking the set does change them.
    await notifier.updateSet(exerciseId, setId, isCompleted: true);
    expect(heard.last, (exercises: 1, completedSets: 1));
    expect(heard, hasLength(before + 1));

    await notifier.discard();
    expect(heard.last, isNull);
  });
}
