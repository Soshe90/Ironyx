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

  // The dialog's text controllers used to be disposed as soon as
  // `showDialog` returned, while the dialog was still animating out with
  // both fields mounted. On a phone that showed up, some of the time, as a
  // full-screen "'_dependents.isEmpty': is not true" after pressing Save.
  group('RPE and rest time dialog', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Set 1 options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RPE and rest time'));
      await tester.pumpAndSettle();
      expect(find.text('Set 1 details'), findsOneWidget);
    }

    final Finder rpeField = find.widgetWithText(TextField, 'RPE (1–10)');
    final Finder restField =
        find.widgetWithText(TextField, 'Rest before set (seconds)');

    /// Types the way a soft keyboard does, leaving the text underlined as
    /// still being composed when the next tap lands.
    Future<void> typeComposing(
      WidgetTester tester,
      Finder field,
      String text,
    ) async {
      await tester.showKeyboard(field);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
          composing: TextRange(start: 0, end: text.length),
        ),
      );
      await tester.pump();
    }

    testWidgets('Save stores both values and closes without an error',
        (tester) async {
      final harnessKey = await pumpHarness(tester);
      await openDialog(tester);
      await tester.enterText(rpeField, '8.5');
      await typeComposing(tester, restField, '90');
      await tester.tap(find.text('Save'));

      // Frame by frame through the closing animation: the failure was a
      // rebuild in the middle of it, which a single settle could step over.
      for (int frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'frame $frame');
      }

      expect(find.text('Set 1 details'), findsNothing);
      final DraftSet saved = harnessKey.currentState!.exercise.sets.first;
      expect(saved.rpeTimes10, 85);
      expect(saved.restSeconds, 90);
    });

    testWidgets('Cancel closes without an error and changes nothing',
        (tester) async {
      final harnessKey = await pumpHarness(tester);
      await openDialog(tester);
      await typeComposing(tester, rpeField, '8');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Set 1 details'), findsNothing);
      final DraftSet set = harnessKey.currentState!.exercise.sets.first;
      expect(set.rpeTimes10, isNull);
      expect(set.restSeconds, isNull);
    });

    testWidgets('an out-of-range value keeps the dialog open and says why',
        (tester) async {
      final harnessKey = await pumpHarness(tester);
      await openDialog(tester);
      await tester.enterText(rpeField, '11');
      await tester.enterText(restField, '3601');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Set 1 details'), findsOneWidget);
      expect(
        find.text('Enter a number from 1 to 10, or leave it empty'),
        findsOneWidget,
      );
      expect(
        find.text('Enter 0 to 3600 seconds, or leave it empty'),
        findsOneWidget,
      );
      final DraftSet set = harnessKey.currentState!.exercise.sets.first;
      expect(set.rpeTimes10, isNull);
      expect(set.restSeconds, isNull);

      // Editing a field withdraws its own complaint and leaves the other.
      await tester.enterText(rpeField, '9');
      await tester.pump();
      expect(
        find.text('Enter a number from 1 to 10, or leave it empty'),
        findsNothing,
      );
      expect(
        find.text('Enter 0 to 3600 seconds, or leave it empty'),
        findsOneWidget,
      );

      await tester.enterText(restField, '3600');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Set 1 details'), findsNothing);
      final DraftSet saved = harnessKey.currentState!.exercise.sets.first;
      expect(saved.rpeTimes10, 90);
      expect(saved.restSeconds, 3600);
    });

    testWidgets('the edges of each range are accepted', (tester) async {
      final harnessKey = await pumpHarness(tester);
      await openDialog(tester);
      await tester.enterText(rpeField, '1');
      await tester.enterText(restField, '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final DraftSet saved = harnessKey.currentState!.exercise.sets.first;
      expect(saved.rpeTimes10, 10);
      expect(saved.restSeconds, 0);

      await openDialog(tester);
      await tester.enterText(rpeField, '0.9');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Set 1 details'), findsOneWidget);
      expect(harnessKey.currentState!.exercise.sets.first.rpeTimes10, 10);
    });

    testWidgets('text that is not a number is refused, not read as empty',
        (tester) async {
      final harnessKey = await pumpHarness(tester);
      await openDialog(tester);
      await tester.enterText(rpeField, '8');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      await openDialog(tester);
      await tester.enterText(rpeField, '8.5.5');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Set 1 details'), findsOneWidget);
      expect(
        find.text('Enter a number from 1 to 10, or leave it empty'),
        findsOneWidget,
      );
      expect(harnessKey.currentState!.exercise.sets.first.rpeTimes10, 80);
    });

    testWidgets('letters and signs cannot be typed into either field',
        (tester) async {
      await pumpHarness(tester);
      await openDialog(tester);
      // The comma is a decimal mark (see `NumberInputFormatter`); rest is a
      // whole number of seconds, so it has none.
      await tester.enterText(rpeField, '-7,5e');
      await tester.enterText(restField, '1.5m');

      expect(find.widgetWithText(TextField, '7.5'), findsOneWidget);
      expect(find.widgetWithText(TextField, '15'), findsOneWidget);
    });

    testWidgets('a decimal comma and Arabic digits are saved as typed',
        (tester) async {
      final harnessKey = await pumpHarness(tester);
      await openDialog(tester);
      await tester.enterText(rpeField, '٨٫٥');
      await tester.enterText(restField, '١٢٠');

      expect(find.widgetWithText(TextField, '8.5'), findsOneWidget);
      expect(find.widgetWithText(TextField, '120'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final DraftSet saved = harnessKey.currentState!.exercise.sets.first;
      expect(saved.rpeTimes10, 85);
      expect(saved.restSeconds, 120);
    });

    testWidgets('set rows take a decimal comma and Arabic digits',
        (tester) async {
      final harnessKey = await pumpHarness(tester);
      final Finder fields = find.byType(TextField);
      // Set 1: weight, then reps. Before, the comma was dropped as it was
      // typed and 82,5 was logged as 825 kg.
      await tester.enterText(fields.at(0), '82,5');
      await tester.enterText(fields.at(1), '٨');
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.widgetWithText(TextField, '82.5'), findsOneWidget);
      final DraftSet set = harnessKey.currentState!.exercise.sets.first;
      expect(set.weightKg, 82.5);
      expect(set.reps, 8);
    });

    testWidgets('emptying a field clears that value on the set',
        (tester) async {
      final harnessKey = await pumpHarness(tester);
      await openDialog(tester);
      await tester.enterText(rpeField, '8');
      await tester.enterText(restField, '90');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      await openDialog(tester);
      await tester.enterText(find.widgetWithText(TextField, '8.0'), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Set 1 details'), findsNothing);
      DraftSet set = harnessKey.currentState!.exercise.sets.first;
      expect(set.rpeTimes10, isNull);
      expect(set.restSeconds, 90,
          reason: 'the untouched field keeps its value');

      await openDialog(tester);
      await tester.enterText(find.widgetWithText(TextField, '90'), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      set = harnessKey.currentState!.exercise.sets.first;
      expect(set.rpeTimes10, isNull);
      expect(set.restSeconds, isNull);
    });

    testWidgets('saving details leaves the rest of the set alone',
        (tester) async {
      final harnessKey = await pumpHarness(tester);
      await tester.enterText(find.byType(TextField).at(0), '40');
      await tester.pump(const Duration(milliseconds: 350));
      await openDialog(tester);
      await tester.enterText(rpeField, '8');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final List<DraftSet> sets = harnessKey.currentState!.exercise.sets;
      expect(sets[0].weightKg, 40);
      expect(sets[0].rpeTimes10, 80);
      expect(sets[1].rpeTimes10, isNull);
    });

    testWidgets('the refusal is translated (Arabic)', (tester) async {
      await pumpHarness(tester, locale: const Locale('ar'));
      final AppLocalizations ar = lookupAppLocalizations(const Locale('ar'));
      await tester.tap(find.byTooltip(ar.draftSetOptionsSemantic(1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ar.draftRpeAndRest));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, ar.draftRpeField),
        '11',
      );
      await tester.tap(find.text(ar.actionSave));
      await tester.pumpAndSettle();

      expect(find.text(ar.draftRpeInvalid), findsOneWidget);
      expect(ar.draftRpeInvalid, isNot(contains('Enter')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('reopening shows what was saved', (tester) async {
      await pumpHarness(tester);
      await openDialog(tester);
      await tester.enterText(rpeField, '7');
      await tester.enterText(restField, '120');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      await openDialog(tester);
      expect(find.widgetWithText(TextField, '7.0'), findsOneWidget);
      expect(find.widgetWithText(TextField, '120'), findsOneWidget);
    });
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
  Future<void> replaceSetDetails(
    String exerciseId,
    String setId, {
    required int? rpeTimes10,
    required int? restSeconds,
  }) async {
    _ensureExercise(exerciseId);
    _exercise = _exercise!.copyWith(
      sets: [
        for (final set in _exercise!.sets)
          if (set.id == setId)
            set.copyWith(rpeTimes10: rpeTimes10, restSeconds: restSeconds)
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
