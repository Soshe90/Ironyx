import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/features/progress/presentation/widgets/progress_visuals.dart';

import '../helpers/pump_app.dart';

/// The Progress page's hand-drawn visuals. They replaced canvas charts
/// precisely so their figures are real text, so these tests read that text
/// and the semantics labels, and check the geometry at the edges (empty
/// totals, out-of-range values, right-to-left layout).
void main() {
  group('ShareBarRow', () {
    testWidgets('shows value and rounded share, and announces both',
        (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpWidgetUnderTest(
        tester,
        const ShareBarRow(
          label: 'Chest',
          value: '13,612 kg',
          share: 0.516,
          relative: 1,
          color: Colors.blue,
        ),
      );

      expect(find.text('Chest'), findsOneWidget);
      expect(find.text('13,612 kg'), findsOneWidget);
      expect(find.text('52%'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Chest: 13,612 kg, 52% of the total'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('clamps an out-of-range fill instead of overflowing',
        (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const ShareBarRow(
          label: 'Back',
          value: '1 kg',
          share: 0,
          relative: 3,
          color: Colors.red,
        ),
      );
      final FractionallySizedBox fill = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(fill.widthFactor, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('ProportionBar', () {
    testWidgets('sizes segments by count and lists every bucket as text',
        (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const ProportionBar(
          segments: <ProportionSegment>[
            ProportionSegment(
              label: '1–5 reps',
              value: '2 sets',
              count: 2,
              color: Colors.blue,
            ),
            ProportionSegment(
              label: '6–12 reps',
              value: '6 sets',
              count: 6,
              color: Colors.green,
            ),
            ProportionSegment(
              label: '13+ reps',
              value: '0 sets',
              count: 0,
              color: Colors.orange,
            ),
          ],
        ),
      );

      final List<Expanded> drawn =
          tester.widgetList<Expanded>(find.byType(Expanded)).where((e) {
        return e.child is ColoredBox;
      }).toList();
      // The empty bucket is left out of the bar but kept in the legend.
      expect(drawn.map((e) => e.flex), <int>[2, 6]);
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('13+ reps'), findsOneWidget);

      // The segments have height: a childless box in an unstretched row
      // collapses to nothing, which is how this bar first shipped.
      final Size segment = tester.getSize(
        find.descendant(
          of: find.byWidget(drawn.first),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(segment.height, greaterThan(0));
    });

    testWidgets('with nothing logged shows an empty track and 0%',
        (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const ProportionBar(
          segments: <ProportionSegment>[
            ProportionSegment(
              label: '1–5 reps',
              value: '0 sets',
              count: 0,
              color: Colors.blue,
            ),
          ],
        ),
      );
      expect(find.text('0%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('RatioGauge', () {
    Future<Offset?> markerCentre(
      WidgetTester tester,
      double? ratio, {
      TextDirection direction = TextDirection.ltr,
    }) async {
      await pumpWidgetUnderTest(
        tester,
        Directionality(
          textDirection: direction,
          child: SizedBox(
            width: 200,
            child: RatioGauge(ratio: ratio, bandLow: 0.75, bandHigh: 1.33),
          ),
        ),
      );
      final Finder marker = find.byWidgetPredicate(
        (Widget w) =>
            w is Container &&
            (w.decoration as BoxDecoration?)?.shape == BoxShape.circle,
      );
      if (marker.evaluate().isEmpty) return null;
      return tester.getCenter(marker);
    }

    testWidgets('has no marker without a ratio', (tester) async {
      expect(await markerCentre(tester, null), isNull);
    });

    testWidgets('places 1.0 at the middle of a 0–2 scale', (tester) async {
      final Offset? centre = await markerCentre(tester, 1);
      final double left = tester.getTopLeft(find.byType(RatioGauge)).dx;
      expect(centre!.dx - left, closeTo(100, 0.5));
    });

    testWidgets('keeps an extreme ratio on the track', (tester) async {
      final Offset? high = await markerCentre(tester, 9);
      final Rect gauge = tester.getRect(find.byType(RatioGauge));
      expect(high!.dx, lessThanOrEqualTo(gauge.right));
      expect(tester.takeException(), isNull);
    });

    testWidgets('mirrors in right-to-left layouts', (tester) async {
      final Offset? ltr = await markerCentre(tester, 0.5);
      final Offset? rtl =
          await markerCentre(tester, 0.5, direction: TextDirection.rtl);
      final double left = tester.getTopLeft(find.byType(RatioGauge)).dx;
      // A quarter of the way along from the reading start either way.
      expect(ltr!.dx - left, closeTo(50, 0.5));
      expect(rtl!.dx - left, closeTo(150, 0.5));
    });
  });

  group('WeekdayBars', () {
    List<WeekdayBarData> week(List<int> counts) => <WeekdayBarData>[
          for (int i = 0; i < counts.length; i++)
            WeekdayBarData(
              shortLabel: 'D$i',
              semanticLabel: 'Day $i: ${counts[i]}',
              trainingDays: counts[i],
            ),
        ];

    testWidgets('scales to the busiest day', (tester) async {
      await pumpWidgetUnderTest(tester, WeekdayBars(days: week([1, 4, 2])));
      final List<double?> factors = tester
          .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .map((f) => f.heightFactor)
          .toList();
      expect(factors, <double>[0.25, 1, 0.5]);
      expect(find.bySemanticsLabel('Day 1: 4'), findsOneWidget);
    });

    testWidgets('an untrained window draws stubs, not a division by zero',
        (tester) async {
      await pumpWidgetUnderTest(tester, WeekdayBars(days: week([0, 0, 0])));
      expect(tester.takeException(), isNull);
      // Counts are only printed above days that were trained.
      expect(find.text('0'), findsNothing);
    });
  });
}
