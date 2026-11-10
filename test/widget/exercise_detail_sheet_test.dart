import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/features/library/presentation/widgets/exercise_detail_sheet.dart';
import 'package:ironyx/l10n/app_localizations.dart';

/// The shared tap target and the sheet's non-happy states. The happy path
/// against a real database lives in exercise_how_to_test.dart.
void main() {
  Future<void> pumpTarget(
    WidgetTester tester, {
    required Future<ExerciseDetail?> Function() load,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseDetailProvider('bench').overrideWith((ref) => load()),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Center(
              child: ExerciseInfoTapTarget(
                exerciseId: 'bench',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('Bench Press'),
                    ExerciseInfoIcon(exerciseName: 'Bench Press'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('an exercise that no longer exists shows not-found, not a crash',
      (tester) async {
    // e.g. an old workout referencing a since-deleted custom exercise.
    await pumpTarget(tester, load: () async => null);

    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseDetailSheet), findsOneWidget);
    expect(find.text('Exercise not found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed load shows an error with a working retry',
      (tester) async {
    int calls = 0;
    await pumpTarget(
      tester,
      load: () async {
        calls++;
        throw StateError('database is locked');
      },
    );

    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load exercises'), findsOneWidget);
    // Compared, not pinned: Riverpod may also retry on its own schedule.
    final int before = calls;
    expect(before, greaterThanOrEqualTo(1));

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(calls, greaterThan(before));
    expect(find.text('Failed to load exercises'), findsOneWidget);
  });

  testWidgets('a quick double tap never stacks two sheets', (tester) async {
    await pumpTarget(tester, load: () async => null);

    // A real second tap arrives at least a frame later, by which time the
    // first sheet's modal barrier is up. It takes the tap (standard modal
    // behaviour: a barrier tap dismisses), so the target underneath can't
    // open a second sheet on top of the first.
    await tester.tap(find.text('Bench Press'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Bench Press'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      find.byType(ExerciseDetailSheet).evaluate().length,
      lessThanOrEqualTo(1),
    );
  });

  testWidgets('the target is at least the minimum tap size', (tester) async {
    await pumpTarget(tester, load: () async => null);

    expect(
      tester.getSize(find.byType(ExerciseInfoTapTarget)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('announces its purpose in Arabic under the Arabic locale',
      (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpTarget(
      tester,
      load: () async => null,
      locale: const Locale('ar'),
    );

    expect(
      tester.getSemantics(find.byType(ExerciseInfoTapTarget)),
      isSemantics(
        isButton: true,
        hasTapAction: true,
        label: 'Bench Press\nطريقة أداء Bench Press',
      ),
    );

    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    expect(find.text('التمرين غير موجود'), findsOneWidget);

    semantics.dispose();
  });
}
