import 'package:flutter/material.dart';

/// A single-line metric number that shrinks to fit its space instead of
/// being cut off.
///
/// An ellipsized metric ("6,814…") hides the one thing a metric exists to
/// show, and large system text sizes or a narrow tile make that routine.
/// Scaling down keeps every digit; at normal sizes it changes nothing.
class MetricValue extends StatelessWidget {
  const MetricValue(this.text, {required this.style, super.key});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(text, style: style, maxLines: 1),
      );
}
