import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/core/services/program_import_service.dart';
import 'package:ironyx/features/programs/presentation/program_import_action.dart';
import 'package:ironyx/l10n/app_localizations.dart';

/// Stands in for the real service so the dialog flow can be driven without
/// a file picker or a database round trip.
class _FakeImportService extends ProgramImportService {
  _FakeImportService({this.result, this.parseError, this.applyError});

  final ProgramImportResult? result;
  final Object? parseError;
  final Object? applyError;
  int applyCalls = 0;

  @override
  Future<ProgramImportResult> parse(String csvText, AppDatabase db) async {
    if (parseError != null) throw parseError!;
    return result!;
  }

  @override
  Future<void> apply(AppDatabase db, ProgramImportResult result) async {
    applyCalls++;
    if (applyError != null) throw applyError!;
  }
}

const ProgramImportResult _oneProgram = ProgramImportResult(
  programs: [
    ImportedProgram(
      name: 'Mine',
      days: [
        ImportedDay(
          dayName: 'Day 1',
          exercises: [
            ImportedExercise(
              exerciseId: 'squat',
              exerciseName: 'Back Squat',
              sets: 3,
            ),
          ],
        ),
      ],
    ),
  ],
  unknownExercises: [],
  totalDays: 1,
  totalExercises: 1,
);

Future<void> _pumpImporter(
  WidgetTester tester,
  _FakeImportService service,
) async {
  final AppDatabase database = AppDatabase.forTesting();
  addTearDown(database.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        programImportServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () =>
                  ProgramImportAction.importCsv(context, ref, 'csv'),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a failed write is reported, not silently dropped',
      (tester) async {
    final service = _FakeImportService(
      result: _oneProgram,
      applyError: Exception('UNIQUE constraint failed'),
    );
    await _pumpImporter(tester, service);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();

    expect(service.applyCalls, 1);
    expect(
      find.text(
        "Couldn't save the imported programs. Nothing was written — try again.",
      ),
      findsOneWidget,
    );
    expect(find.text('Programs imported.'), findsNothing);
    // The raw database error never reaches the screen.
    expect(find.textContaining('UNIQUE'), findsNothing);
  });

  testWidgets('a successful write says so', (tester) async {
    final service = _FakeImportService(result: _oneProgram);
    await _pumpImporter(tester, service);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();

    expect(find.text('Programs imported.'), findsOneWidget);
  });

  testWidgets('cancelling the preview writes nothing', (tester) async {
    final service = _FakeImportService(result: _oneProgram);
    await _pumpImporter(tester, service);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(service.applyCalls, 0);
  });

  testWidgets('a parse failure other than a bad header still shows a message',
      (tester) async {
    final service = _FakeImportService(parseError: StateError('db closed'));
    await _pumpImporter(tester, service);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Could not read the selected file.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
      'the preview names every skipped program and row, '
      'and summarises a long list', (tester) async {
    final service = _FakeImportService(
      result: ProgramImportResult(
        programs: const [],
        unknownExercises: const ['Moon Press'],
        existingPrograms: const ['Full Body'],
        rejectedRows: [
          const ProgramImportRowIssue(
            rowNumber: 2,
            problem: ProgramImportRowProblem.invalidSets,
          ),
          for (var row = 3; row <= 13; row++)
            ProgramImportRowIssue(
              rowNumber: row,
              problem: ProgramImportRowProblem.missingField,
            ),
        ],
        totalDays: 0,
        totalExercises: 0,
      ),
    );
    await _pumpImporter(tester, service);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('• Full Body'), findsOneWidget);
    expect(find.text('• Moon Press'), findsOneWidget);
    expect(
      find.text('• Row 2: sets must be a whole number from 1 to 20'),
      findsOneWidget,
    );
    expect(
      find.text('• Row 3: program, day or exercise is empty'),
      findsOneWidget,
    );
    // Twelve rows: ten listed, the last two counted.
    expect(
      find.text('• Row 12: program, day or exercise is empty'),
      findsNothing,
    );
    expect(find.text('…and 2 more'), findsOneWidget);

    // Nothing importable: the confirm button is disabled.
    final FilledButton confirm = tester.widget(
      find.widgetWithText(FilledButton, 'Import'),
    );
    expect(confirm.onPressed, isNull);
  });
}
