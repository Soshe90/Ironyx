import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/body_metrics_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/database/tables/body_metrics.dart';
import 'package:ironyx/core/formatters/unit_formatters.dart';
import 'package:ironyx/features/progress/presentation/widgets/body_metric_widgets.dart';
import 'package:ironyx/l10n/app_localizations.dart';

const String _notANumber = 'Enter a number.';
const String _weightRangeKg = 'Enter a value between 25 and 350.';
const String _bodyFatRange = 'Enter a value between 2 and 70.';

/// The measurement dialog on Progress.
///
/// Two faults are pinned here. It used to dispose its text controllers as
/// soon as `showDialog` returned, while it was still animating out with the
/// fields mounted (see the matching tests for the set details dialog in
/// `draft_editor_widgets_test.dart`). And it used to close on Save whatever
/// the fields held, storing nothing for a weight it could not use and
/// anything at all for one it could.
void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase.forTesting());
  tearDown(() => database.close());

  Future<List<BodyMetricsTableData>> stored() =>
      database.select(database.bodyMetricsTable).get();

  Future<void> openEditor(
    WidgetTester tester, {
    WeightUnit unit = WeightUnit.kg,
    BodyMetrics? entry,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showBodyMetricEditor(
                  context,
                  ref,
                  unit: unit,
                  entry: entry,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  }

  Finder weightField([String unit = 'kg']) =>
      find.widgetWithText(TextFormField, 'Weight ($unit)');
  final Finder bodyFatField =
      find.widgetWithText(TextFormField, 'Body fat % (optional)');

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  /// Types into the focused field the way a soft keyboard does, leaving the
  /// text underlined as still being composed.
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

  group('closing', () {
    testWidgets('Save closes the dialog cleanly and stores the measurement',
        (tester) async {
      await openEditor(tester);
      await typeComposing(tester, weightField(), '82.5');
      await tester.enterText(bodyFatField, '18');
      await tester.tap(find.text('Save'));

      // Frame by frame through the closing animation: the failure was a
      // rebuild in the middle of it, which a single settle could step over.
      for (int frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'frame $frame');
      }

      expect(find.byType(AlertDialog), findsNothing);
      final rows = await stored();
      expect(rows, hasLength(1));
      expect(rows.single.weightKg, 82.5);
      expect(rows.single.bodyFatPercentage, 18);
    });

    testWidgets('Cancel closes the dialog cleanly and stores nothing',
        (tester) async {
      await openEditor(tester);
      await typeComposing(tester, weightField(), '82.5');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(await stored(), isEmpty);
    });

    testWidgets('Cancel after a refused Save still stores nothing',
        (tester) async {
      await openEditor(tester);
      await tester.enterText(weightField(), '9999');
      await save(tester);
      expect(find.text(_weightRangeKg), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(await stored(), isEmpty);
    });
  });

  group('weight', () {
    testWidgets('an empty weight keeps the dialog open and says why',
        (tester) async {
      await openEditor(tester);
      await save(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(_notANumber), findsOneWidget);
      expect(await stored(), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the message goes as soon as the field is put right',
        (tester) async {
      await openEditor(tester);
      await save(tester);
      expect(find.text(_notANumber), findsOneWidget);

      await tester.enterText(weightField(), '80');
      await tester.pump();
      expect(find.text(_notANumber), findsNothing);

      await save(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect((await stored()).single.weightKg, 80);
    });

    testWidgets('nothing complains while the form is first being filled in',
        (tester) async {
      await openEditor(tester);
      await tester.enterText(weightField(), '8');
      await tester.pump();

      expect(find.text(_weightRangeKg), findsNothing);
    });

    for (final String bad in <String>['0', '24.99', '350.01', '825', '-80']) {
      testWidgets('$bad kg is refused as out of range', (tester) async {
        await openEditor(tester);
        await tester.enterText(weightField(), bad);
        await save(tester);

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(_weightRangeKg), findsOneWidget);
        expect(await stored(), isEmpty);
      });
    }

    for (final String bad in <String>['8..5', '82,5', 'abc', 'NaN', '1e999']) {
      testWidgets('"$bad" is refused as not a number', (tester) async {
        await openEditor(tester);
        await tester.enterText(weightField(), bad);
        await save(tester);

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(_notANumber), findsOneWidget);
        expect(await stored(), isEmpty);
      });
    }

    for (final (String text, double kg) in <(String, double)>[
      ('25', 25),
      ('350', 350),
      (' 80.5 ', 80.5),
    ]) {
      testWidgets('"$text" kg is accepted', (tester) async {
        await openEditor(tester);
        await tester.enterText(weightField(), text);
        await save(tester);

        expect(find.byType(AlertDialog), findsNothing);
        expect((await stored()).single.weightKg, kg);
      });
    }

    testWidgets('pounds are checked in pounds and stored in kilograms',
        (tester) async {
      await openEditor(tester, unit: WeightUnit.lb);
      await tester.enterText(weightField('lb'), '55');
      await save(tester);

      // The same 25 to 350 kg, quoted in the unit being typed.
      expect(
        find.text('Enter a value between 55.11 and 771.62.'),
        findsOneWidget,
      );
      expect(await stored(), isEmpty);

      // The limit the message quotes is itself accepted.
      await tester.enterText(weightField('lb'), '55.11');
      await save(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect((await stored()).single.weightKg, closeTo(25, 0.01));
    });

    testWidgets('the upper limit quoted in pounds is accepted too',
        (tester) async {
      await openEditor(tester, unit: WeightUnit.lb);
      await tester.enterText(weightField('lb'), '771.62');
      await save(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect((await stored()).single.weightKg, closeTo(350, 0.01));
    });
  });

  group('body fat', () {
    testWidgets('left empty, it is stored as not measured', (tester) async {
      await openEditor(tester);
      await tester.enterText(weightField(), '80');
      await save(tester);

      expect((await stored()).single.bodyFatPercentage, isNull);
    });

    for (final String bad in <String>['1.99', '70.01', '0', '825']) {
      testWidgets('$bad % is refused as out of range', (tester) async {
        await openEditor(tester);
        await tester.enterText(weightField(), '80');
        await tester.enterText(bodyFatField, bad);
        await save(tester);

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(_bodyFatRange), findsOneWidget);
        expect(find.text(_weightRangeKg), findsNothing);
        expect(await stored(), isEmpty);
      });
    }

    testWidgets('text that is not a number is refused, not read as empty',
        (tester) async {
      await openEditor(tester);
      await tester.enterText(weightField(), '80');
      await tester.enterText(bodyFatField, '1.8.5');
      await save(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(_notANumber), findsOneWidget);
      expect(await stored(), isEmpty);
    });

    for (final String good in <String>['2', '70', '18.5']) {
      testWidgets('$good % is accepted', (tester) async {
        await openEditor(tester);
        await tester.enterText(weightField(), '80');
        await tester.enterText(bodyFatField, good);
        await save(tester);

        expect(find.byType(AlertDialog), findsNothing);
        expect(
          (await stored()).single.bodyFatPercentage,
          double.parse(good),
        );
      });
    }

    testWidgets('both fields can be wrong at once, each with its own message',
        (tester) async {
      await openEditor(tester);
      await tester.enterText(bodyFatField, '90');
      await save(tester);

      expect(find.text(_notANumber), findsOneWidget);
      expect(find.text(_bodyFatRange), findsOneWidget);
    });
  });

  group('editing an entry', () {
    final DateTime day = DateTime.utc(2026, 10, 30);

    Future<BodyMetrics> seed({
      required double weightKg,
      double? bodyFat,
    }) async {
      await BodyMetricsDao(database).upsert(
        BodyMetricsTableCompanion.insert(
          id: 'm1',
          date: day,
          weightKg: weightKg,
          bodyFatPercentage: Value(bodyFat),
        ),
      );
      return BodyMetrics.fromDrift((await stored()).single);
    }

    testWidgets('shows what is stored and saves over the same row',
        (tester) async {
      final BodyMetrics entry = await seed(weightKg: 82.5, bodyFat: 18);
      await openEditor(tester, entry: entry);

      expect(find.text('Edit measurement'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '82.5'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '18'), findsOneWidget);

      await tester.enterText(weightField(), '81');
      await save(tester);

      final rows = await stored();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'm1');
      expect(rows.single.date.isAtSameMomentAs(day), isTrue);
      expect(rows.single.weightKg, 81);
      expect(rows.single.bodyFatPercentage, 18);
    });

    testWidgets('emptying body fat clears it', (tester) async {
      final BodyMetrics entry = await seed(weightKg: 82.5, bodyFat: 18);
      await openEditor(tester, entry: entry);
      await tester.enterText(bodyFatField, '');
      await save(tester);

      final row = (await stored()).single;
      expect(row.weightKg, 82.5);
      expect(row.bodyFatPercentage, isNull);
    });

    testWidgets('a refused edit leaves the stored row as it was',
        (tester) async {
      final BodyMetrics entry = await seed(weightKg: 82.5, bodyFat: 18);
      await openEditor(tester, entry: entry);
      await tester.enterText(weightField(), '');
      await save(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      final row = (await stored()).single;
      expect(row.weightKg, 82.5);
      expect(row.bodyFatPercentage, 18);
    });

    testWidgets(
        'a row from outside the limits opens, and must be corrected to save',
        (tester) async {
      // What a restored backup or an older build can have left behind.
      final BodyMetrics entry = await seed(weightKg: 825, bodyFat: 180);
      await openEditor(tester, entry: entry);

      expect(find.widgetWithText(TextFormField, '825'), findsOneWidget);
      await save(tester);
      expect(find.text(_weightRangeKg), findsOneWidget);
      expect(find.text(_bodyFatRange), findsOneWidget);
      expect((await stored()).single.weightKg, 825);

      await tester.enterText(weightField(), '82.5');
      await tester.enterText(bodyFatField, '18');
      await save(tester);

      expect(find.byType(AlertDialog), findsNothing);
      final row = (await stored()).single;
      expect(row.weightKg, 82.5);
      expect(row.bodyFatPercentage, 18);
    });
  });

  testWidgets('the refusal is translated (Arabic)', (tester) async {
    await openEditor(tester, locale: const Locale('ar'));
    final AppLocalizations ar = lookupAppLocalizations(const Locale('ar'));
    await tester.enterText(
      find.widgetWithText(TextFormField, ar.progressBodyFatOptionalField),
      '90',
    );
    await tester.tap(find.text(ar.actionSave));
    await tester.pumpAndSettle();

    expect(find.text(ar.profileEnterANumber), findsOneWidget);
    expect(find.text(ar.profileEnterValueBetween('2', '70')), findsOneWidget);
    expect(ar.profileEnterANumber, isNot(_notANumber));
    expect(tester.takeException(), isNull);
    expect(await stored(), isEmpty);
  });

  testWidgets('both messages fit on a small phone with the keyboard up',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.reset);

    await openEditor(tester);
    await tester.enterText(bodyFatField, '90');
    await save(tester);

    expect(find.text(_notANumber), findsOneWidget);
    // A layout overflow would be reported here as an exception.
    expect(tester.takeException(), isNull);
  });
}
