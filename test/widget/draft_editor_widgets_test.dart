import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/core/services/haptics_service.dart';
import 'package:ironyx/features/library/presentation/widgets/exercise_detail_sheet.dart';
import 'package:ironyx/features/tracker/domain/draft_editor_controller.dart';
import 'package:ironyx/features/tracker/domain/workout_draft.dart';
import 'package:ironyx/features/tracker/presentation/widgets/draft_editor_widgets.dart';
import 'package:ironyx/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CountingHaptics implements HapticsService {
  int impacts = 0;

  @override
  bool get isSupported => true;

  @override
  Future<void> selection() async {}

  @override
  Future<void> impact() async => impacts++;

  @override
  Future<void> heavy() async {}
}

void main() {
  Future<GlobalKey<_DraftHarnessState>> pumpHarness(
    WidgetTester tester, {
    Map<String, Object> prefs = const <String, Object>{},
    HapticsService haptics = const NoopHapticsService(),
    bool showPreviousPerformance = false,
    PreviousPerformance? previous,
    Locale locale = const Locale('en'),
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final preferences = await SharedPreferences.getInstance();
    final harnessKey = GlobalKey<_DraftHarnessState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          hapticsServiceProvider.overrideWithValue(haptics),
          previousPerformanceProvider('bench')
              .overrideWith((ref) => Stream.value(previous)),
          // The how-to sheet resolves to "not found" here; that is enough
          // to prove the card opened it for the right exercise.
          exerciseDetailProvider('bench').overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: _DraftHarness(
            key: harnessKey,
            showPreviousPerformance: showPreviousPerformance,
          ),
        ),
      ),
    );
    await tester.pump();
    return harnessKey;
  }

  testWidgets(
      'removing an exercise is a menu action, not a one-tap button beside it',
      (tester) async {
    final harnessKey = await pumpHarness(tester);

    expect(find.byTooltip('Remove Bench Press'), findsNothing);
    await tester.tap(find.byTooltip('Bench Press options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove Bench Press'));
    await tester.pumpAndSettle();

    expect(
      harnessKey.currentState!.controller.removedExerciseIds,
      <String>['exercise-row'],
    );
  });

  testWidgets('tapping the exercise name opens its how-to sheet',
      (tester) async {
    await pumpHarness(tester);

    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseDetailSheet), findsOneWidget);
    expect(find.text('Exercise not found'), findsOneWidget);
  });

  testWidgets('the options menu and set rows do not open the how-to sheet',
      (tester) async {
    await pumpHarness(tester);

    await tester.tap(find.byTooltip('Bench Press options'));
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseDetailSheet), findsNothing);
    await tester.tapAt(Offset.zero); // dismiss the menu
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsLabel(
        RegExp('Set 1.*(complete|done)', caseSensitive: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseDetailSheet), findsNothing);
  });

  group('last time', () {
    final PreviousPerformance previous = PreviousPerformance(
      date: DateTime(2026, 9, 12),
      sets: const <PreviousSet>[
        PreviousSet(weightKg: 80, reps: 8),
        PreviousSet(weightKg: 85, reps: 7),
      ],
    );

    testWidgets('shows the previous session\'s sets in a live workout',
        (tester) async {
      await pumpHarness(
        tester,
        showPreviousPerformance: true,
        previous: previous,
      );

      expect(
        find.text(
          'Last time (12 Sep): 80 kg × 8 · 85 kg × 7'.replaceAllMapped(
            // Each set is held together with non-breaking spaces.
            RegExp(r'(\d+) kg × (\d+)'),
            (m) => '${m[1]}\u00A0kg\u00A0×\u00A0${m[2]}',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('is off unless asked for (e.g. editing a past workout)',
        (tester) async {
      await pumpHarness(tester, previous: previous);

      expect(find.textContaining('Last time'), findsNothing);
    });

    testWidgets('shows nothing for an exercise with no history',
        (tester) async {
      await pumpHarness(tester, showPreviousPerformance: true);

      expect(find.textContaining('Last time'), findsNothing);
    });
  });

  group('Arabic (right-to-left)', () {
    final PreviousPerformance previous = PreviousPerformance(
      date: DateTime(2026, 10, 4),
      sets: const <PreviousSet>[PreviousSet(weightKg: 60, reps: 8)],
    );

    testWidgets('"last time" keeps each set as one left-to-right run',
        (tester) async {
      await pumpHarness(
        tester,
        locale: const Locale('ar'),
        showPreviousPerformance: true,
        previous: previous,
      );

      // Isolated, so the bidi algorithm cannot reorder it into "60 8 × kg".
      expect(
        find.textContaining('\u206660\u00A0kg\u00A0×\u00A08\u2069'),
        findsOneWidget,
      );
    });

    testWidgets('column headers stay on one line instead of breaking a word',
        (tester) async {
      await pumpHarness(tester, locale: const Locale('ar'));

      // "المجموعة" is wider than the digit-sized set column; it used to
      // wrap as "المجمو / عة". It must render at the same single-line
      // height as a header that fits.
      final double setHeader = tester.getSize(find.text('المجموعة')).height;
      final double repsHeader = tester.getSize(find.text('التكرارات')).height;
      expect(setHeader, lessThanOrEqualTo(repsHeader));
      expect(tester.takeException(), isNull);
    });
  });

  group('logging a set gives a haptic tick', () {
    Finder doneButton(int set) => find.bySemanticsLabel(
          RegExp('Set $set.*(complete|done)', caseSensitive: false),
        );

    testWidgets('when marked done, not when unmarked', (tester) async {
      final _CountingHaptics haptics = _CountingHaptics();
      await pumpHarness(tester, haptics: haptics);

      await tester.tap(doneButton(1));
      await tester.pump();
      expect(haptics.impacts, 1);

      await tester.tap(doneButton(1));
      await tester.pump();
      expect(haptics.impacts, 1);
    });

    testWidgets('never when haptics are switched off in Settings',
        (tester) async {
      final _CountingHaptics haptics = _CountingHaptics();
      await pumpHarness(
        tester,
        haptics: haptics,
        prefs: <String, Object>{'timer_haptics_enabled': false},
      );

      await tester.tap(doneButton(1));
      await tester.pump();
      expect(haptics.impacts, 0);
    });
  });

  testWidgets('an unlogged set is hollow and a logged one is filled',
      (tester) async {
    await pumpHarness(tester);
    final Finder button = find.bySemanticsLabel('Set 1 complete');
    Material box() => tester.widget<Material>(
          find.descendant(of: button, matching: find.byType(Material)).first,
        );
    BorderSide side() => (box().shape! as RoundedRectangleBorder).side;
    final ColorScheme scheme = Theme.of(tester.element(button)).colorScheme;

    // A grey fill used to read as "already done" at arm's length.
    expect(box().color, Colors.transparent);
    expect(side().color, scheme.outline);

    await tester.tap(button);
    await tester.pump();

    expect(box().color, scheme.primary);
    expect(side(), BorderSide.none);
  });

  testWidgets('deleting a middle set preserves neighboring edited values',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final harnessKey = GlobalKey<_DraftHarnessState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp(
          // The card reads `context.l10n`, so it needs the app's delegates.
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _DraftHarness(key: harnessKey),
        ),
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

  testWidgets(
      'a time-based exercise shows a duration column instead of reps, and '
      'entering a value updates durationSeconds not reps', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final harnessKey = GlobalKey<_DraftHarnessState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _DraftHarness(
            key: harnessKey,
            initial: const DraftExercise(
              id: 'exercise-row',
              exerciseId: 'plank',
              name: 'Plank',
              isTimeBased: true,
              sets: [DraftSet(id: 'set-1')],
            ),
          ),
        ),
      ),
    );

    expect(find.text('SEC'), findsOneWidget);
    expect(find.text('REPS'), findsNothing);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '45');
    await tester.pump(const Duration(milliseconds: 350));

    final exercise = harnessKey.currentState!.exercise;
    expect(exercise.sets.single.durationSeconds, 45);
    expect(exercise.sets.single.reps, 0);
  });

  testWidgets('a superset exercise shows its letter and a SUPERSET tag',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _DraftHarness(
            initial: DraftExercise(
              id: 'exercise-row',
              exerciseId: 'bench',
              name: 'Bench Press',
              supersetGroupId: 'g1',
              sets: [DraftSet(id: 'set-1')],
            ),
            supersetLabel: 'A',
            isInSuperset: true,
          ),
        ),
      ),
    );

    expect(find.text('SUPERSET'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
  });
}

