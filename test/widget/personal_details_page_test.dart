import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/body_metrics_dao.dart';
import 'package:ironyx/core/database/daos/profile_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/router/routes.dart';
import 'package:ironyx/core/widgets/app_card.dart';
import 'package:ironyx/features/profile/presentation/widgets/value_pill.dart';

import '../helpers/pump_app.dart';

void main() {
  late AppDatabase database;

  const Map<String, Object> seededPrefs = <String, Object>{
    'exercise_seed_version': 999999,
    'program_seed_version': 999999,
  };

  setUp(() {
    database = AppDatabase.forTesting();
  });

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await database.close();
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await pumpApp(
      tester,
      initialLocation: Routes.personalDetails,
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      prefs: seededPrefs,
      // Tall enough that the sticky Confirm bar and every row are on screen.
      surfaceSize: const Size(400, 1000),
    );
    await tester.pumpAndSettle();
  }

  /// The value pill on the row labelled [rowLabel].
  ///
  /// Anchored on `ValuePillRow` rather than the nearest `Row`: a row nests
  /// several of those, so a `Row` ancestor finder matches more than one and
  /// `tap` refuses to guess.
  Finder pillFor(String rowLabel) => find.descendant(
        of: find.ancestor(
          of: find.text(rowLabel),
          matching: find.byType(ValuePillRow),
        ),
        matching: find.byType(FilledButton),
      );

  /// Drives the numeric dialog behind the Weight / Height pills.
  Future<void> enterNumber(
    WidgetTester tester, {
    required String rowLabel,
    required String value,
  }) async {
    await tester.tap(pillFor(rowLabel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), value);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('saves the profile and logs the weight as a body metric',
      (tester) async {
    await pumpPage(tester);

    expect(find.text('Personal details'), findsOneWidget);
    final Finder nameField = find.widgetWithText(TextField, 'Name');
    expect(nameField, findsOneWidget);
    expect(
      find.ancestor(of: nameField, matching: find.byType(AppCard)),
      findsNothing,
    );

    await tester.enterText(
      nameField,
      'Mustafa Salih',
    );
    await enterNumber(tester, rowLabel: 'Height', value: '172');
    await enterNumber(tester, rowLabel: 'Weight', value: '94');

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    final profile = await ProfileDao(database).get();
    expect(profile!.displayName, 'Mustafa Salih');
    expect(profile.heightCm, 172);

    // Weight deliberately does NOT live on the profile: body_metrics_table
    // already owns weight-by-date and the Progress charts read from it.
    final metric = await BodyMetricsDao(database).getLatest();
    expect(metric!.weightKg, 94);

    await disposeApp(tester);
  });

  testWidgets('reloads what was saved instead of showing an empty form',
      (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mus');
    await enterNumber(tester, rowLabel: 'Height', value: '180');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    await disposeApp(tester);
    database = AppDatabase.forTesting();
    // Re-seed the same values into a fresh in-memory database, since the
    // first one is closed: this asserts the *form* renders stored values.
    await ProfileDao(database).upsert(
      const ProfilesTableCompanion(
        displayName: Value('Mus'),
        heightCm: Value(180),
      ),
    );

    await pumpPage(tester);
    expect(find.widgetWithText(TextField, 'Mus'), findsOneWidget);
    expect(find.text('180 cm'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('shows the plausibility note only once both values are set',
      (tester) async {
    await pumpPage(tester);

    // Nothing to advise on yet.
    expect(find.textContaining('overweight'), findsNothing);

    await enterNumber(tester, rowLabel: 'Height', value: '172');
    expect(find.textContaining('overweight'), findsNothing);

    await enterNumber(tester, rowLabel: 'Weight', value: '94');
    await tester.pumpAndSettle();
    expect(find.textContaining('overweight'), findsOneWidget);

    // Advisory only: Confirm must still commit.
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect((await ProfileDao(database).get())!.heightCm, 172);

    await disposeApp(tester);
  });

  testWidgets('rejects an out-of-range height rather than storing it',
      (tester) async {
    await pumpPage(tester);

    await tester.tap(pillFor('Height'));
    await tester.pumpAndSettle();
    // A slipped decimal — the exact mistake the range exists to catch.
    await tester.enterText(find.byType(TextFormField), '1720');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Enter a value between'), findsOneWidget);

    await disposeApp(tester);
  });
}
