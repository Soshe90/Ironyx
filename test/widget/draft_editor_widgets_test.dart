import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/tracker/domain/draft_editor_controller.dart';
import 'package:fittrack/features/tracker/domain/workout_draft.dart';
import 'package:fittrack/features/tracker/presentation/widgets/draft_editor_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('deleting a middle set preserves neighboring edited values',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final harnessKey = GlobalKey<_DraftHarnessState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp(home: _DraftHarness(key: harnessKey)),
      ),
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '40');
    await tester.enterText(fields.at(4), '60');
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.byTooltip('Set 2 options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove set'));
    await tester.pumpAndSettle();

    final exercise = harnessKey.currentState!.exercise;
    expect(exercise.sets, hasLength(2));
    expect(exercise.sets[0].weightKg, 40);
    expect(exercise.sets[1].weightKg, 60);
    expect(find.byTooltip('Set 1 options'), findsOneWidget);
    expect(find.byTooltip('Set 2 options'), findsOneWidget);
  });
}

class _DraftHarness extends StatefulWidget {
  const _DraftHarness({super.key});

  final DraftExercise initial = const DraftExercise(
    id: 'exercise-row',
    exerciseId: 'bench',
    name: 'Bench Press',
    sets: [
      DraftSet(id: 'set-1'),
      DraftSet(id: 'set-2'),
      DraftSet(id: 'set-3'),
    ],
  );

  @override
  State<_DraftHarness> createState() => _DraftHarnessState();
}

class _DraftHarnessState extends State<_DraftHarness> {
  late DraftExercise exercise = widget.initial;
  late final _FakeController controller = _FakeController(_apply)
    ..initialize(widget.initial);

  void _apply(DraftExercise next) => setState(() => exercise = next);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SingleChildScrollView(
          child: ExerciseDraftCard(
            exercise: exercise,
            controller: controller,
          ),
        ),
      );
}

class _FakeController implements DraftEditorController {
  _FakeController(this.onChanged);

  final ValueChanged<DraftExercise> onChanged;

  DraftExercise? _exercise;

  DraftExercise get exercise => _exercise!;

  void initialize(DraftExercise exercise) => _exercise = exercise;

  void _ensureExercise(String id) {
    if (_exercise == null || _exercise!.id == id) return;
    throw StateError('Unexpected exercise $id');
  }

  @override
  Future<void> updateSet(
    String exerciseId,
    String setId, {
    double? weightKg,
    int? reps,
    bool? isCompleted,
    bool? isWarmup,
  }) async {
    _ensureExercise(exerciseId);
    final source = _exercise!;
    _exercise = source.copyWith(
      sets: [
        for (final set in source.sets)
          if (set.id == setId)
            set.copyWith(
              weightKg: weightKg ?? set.weightKg,
              reps: reps ?? set.reps,
              isCompleted: isCompleted ?? set.isCompleted,
              isWarmup: isWarmup ?? set.isWarmup,
            )
          else
            set,
      ],
    );
    onChanged(_exercise!);
  }

  @override
  Future<void> removeSet(String exerciseId, String setId) async {
    _ensureExercise(exerciseId);
    _exercise = _exercise!.copyWith(
      sets: _exercise!.sets.where((set) => set.id != setId).toList(),
    );
    onChanged(_exercise!);
  }

  @override
  Future<void> addExercise(
          {required String exerciseId, required String name}) =>
      Future<void>.value();

  @override
  Future<void> removeExercise(String exerciseId) => Future<void>.value();

  @override
  Future<void> reorderExercise(String exerciseId, int newIndex) =>
      Future<void>.value();

  @override
  Future<void> addSet(String exerciseId) => Future<void>.value();

  @override
  Future<void> duplicateSet(String exerciseId, String setId) =>
      Future<void>.value();
}
