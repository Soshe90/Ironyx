/// Neutralises fl_chart's long-press recognizer.
///
/// Every touch-enabled fl_chart registers three gesture recognizers on
/// pointer-down — tap, pan, and long-press — and they compete in the arena
/// with the enclosing `Scrollable`'s vertical drag. Tap and pan lose that
/// race harmlessly, but the long-press does not: rest a finger on a chart
/// for 500 ms (reading it, or just starting a swipe hesitantly) and the
/// long-press wins, after which the drag is dead until the finger lifts.
/// The page reads as randomly stuck, and only over charts.
///
/// fl_chart has no flag for "no long press", but the recognizer's deadline
/// is configurable, so a deadline that never arrives is the same thing.
/// Tap and hover still drive the tooltips, which is all the charts use.
///
/// Pass as `longPressDuration:` on any `LineTouchData` / `BarTouchData` that
/// leaves touch enabled.
const Duration kChartNoLongPress = Duration(days: 1);
