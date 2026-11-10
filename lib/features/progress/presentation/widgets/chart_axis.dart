import 'dart:math' as math;

/// A round step for a value axis that spans [span], in the unit the axis
/// is read in.
///
/// Left to itself fl_chart picks a step in the units it plots, and this
/// page plots kilograms (ADR-1: stored values in, conversion at the label).
/// A step round in kilograms is not round in pounds, so a 100/105/110 kg
/// axis read 220.5/231.5/242.5 lb. The caller picks the step here in the
/// display unit and divides it back into plotted units; fl_chart places
/// ticks on whole multiples of the step, so every tick is then a round
/// display value.
///
/// The step is 1, 2, 2.5 or 5 times a power of ten, the smallest of those
/// that gives at most about [targetTicks] steps across [span].
/// [wholeNumbers] leaves out 2.5 and never goes below 1, for counts.
/// A span that is zero, negative or not finite gets a step of 1.
double niceAxisStep(
  double span, {
  int targetTicks = 4,
  bool wholeNumbers = false,
}) {
  if (!span.isFinite || span <= 0 || targetTicks < 1) return 1;
  final double raw = span / targetTicks;
  final double magnitude =
      math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final List<double> multiples = wholeNumbers
      ? const <double>[1, 2, 5, 10]
      : const <double>[1, 2, 2.5, 5, 10];
  double step = 10 * magnitude;
  for (final double m in multiples) {
    // A hair of tolerance, so 0.3 / 3 picks 0.1 rather than 0.2.
    if (m * magnitude >= raw * (1 - 1e-9)) {
      step = m * magnitude;
      break;
    }
  }
  if (wholeNumbers && step < 1) return 1;
  return step;
}
