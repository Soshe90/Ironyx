import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/features/dashboard/presentation/widgets/summary_card.dart';

import '../helpers/pump_app.dart';

void main() {
  group('SummaryCard', () {
    testWidgets('renders metric and caption', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        SummaryCard(
          title: 'Last workout',
          icon: Icons.add_box_outlined,
          metric: '12,450 kg',
          caption: 'Push day · Yesterday',
          onTap: () {},
        ),
      );

      expect(find.text('12,450 kg'), findsOneWidget);
      expect(find.text('Push day · Yesterday'), findsOneWidget);
    });

    testWidgets('shows a placeholder rather than an empty box', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        SummaryCard(
          title: 'Last workout',
          icon: Icons.add_box_outlined,
          onTap: () {},
        ),
      );

      expect(find.text('—'), findsOneWidget);
      expect(find.text('No data yet'), findsOneWidget);
    });

    testWidgets('an error degrades this card only', (tester) async {
      await pumpWidgetUnderTest(
        tester,
        SummaryCard(
          title: 'Last workout',
          icon: Icons.add_box_outlined,
          error: Exception('query failed'),
          onTap: () {},
        ),
      );

      expect(find.text('Could not load'), findsOneWidget);
      expect(find.text('No data yet'), findsNothing);
    });

    testWidgets('is tappable and announced as a button', (tester) async {
      int taps = 0;
      await pumpWidgetUnderTest(
        tester,
        SummaryCard(
          title: 'Last workout',
          icon: Icons.add_box_outlined,
          metric: '12,450 kg',
          onTap: () => taps++,
        ),
      );

      await tester.tap(find.byType(SummaryCard));
      expect(taps, 1);

      final SemanticsHandle handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('Last workout')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
