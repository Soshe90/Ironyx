import 'package:fittrack/core/widgets/metric_explainer.dart';
import 'package:fittrack/core/widgets/section_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

const MetricExplainer _explainer = MetricExplainer(
  title: 'Estimated 1RM',
  summary: 'The heaviest weight you could lift once.',
  formula: '1RM = weight × (1 + reps ÷ 30)',
  example: '80 kg × 8 reps → 101 kg',
  points: <String>['Only sets of 1–12 reps are used.'],
  caveat: 'An estimate, not a target.',
);

void main() {
  group('MetricExplainer', () {
    testWidgets('SectionHeader shows no info button without an explainer',
        (tester) async {
      await pumpWidgetUnderTest(tester, const SectionHeader(title: 'Volume'));

      expect(find.byType(MetricInfoButton), findsNothing);
    });

    testWidgets('tapping the info button opens the sheet', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const SectionHeader(title: 'Estimated 1RM', explainer: _explainer),
      );

      // Nothing is on screen until asked for — the header stays uncluttered.
      expect(find.text(_explainer.summary), findsNothing);

      await tester.tap(find.byType(MetricInfoButton));
      await tester.pumpAndSettle();

      expect(find.text(_explainer.summary), findsOneWidget);
      expect(find.text(_explainer.formula!), findsOneWidget);
      expect(find.text(_explainer.example!), findsOneWidget);
      expect(find.text(_explainer.points.single), findsOneWidget);
      expect(find.text(_explainer.caveat!), findsOneWidget);
    });

    testWidgets('the dismiss button closes the sheet', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const SectionHeader(title: 'Estimated 1RM', explainer: _explainer),
      );

      await tester.tap(find.byType(MetricInfoButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      expect(find.text(_explainer.summary), findsNothing);
    });

    testWidgets('omits the formula card for metrics without a formula',
        (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const SectionHeader(
          title: 'Consistency',
          explainer: MetricExplainer(
            title: 'Consistency',
            summary: 'Whether you are showing up.',
          ),
        ),
      );

      await tester.tap(find.byType(MetricInfoButton));
      await tester.pumpAndSettle();

      expect(find.text('Whether you are showing up.'), findsOneWidget);
      // No formula, so no "How to read it" heading either — an empty section
      // label with nothing under it reads as a rendering bug.
      expect(find.text('How to read it'), findsNothing);
    });

    testWidgets('lays the formula out left-to-right under an RTL locale',
        (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const SectionHeader(title: 'الحد الأقصى', explainer: _explainer),
        locale: const Locale('ar'),
      );

      // The header itself follows the locale...
      expect(
        Directionality.of(tester.element(find.text('الحد الأقصى'))),
        TextDirection.rtl,
      );

      await tester.tap(find.byType(MetricInfoButton));
      await tester.pumpAndSettle();

      // ...but the formula must not, or the bidi algorithm reorders the
      // operands and `weight × (1 + reps ÷ 30)` comes out backwards.
      expect(
        Directionality.of(tester.element(find.text(_explainer.formula!))),
        TextDirection.ltr,
      );
      expect(
        Directionality.of(tester.element(find.text(_explainer.example!))),
        TextDirection.ltr,
      );
    });
  });
}