class _DraftHarness extends StatefulWidget {
  const _DraftHarness({
    this.initial = _defaultInitial,
    this.supersetLabel,
    this.isInSuperset = false,
    this.showPreviousPerformance = false,
    super.key,
  });

  final bool showPreviousPerformance;

  static const DraftExercise _defaultInitial = DraftExercise(
    id: 'exercise-row',
    exerciseId: 'bench',
    name: 'Bench Press',
    sets: [
      DraftSet(id: 'set-1'),
      DraftSet(id: 'set-2'),
      DraftSet(id: 'set-3'),
    ],
  );

  final DraftExercise initial;
  final String? supersetLabel;
  final bool isInSuperset;

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
            supersetLabel: widget.supersetLabel,
            isInSuperset: widget.isInSuperset,
            showPreviousPerformance: widget.showPreviousPerformance,
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
    int? rpeTimes10,
    int? restSeconds,
    int? durationSeconds,
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
              rpeTimes10: rpeTimes10 ?? set.rpeTimes10,
              restSeconds: restSeconds ?? set.restSeconds,
              durationSeconds: durationSeconds ?? set.durationSeconds,
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
  Future<void> addExercise({
    required String exerciseId,
    required String name,
    bool isTimeBased = false,
  }) =>
      Future<void>.value();

  @override
  Future<void> removeExercise(String exerciseId) async =>
      removedExerciseIds.add(exerciseId);

  final List<String> removedExerciseIds = <String>[];

  @override
  Future<void> reorderExercise(String exerciseId, int newIndex) =>
      Future<void>.value();

  @override
  Future<void> groupWithPrevious(String exerciseId) => Future<void>.value();

  @override
  Future<void> ungroupFromSuperset(String exerciseId) => Future<void>.value();

  @override
  Future<void> addSet(String exerciseId) => Future<void>.value();

  @override
  Future<void> duplicateSet(String exerciseId, String setId) =>
      Future<void>.value();
}
