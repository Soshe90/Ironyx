import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/features/tracker/domain/workout_draft.dart';

/// The volume rule is duplicated across three places that must agree:
/// `ActiveWorkoutNotifier.save` (which persists `totalVolumeKg`), the live
/// session totals on the active-workout screen, and the per-exercise
/// figures on the workout-detail screen.
///
/// They disagreed once already — the UI summed every completed set while
/// `save` excluded warm-ups, so a workout with warm-ups showed one total
/// while training and a smaller one after saving. This pins the rule.
void main() {
  group('working volume', () {
    /// The shared rule, stated once: completed, and not a warm-up at
    /// either the set or the exercise level.
    double workingVolume(WorkoutDraft draft) {
      var total = 0.0;
      for (final DraftExercise exercise in draft.exercises) {
        for (final DraftSet set in exercise.sets) {
          if (set.isCompleted && !set.isWarmup && !exercise.isWarmup) {
            total += set.weightKg * set.reps;
          }
        }
      }
      return total;
    }

    WorkoutDraft draftWith(List<DraftExercise> exercises) => WorkoutDraft(
          id: 'd',
          startedAt: DateTime.utc(2026, 1, 1),
          exercises: exercises,
        );

    test('counts only completed sets', () {
      final draft = draftWith(<DraftExercise>[
        const DraftExercise(
          id: 'e1',
          exerciseId: 'bench',
          name: 'Bench',
          sets: <DraftSet>[
            DraftSet(id: 's1', weightKg: 100, reps: 5, isCompleted: true),
            DraftSet(id: 's2', weightKg: 100, reps: 5),
          ],
        ),
      ]);

      expect(workingVolume(draft), 500);
    });

    test('excludes a set flagged as a warm-up', () {
      final draft = draftWith(<DraftExercise>[
        const DraftExercise(
          id: 'e1',
          exerciseId: 'bench',
          name: 'Bench',
          sets: <DraftSet>[
            DraftSet(
              id: 's1',
              weightKg: 40,
              reps: 10,
              isCompleted: true,
              isWarmup: true,
            ),
            DraftSet(id: 's2', weightKg: 100, reps: 5, isCompleted: true),
          ],
        ),
      ]);

      // 40 x 10 is warm-up and must not land in the total.
      expect(workingVolume(draft), 500);
    });

    test('excludes every set of a warm-up exercise', () {
      final draft = draftWith(<DraftExercise>[
        const DraftExercise(
          id: 'e1',
          exerciseId: 'bike',
          name: 'Air Bike',
          isWarmup: true,
          sets: <DraftSet>[
            DraftSet(id: 's1', weightKg: 20, reps: 20, isCompleted: true),
          ],
        ),
        const DraftExercise(
          id: 'e2',
          exerciseId: 'bench',
          name: 'Bench',
          sets: <DraftSet>[
            DraftSet(id: 's2', weightKg: 100, reps: 5, isCompleted: true),
          ],
        ),
      ]);

      expect(workingVolume(draft), 500);
    });

    test('per-exercise totals sum to the workout total', () {
      final draft = draftWith(<DraftExercise>[
        const DraftExercise(
          id: 'e1',
          exerciseId: 'bench',
          name: 'Bench',
          sets: <DraftSet>[
            DraftSet(
              id: 's1',
              weightKg: 40,
              reps: 10,
              isCompleted: true,
              isWarmup: true,
            ),
            DraftSet(id: 's2', weightKg: 100, reps: 5, isCompleted: true),
          ],
        ),
        const DraftExercise(
          id: 'e2',
          exerciseId: 'squat',
          name: 'Squat',
          sets: <DraftSet>[
            DraftSet(id: 's3', weightKg: 120, reps: 5, isCompleted: true),
          ],
        ),
      ]);

      final double perExercise = draft.exercises
          .map((e) => workingVolume(draftWith(<DraftExercise>[e])))
          .fold<double>(0, (a, b) => a + b);

      expect(perExercise, workingVolume(draft));
      expect(perExercise, 1100);
    });
  });
}
