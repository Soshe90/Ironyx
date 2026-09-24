import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/theme/app_theme.dart';
import 'package:ironyx/core/widgets/metric_block.dart';

import '../helpers/pump_app.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    MetricBlock block, {
    double width = 300,
    double textScale = 1,
  }) async {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpWidgetUnderTest(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: block),
      ),
      theme: AppTheme.light(),
    );
  }

  testWidgets('a value without a caption shows no empty-state wording',
      (tester) async {
    await pump(
      tester,
      const MetricBlock(
        label: 'Average duration',
        value: '57m',
        emptyCaption: 'Complete a workout to see this',
      ),
    );

    expect(find.text('57m'), findsOneWidget);
    expect(find.text('Complete a workout to see this'), findsNothing);
  });

  testWidgets('no value shows the empty caption', (tester) async {
    await pump(
      tester,
      const MetricBlock(
        label: 'Average duration',
        emptyCaption: 'Complete a workout to see this',
      ),
    );

    expect(find.text('—'), findsOneWidget);
    expect(find.text('Complete a workout to see this'), findsOneWidget);
  });

  testWidgets('an explicit caption is shown alongside a value', (tester) async {
    await pump(
      tester,
      const MetricBlock(
          label: 'Body weight', value: '82.5 kg', caption: 'Today'),
    );

    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets(
      'a long value in a narrow tile at large text is scaled, never '
      'ellipsized or overflowing', (tester) async {
    await pump(
      tester,
      const MetricBlock(label: 'Volume', value: '126,814 kg'),
      width: 120,
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    final RenderParagraph value = tester.renderObject(find.text('126,814 kg'));
    expect(value.didExceedMaxLines, isFalse);
    // Painted width, after the scale-down transform (getSize is pre-transform).
    expect(
      tester.getRect(find.text('126,814 kg')).width,
      lessThanOrEqualTo(120),
    );
  });
}
