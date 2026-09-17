import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/widgets/chart_gestures.dart';

/// Guards the workaround in `core/widgets/chart_gestures.dart`.
///
/// fl_chart registers a `LongPressGestureRecognizer` on every touch-enabled
/// chart. It beats the enclosing `Scrollable`'s vertical drag, so a finger
/// that rests on a chart for the long-press timeout before moving cannot
/// scroll the page at all until it lifts — the "sometimes the page is stuck"
/// symptom, and only ever over charts.
///
/// These tests pin the behaviour rather than the mechanism: if a future
/// fl_chart makes the workaround unnecessary, the "unfixed" case starts
/// passing and `kChartNoLongPress` can be deleted.
void main() {
  const double dragDistance = 200;

  Widget page(Widget chart) => MaterialApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              for (int i = 0; i < 10; i++) SizedBox(height: 220, child: chart),
            ],
          ),
        ),
      );

  Widget lineChart({Duration? longPress}) => LineChart(
        LineChartData(
          lineTouchData: LineTouchData(longPressDuration: longPress),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: const <FlSpot>[FlSpot(0, 1), FlSpot(1, 3), FlSpot(2, 2)],
            ),
          ],
        ),
      );

  Widget barChart({Duration? longPress}) => BarChart(
        BarChartData(
          barTouchData: BarTouchData(longPressDuration: longPress),
          barGroups: <BarChartGroupData>[
            for (int i = 0; i < 3; i++)
              BarChartGroupData(
                x: i,
                barRods: <BarChartRodData>[BarChartRodData(toY: i + 1)],
              ),
          ],
        ),
      );

  double offsetOf(WidgetTester tester) => tester
      .widget<Scrollable>(find.byType(Scrollable).first)
      .controller!
      .offset;

  /// Drags in small per-frame steps like a real finger, optionally resting
  /// first. [hold] is what distinguishes a stuck drag from a working one.
  Future<void> dragUp(WidgetTester tester, {Duration? hold}) async {
    final TestGesture gesture = await tester.startGesture(
      const Offset(200, 300),
    );
    await tester.pump(hold ?? const Duration(milliseconds: 16));
    for (int i = 0; i < dragDistance ~/ 8; i++) {
      await gesture.moveBy(const Offset(0, -8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a rested finger cannot scroll an unfixed chart', (tester) async {
    await tester.pumpWidget(page(lineChart()));
    await tester.pump();

    await dragUp(tester, hold: const Duration(milliseconds: 600));

    // The bug this file exists for. Not "scrolled less" — not at all.
    expect(offsetOf(tester), 0);
  });

  testWidgets('a rested finger scrolls a LineChart using kChartNoLongPress',
      (tester) async {
    await tester.pumpWidget(page(lineChart(longPress: kChartNoLongPress)));
    await tester.pump();

    await dragUp(tester, hold: const Duration(milliseconds: 600));

    // Not the full 200: the chart's pan recognizer still consumes the
    // pointer deltas spent resolving the gesture arena, as it does on any
    // drag over any chart. That costs a few pixels, not the gesture.
    expect(offsetOf(tester), greaterThan(dragDistance * 0.8));
  });

  testWidgets('a rested finger scrolls a BarChart using kChartNoLongPress',
      (tester) async {
    await tester.pumpWidget(page(barChart(longPress: kChartNoLongPress)));
    await tester.pump();

    await dragUp(tester, hold: const Duration(milliseconds: 600));

    expect(offsetOf(tester), greaterThan(dragDistance * 0.8));
  });

  testWidgets('holding longer than the timeout still scrolls', (tester) async {
    await tester.pumpWidget(page(lineChart(longPress: kChartNoLongPress)));
    await tester.pump();

    await dragUp(tester, hold: const Duration(seconds: 3));

    expect(offsetOf(tester), greaterThan(dragDistance * 0.8));
  });

  testWidgets('taps still reach the chart, so tooltips survive',
      (tester) async {
    FlTouchEvent? received;
    await tester.pumpWidget(
      page(
        LineChart(
          LineChartData(
            lineTouchData: LineTouchData(
              longPressDuration: kChartNoLongPress,
              touchCallback: (FlTouchEvent event, LineTouchResponse? _) {
                if (event is FlTapUpEvent) received = event;
              },
            ),
            lineBarsData: <LineChartBarData>[
              LineChartBarData(
                spots: const <FlSpot>[FlSpot(0, 1), FlSpot(1, 3)],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tapAt(const Offset(200, 300));
    await tester.pump();

    expect(received, isNotNull);
  });
}
