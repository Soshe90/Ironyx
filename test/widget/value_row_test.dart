import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/theme/app_theme.dart';
import 'package:ironyx/core/widgets/value_row.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('shows label, caption and value, read as one item',
      (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpWidgetUnderTest(
      tester,
      const ValueRow(label: '12 Sep', caption: 'From 4 sets', value: '95 s'),
      theme: AppTheme.light(),
    );

    expect(find.text('12 Sep'), findsOneWidget);
    expect(find.text('From 4 sets'), findsOneWidget);
    expect(find.text('95 s'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(ValueRow)),
      matchesSemantics(label: '12 Sep\nFrom 4 sets\n95 s'),
    );
    semantics.dispose();
  });

  testWidgets(
      'long text on a narrow phone at large text wraps, never overflows',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpWidgetUnderTest(
      tester,
      const ValueRow(
        label: 'Barbell Romanian Deadlift',
        value: '1.31× body weight',
      ),
      theme: AppTheme.light(),
      surfaceSize: const Size(320, 600),
    );

    expect(tester.takeException(), isNull);
  });
}
