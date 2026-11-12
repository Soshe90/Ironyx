import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/formatters/unit_formatters.dart';
import 'package:ironyx/core/services/workout_xlsx_import_service.dart';
import 'package:ironyx/features/tracker/presentation/widgets/workout_xlsx_import_action.dart';
import 'package:ironyx/l10n/app_localizations.dart';

/// The XLSX import's confirm dialog body.
void main() {
  WorkoutXlsxImportResult result(List<DateTime> dates) =>
      WorkoutXlsxImportResult(
        workouts: <ImportedHistoricalWorkout>[
          for (final DateTime d in dates)
            ImportedHistoricalWorkout(
              date: d,
              exercises: <ImportedHistoricalExercise>[
                ImportedHistoricalExercise(
                  exerciseId: 'bench',
                  name: 'Bench',
                  sets: const <ImportedHistoricalSet>[
                    ImportedHistoricalSet(reps: 5, weightKg: 60),
                  ],
                ),
              ],
            ),
        ],
        unknownExercises: const <String>[],
        totalSets: dates.length,
      );

  Future<String> summaryIn(
    WidgetTester tester,
    Locale locale,
    WorkoutXlsxImportResult r,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: WorkoutXlsxImportPreview(
            result: r,
            sourceUnit: WeightUnit.kg,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<Text>(find.byType(Text).first).data!;
  }

  // The workbook's dates arrive as UTC midnight.
  final WorkoutXlsxImportResult range =
      result(<DateTime>[DateTime.utc(2026, 8, 24), DateTime.utc(2026, 11, 4)]);

  testWidgets('dates read as dates, not ISO strings', (tester) async {
    final String text = await summaryIn(tester, const Locale('en'), range);

    expect(text, isNot(contains('2026-08-24')));
    expect(text, contains('24 Aug 2026'));
    expect(text, contains('4 Nov 2026'));
  });

  testWidgets('and in Arabic, in Arabic', (tester) async {
    final String text = await summaryIn(tester, const Locale('ar'), range);

    expect(text, isNot(contains('2026-11-04')));
    expect(text, contains('نوفمبر'));
  });

  testWidgets('with nothing to import it says there are no dates',
      (tester) async {
    final String text =
        await summaryIn(tester, const Locale('en'), result(const []));

    expect(text, contains('0 workouts'));
    expect(text, contains('No dates'));
  });
}
