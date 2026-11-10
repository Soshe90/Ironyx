import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/features/progress/presentation/widgets/lift_picker.dart';

import '../helpers/pump_app.dart';

void main() {
  group('liftMatchesQuery', () {
    test('every word, in any order, ignoring case', () {
      const List<String> names = <String>['Barbell Bench Press'];
      expect(liftMatchesQuery('bench', names), isTrue);
      expect(liftMatchesQuery('BENCH barbell', names), isTrue);
      expect(liftMatchesQuery('  press  ', names), isTrue);
      expect(liftMatchesQuery('bench squat', names), isFalse);
    });

    test('an empty query matches everything', () {
      expect(liftMatchesQuery('', <String>['Row']), isTrue);
      expect(liftMatchesQuery('   ', <String>['Row']), isTrue);
    });

    test('searches the shown name and the stored one', () {
      const List<String> names = <String>['ضغط البنش بالبار', 'Bench Press'];
      expect(liftMatchesQuery('bench', names), isTrue);
      expect(liftMatchesQuery('البنش', names), isTrue);
    });

    test('Arabic: alef forms, teh marbuta, diacritics and tatweel fold', () {
      // Typed without the hamza, the teh marbuta as heh, no diacritics.
      expect(liftMatchesQuery('اماميه', <String>['رفرفة أماميّة']), isTrue);
      expect(liftMatchesQuery('رفرفـة', <String>['رفرفة أمامية']), isTrue);
      expect(liftMatchesQuery('إمالة', <String>['امالة']), isTrue);
    });
  });

  group('the sheet', () {
    List<LiftOption> lifts(int n) => <LiftOption>[
          for (int i = 0; i < n; i++)
            LiftOption(
              id: 'lift$i',
              name: i == 0 ? 'Barbell Bench Press' : 'Lift number $i',
              storedName: i == 0 ? 'Barbell Bench Press' : 'Lift $i',
              sessions: '${20 - i} sessions',
            ),
        ];

    /// Opens the picker from a button and records what it resolves to.
    Future<List<String?>> open(
      WidgetTester tester,
      List<LiftOption> options, {
      String? selectedId,
    }) async {
      final List<String?> results = <String?>[];
      await pumpWidgetUnderTest(
        tester,
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async => results.add(
              await showLiftPicker(
                context,
                options: options,
                selectedId: selectedId,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('a short list has no search box, and marks the current lift',
        (tester) async {
      await open(tester, lifts(3), selectedId: 'lift1');

      expect(find.text('Choose a lift'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      final ListTile current = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Lift number 1'),
          matching: find.byType(ListTile),
        ),
      );
      expect(current.selected, isTrue);
      expect(find.text('19 sessions'), findsOneWidget);
    });

    testWidgets('a short list sheet is as tall as its rows', (tester) async {
      // 800 dp tall surface; one lift used to open a 60% sheet.
      await open(tester, lifts(1));
      final double height = tester.getSize(find.byType(LiftPickerSheet)).height;
      expect(height, lessThan(800 * 0.3));
      expect(find.text('Barbell Bench Press'), findsOneWidget);
    });

    testWidgets('choosing a lift resolves to its id', (tester) async {
      final List<String?> results = await open(tester, lifts(3));

      await tester.tap(find.text('Lift number 2'));
      await tester.pumpAndSettle();

      expect(results, <String?>['lift2']);
      expect(find.text('Choose a lift'), findsNothing);
    });

    testWidgets('dismissing resolves to null', (tester) async {
      final List<String?> results = await open(tester, lifts(3));

      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();

      expect(results, <String?>[null]);
    });

    testWidgets('past the threshold, a search box filters the list',
        (tester) async {
      await open(tester, lifts(liftPickerSearchFrom + 4));

      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'bench');
      await tester.pump();

      expect(find.text('Barbell Bench Press'), findsOneWidget);
      expect(find.textContaining('Lift number'), findsNothing);

      // Clearing brings the list back.
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.textContaining('Lift number'), findsWidgets);
    });

    testWidgets('a search with no match says only logged lifts are listed',
        (tester) async {
      await open(tester, lifts(liftPickerSearchFrom + 1));

      await tester.enterText(find.byType(TextField), 'zercher');
      await tester.pump();

      expect(find.text('No lift matches'), findsOneWidget);
      expect(
        find.text('Only lifts you have logged are listed here.'),
        findsOneWidget,
      );
    });
  });
}
