import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/theme/app_spacing.dart';
import 'package:ironyx/core/widgets/segmented_pills.dart';

void main() {
  Future<List<String>> pump(
    WidgetTester tester, {
    String selected = 'b',
    TextDirection direction = TextDirection.ltr,
    double width = 320,
    List<PillSegment<String>>? segments,
  }) async {
    final List<String> changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: SegmentedPills<String>(
                  semanticLabel: 'Date range',
                  segments: segments ??
                      const <PillSegment<String>>[
                        PillSegment<String>(value: 'a', label: 'Week'),
                        PillSegment<String>(value: 'b', label: 'Month'),
                        PillSegment<String>(value: 'c', label: 'Year'),
                      ],
                  selected: selected,
                  onChanged: changes.add,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return changes;
  }

  testWidgets('reports the tapped segment', (tester) async {
    final List<String> changes = await pump(tester);

    await tester.tap(find.text('Year'));
    await tester.tap(find.text('Week'));

    expect(changes, <String>['c', 'a']);
  });

  testWidgets('tapping the selected segment changes nothing', (tester) async {
    final List<String> changes = await pump(tester);

    await tester.tap(find.text('Month'));

    expect(changes, isEmpty);
  });

  testWidgets('every segment is a full-height tap target', (tester) async {
    await pump(tester);

    expect(
      tester.getSize(find.byType(SegmentedPills<String>)).height,
      AppSpacing.minTapTarget,
    );
    // Top edge of the control, well above the drawn pill.
    final Rect year = tester.getRect(
      find.ancestor(of: find.text('Year'), matching: find.byType(InkWell)),
    );
    expect(year.height, AppSpacing.minTapTarget);
    expect(year.width, moreOrLessEquals(320 / 3, epsilon: 0.5));
  });

  testWidgets('a screen reader hears a named group of selectable buttons',
      (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final List<String> changes = await pump(tester);

    expect(find.bySemanticsLabel('Date range'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Month')),
      matchesSemantics(
        label: 'Month',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Year')),
      matchesSemantics(
        label: 'Year',
        isButton: true,
        hasSelectedState: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );

    // The action a screen reader triggers is the same one a tap does.
    tester.getSemantics(find.bySemanticsLabel('Year')).owner!.performAction(
          tester.getSemantics(find.bySemanticsLabel('Year')).id,
          SemanticsAction.tap,
        );
    expect(changes, <String>['c']);
    semantics.dispose();
  });

  testWidgets('the first segment sits at the reading start in Arabic',
      (tester) async {
    await pump(tester, direction: TextDirection.rtl);

    expect(
      tester.getCenter(find.text('Week')).dx,
      greaterThan(tester.getCenter(find.text('Year')).dx),
    );
  });

  testWidgets('a long label shrinks to fit instead of overflowing',
      (tester) async {
    await pump(
      tester,
      width: 200,
      selected: 'a',
      segments: const <PillSegment<String>>[
        PillSegment<String>(value: 'a', label: 'Estimated one-rep maximum'),
        PillSegment<String>(value: 'b', label: 'Volume'),
      ],
    );

    expect(tester.takeException(), isNull);
    final Rect label = tester.getRect(find.text('Estimated one-rep maximum'));
    final Rect control = tester.getRect(find.byType(SegmentedPills<String>));
    expect(label.left, greaterThanOrEqualTo(control.left));
    expect(label.right, lessThanOrEqualTo(control.left + control.width / 2));
  });
}
