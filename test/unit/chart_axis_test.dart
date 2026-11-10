import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/features/progress/presentation/widgets/chart_axis.dart';

void main() {
  group('niceAxisStep', () {
    test('picks 1, 2, 2.5 or 5 times a power of ten', () {
      expect(niceAxisStep(40), 10); // 4 steps of 10
      expect(niceAxisStep(30), 10); // 7.5 -> 10
      expect(niceAxisStep(18), 5); // 4.5 -> 5
      expect(niceAxisStep(9), 2.5); // 2.25 -> 2.5
      expect(niceAxisStep(7), 2); // 1.75 -> 2
      expect(niceAxisStep(4), 1);
      expect(niceAxisStep(2200), 1000); // 550 -> 1000
      expect(niceAxisStep(1800), 500);
      expect(niceAxisStep(0.6), closeTo(0.2, 1e-12)); // 0.15 -> 0.2
    });

    test('an exact fit takes that step, not the next one', () {
      expect(niceAxisStep(0.4), closeTo(0.1, 1e-12));
      expect(niceAxisStep(20), 5);
      expect(niceAxisStep(8), 2);
    });

    test('never gives more than about the target number of steps', () {
      for (double span = 0.37; span < 50000; span *= 1.37) {
        final double step = niceAxisStep(span);
        expect(span / step, lessThanOrEqualTo(4 + 1e-9), reason: '$span');
        expect(span / step, greaterThan(1), reason: '$span');
      }
    });

    test('whole numbers leave out 2.5 and never go below 1', () {
      expect(niceAxisStep(9, wholeNumbers: true), 5);
      expect(niceAxisStep(3, wholeNumbers: true), 1);
      expect(niceAxisStep(0.5, wholeNumbers: true), 1);
      expect(niceAxisStep(7, wholeNumbers: true), 2);
    });

    test('a span with no size gets a step of 1', () {
      expect(niceAxisStep(0), 1);
      expect(niceAxisStep(-5), 1);
      expect(niceAxisStep(double.nan), 1);
      expect(niceAxisStep(double.infinity), 1);
    });

    test('a step round in pounds is not round in kilograms', () {
      // Why callers pick the step in display units: 5 lb is 2.268 kg.
      const double lbPerKg = 2.2046226218;
      final double stepKg = niceAxisStep(40 * lbPerKg) / lbPerKg;
      expect(stepKg * lbPerKg, closeTo(25, 1e-9));
    });
  });
}
