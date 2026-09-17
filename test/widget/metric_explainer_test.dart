import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/widgets/metric_explainer.dart';
import 'package:ironyx/core/widgets/section_header.dart';

import '../helpers/pump_app.dart';

const MetricExplainer _explainer = MetricExplainer(
  title: 'Estimated 1RM',
  summary: 'The heaviest weight you could lift once.',
  formula: '1RM = weight × (1 + reps ÷ 30)',
  example: '80 kg × 8 reps → 101 kg',
  points: <String>['Only sets of 1–12 reps are used.'],
  caveat: 'An estimate, not a target.',
);

/// Mirrors the shape of the shipped Arabic string: Latin `1RM`, an `=`, then
/// Arabic words interleaved with neutral operators. That mix is what the bidi
/// algorithm reorders if the formula is rendered as one paragraph.
const MetricExplainer _arabicExplainer = MetricExplainer(
  title: 'الحد الأقصى',
  summary: 'أثقل وزن يمكنك رفعه مرة واحدة.',
  formula: '1RM = الوزن × (1 + التكرارات ÷ 30)',
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
      expect(find.text(_explainer.points.single), findsOneWidget);
      expect(find.text(_explainer.caveat!), findsOneWidget);
      // The formula and example are split into one Text per token, so assert
      // on the tokens rather than the whole string.
      expect(find.text('1RM'), findsOneWidget);
      expect(find.text('weight'), findsOneWidget);
      expect(find.text('101'), findsOneWidget);
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

    testWidgets('keeps the formula in written order under an RTL locale',
        (tester) async {
      await pumpWidgetUnderTest(
        tester,
        const SectionHeader(
          title: 'الحد الأقصى',
          explainer: _arabicExplainer,
        ),
        locale: const Locale('ar'),
      );

      // The header itself follows the locale...
      expect(
        Directionality.of(tester.element(find.text('الحد الأقصى'))),
        TextDirection.rtl,
      );

      await tester.tap(find.byType(MetricInfoButton));
      await tester.pumpAndSettle();

      // ...but the formula must read left to right, in the order it was
      // written. Asserting on position rather than on Directionality: an
      // earlier version forced the paragraph to LTR, which satisfied a
      // directionality check while still rendering `= 1RM` at the far right,
      // because the Arabic words inside were their own RTL runs.
      final double lhs = tester.getTopLeft(find.text('1RM')).dx;
      final double firstOperand = tester.getTopLeft(find.text('الوزن')).dx;
      final double lastOperand = tester.getTopLeft(find.text('30)')).dx;

      expect(lhs, lessThan(firstOperand));
      expect(firstOperand, lessThan(lastOperand));
    });
  });
}
