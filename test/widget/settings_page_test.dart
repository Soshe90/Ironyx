import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/database_providers.dart';
import 'package:fittrack/core/formatters/unit_formatters.dart';
import 'package:fittrack/core/formatters/weight_unit_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  group('SettingsPage', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.forTesting();
    });

    tearDown(() async {
      await database.close();
    });

    testWidgets('choosing pounds persists the weight unit preference',
        (tester) async {
      await pumpApp(
        tester,
        initialLocation: '/settings',
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      await tester.pumpAndSettle();

      // Units sits below the fold at the test surface size, and lazily-built
      // list children have no element to scroll to until they are reached —
      // same reason the delete-all test below scrolls rather than tapping
      // blind. Every row added to the Account card above pushes this further
      // down, so the scroll is what keeps the test about units.
      await tester.scrollUntilVisible(
        find.text('Pounds (lb)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Kilograms (kg)'), findsOneWidget);
      await tester.tap(find.text('Pounds (lb)'));
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.text('Pounds (lb)'));
      final WeightUnit unit = ProviderScope.containerOf(context).read(
        weightUnitControllerProvider,
      );
      expect(unit, WeightUnit.lb);
    });

    testWidgets(
        'delete-all confirm button stays disabled until DELETE is typed',
        (tester) async {
      await pumpApp(
        tester,
        initialLocation: '/settings',
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      await tester.pumpAndSettle();

      // Data is the last group on the page and sits below the fold at the
      // test surface size. `scrollUntilVisible` rather than `ensureVisible`:
      // the latter needs the widget to already exist, and this ListView
      // builds lazily, so anything far enough down the page has no element
      // to make visible yet. That made the test brittle to any section
      // added above it — the Account card duly broke it.
      await tester.scrollUntilVisible(
        find.text('Delete all data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();

      final FilledButton confirmButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete everything'),
      );
      expect(confirmButton.onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pumpAndSettle();

      final FilledButton enabledButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete everything'),
      );
      expect(enabledButton.onPressed, isNotNull);
    });
  });
}
