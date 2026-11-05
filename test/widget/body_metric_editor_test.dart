import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/formatters/unit_formatters.dart';
import 'package:ironyx/features/progress/presentation/widgets/body_metric_widgets.dart';
import 'package:ironyx/l10n/app_localizations.dart';

/// The measurement dialog used to dispose its text controllers as soon as
/// `showDialog` returned, while the dialog was still animating out with the
/// fields mounted. See the matching tests for the set details dialog in
/// `draft_editor_widgets_test.dart`.
void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase.forTesting());
  tearDown(() => database.close());

  Future<void> openEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () =>
                    showBodyMetricEditor(context, ref, unit: WeightUnit.kg),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Log measurement'), findsOneWidget);
  }

  /// Types into the focused field the way a soft keyboard does, leaving the
  /// text underlined as still being composed.
  Future<void> typeComposing(WidgetTester tester, Finder field, String text) {
    return tester.showKeyboard(field).then((_) async {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
          composing: TextRange(start: 0, end: text.length),
        ),
      );
      await tester.pump();
    });
  }

  testWidgets('Save closes the dialog cleanly and stores the measurement',
      (tester) async {
    await openEditor(tester);
    await typeComposing(
      tester,
      find.widgetWithText(TextField, 'Weight (kg)'),
      '82.5',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Body fat % (optional)'),
      '18',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Log measurement'), findsNothing);
    final rows = await database.select(database.bodyMetricsTable).get();
    expect(rows, hasLength(1));
    expect(rows.single.weightKg, 82.5);
    expect(rows.single.bodyFatPercentage, 18);
  });

  testWidgets('Cancel closes the dialog cleanly and stores nothing',
      (tester) async {
    await openEditor(tester);
    await typeComposing(
      tester,
      find.widgetWithText(TextField, 'Weight (kg)'),
      '82.5',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(await database.select(database.bodyMetricsTable).get(), isEmpty);
  });

  testWidgets('Save with no usable weight stores nothing', (tester) async {
    await openEditor(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(await database.select(database.bodyMetricsTable).get(), isEmpty);
  });
}
