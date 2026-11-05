import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/error_reporting.dart';
import 'package:ironyx/core/widgets/uncaught_error_view.dart';
import 'package:ironyx/l10n/app_localizations.dart';

const String _english = 'Something went wrong. Please restart the app.';

void main() {
  FlutterErrorDetails details() => FlutterErrorDetails(
        exception: StateError('secret@example.com could not sign in'),
        stack: StackTrace.fromString(
          '#0      _Foo.build (package:ironyx/features/foo.dart:10:3)\n',
        ),
        context: ErrorDescription('building _Foo'),
      );

  Widget localized(Locale locale, Widget child) => MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      );

  TextDirection directionOf(WidgetTester tester, String text) =>
      Directionality.of(tester.element(find.text(text)));

  group('release', () {
    testWidgets('shows one translated sentence and nothing about the error',
        (tester) async {
      await tester.pumpWidget(
        localized(
          const Locale('en'),
          UncaughtErrorView(
            details: details(),
            firstInBurst: 'earlier failure',
            debug: false,
          ),
        ),
      );

      expect(find.text(_english), findsOneWidget);
      // An error can carry personal data; none of it may reach the screen.
      expect(find.textContaining('secret@example.com'), findsNothing);
      expect(find.textContaining('foo.dart'), findsNothing);
      expect(find.textContaining('earlier failure'), findsNothing);
      expect(find.textContaining('_Foo'), findsNothing);
    });

    testWidgets('follows the app language, right to left for Arabic',
        (tester) async {
      await tester.pumpWidget(
        localized(
          const Locale('ar'),
          UncaughtErrorView(details: details(), debug: false),
        ),
      );
      final String arabic =
          lookupAppLocalizations(const Locale('ar')).errorUncaught;

      expect(arabic, isNot(_english));
      expect(find.text(arabic), findsOneWidget);
      expect(directionOf(tester, arabic), TextDirection.rtl);
    });

    testWidgets('with nothing above it, uses the device language',
        (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('ar', 'IQ');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final String arabic =
          lookupAppLocalizations(const Locale('ar')).errorUncaught;

      // No MaterialApp, Directionality, Theme or Localizations: the case of
      // a failure above all of them.
      await tester.pumpWidget(
        UncaughtErrorView(details: details(), debug: false),
      );

      expect(find.text(arabic), findsOneWidget);
      expect(directionOf(tester, arabic), TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a device language with no translation falls back to English',
        (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('ja', 'JP');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);

      await tester.pumpWidget(
        UncaughtErrorView(details: details(), debug: false),
      );

      expect(find.text(_english), findsOneWidget);
      expect(directionOf(tester, _english), TextDirection.ltr);
      expect(tester.takeException(), isNull);
    });
  });

  group('debug', () {
    testWidgets('shows the exception, what came first and where it was thrown',
        (tester) async {
      await tester.pumpWidget(
        UncaughtErrorView(
          details: details(),
          firstInBurst: 'A TextEditingController was used after disposal.',
          debug: true,
        ),
      );

      expect(
        find.text('Bad state: secret@example.com could not sign in'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'First error: A TextEditingController was used after disposal.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('While building _Foo'), findsOneWidget);
      expect(find.textContaining('_Foo.build (foo.dart:10)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stays left to right inside an Arabic app', (tester) async {
      await tester.pumpWidget(
        localized(
          const Locale('ar'),
          UncaughtErrorView(details: details(), debug: true),
        ),
      );

      expect(
        directionOf(
          tester,
          'Bad state: secret@example.com could not sign in',
        ),
        TextDirection.ltr,
      );
    });

    testWidgets('fits, by scrolling, where a small widget used to be',
        (tester) async {
      await tester.pumpWidget(
        Center(
          child: SizedBox(
            width: 160,
            height: 48,
            child: UncaughtErrorView(
              details: FlutterErrorDetails(
                exception: StateError('long ' * 40),
                stack: StackTrace.fromString(
                  <String>[
                    for (int i = 0; i < 12; i++)
                      '#$i      _Foo.build$i '
                          '(package:flutter/src/widgets/framework.dart:$i:1)',
                  ].join('\n'),
                ),
                context: ErrorDescription('building _Foo'),
              ),
              firstInBurst: 'earlier failure',
              debug: true,
            ),
          ),
        ),
      );

      // A layout overflow would be reported here as an exception.
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('is centred when it has the whole screen', (tester) async {
      await tester.pumpWidget(
        UncaughtErrorView(details: details(), debug: true),
      );

      final Rect screen = tester.getRect(find.byType(UncaughtErrorView));
      final Rect icon = tester.getRect(find.byIcon(Icons.error_outline));
      expect(icon.center.dx, moreOrLessEquals(screen.center.dx, epsilon: 1));
      expect(icon.top, greaterThan(screen.height / 4));
    });

    testWidgets('with nothing to add, shows the exception alone',
        (tester) async {
      await tester.pumpWidget(
        UncaughtErrorView(
          details: FlutterErrorDetails(exception: StateError('bare')),
          debug: true,
        ),
      );

      expect(find.text('Bad state: bare'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
    });
  });

  // The whole path as `main()` wires it: a widget throws while building,
  // the framework reports it and asks `ErrorWidget.builder` for a stand-in.
  testWidgets('a real build failure names the widget the framework blames',
      (tester) async {
    final ErrorBurst burst = ErrorBurst();
    final FlutterExceptionHandler? previousOnError = FlutterError.onError;
    final ErrorWidgetBuilder previousBuilder = ErrorWidget.builder;
    final List<Object> reported = <Object>[];
    FlutterError.onError = (FlutterErrorDetails details) {
      burst.record(details.exception);
      reported.add(details.exception);
    };
    ErrorWidget.builder = (FlutterErrorDetails details) => UncaughtErrorView(
          details: details,
          firstInBurst: burst.firstOtherThan(details.exception),
          debug: true,
        );

    String shown = '';
    try {
      await tester.pumpWidget(
        localized(
          const Locale('en'),
          const Column(children: <Widget>[_ThrowsFirst(), _ThrowsSecond()]),
        ),
      );
      shown = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text text) => text.data ?? '')
          .join('\n');
    } finally {
      // The test binding checks both are back before the test ends.
      FlutterError.onError = previousOnError;
      ErrorWidget.builder = previousBuilder;
    }

    expect(reported, hasLength(2));
    expect(shown, contains('Bad state: first failure'));
    expect(shown, contains('Bad state: second failure'));
    expect(shown, contains('While building _ThrowsSecond'));
    expect(shown, contains('Widget: _ThrowsSecond (uncaught_error_view_test'));
    expect(shown, contains('_ThrowsSecond.build (uncaught_error_view_test'));
    // Only the later failure is told what came before it.
    expect(
      'First error: Bad state: first failure'.allMatches(shown),
      hasLength(1),
    );
  });
}

class _ThrowsFirst extends StatelessWidget {
  const _ThrowsFirst();

  @override
  Widget build(BuildContext context) => throw StateError('first failure');
}

class _ThrowsSecond extends StatelessWidget {
  const _ThrowsSecond();

  @override
  Widget build(BuildContext context) => throw StateError('second failure');
}
