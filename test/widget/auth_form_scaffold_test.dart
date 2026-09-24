import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/widgets/app_card.dart';
import 'package:ironyx/features/auth/presentation/widgets/auth_form_scaffold.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('auth fields are presented directly on the page, not in a card',
      (tester) async {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final Finder emailField = find.byType(TextFormField);

    await pumpWidgetUnderTest(
      tester,
      AuthFormScaffold(
        title: 'Sign in',
        intro: 'Sign in to your account.',
        formKey: formKey,
        fields: <Widget>[
          TextFormField(decoration: const InputDecoration(labelText: 'Email')),
        ],
        primaryLabel: 'Continue',
        onSubmit: () {},
        busy: false,
      ),
    );

    expect(emailField, findsOneWidget);
    expect(
      find.ancestor(of: emailField, matching: find.byType(AppCard)),
      findsNothing,
    );
  });
}
