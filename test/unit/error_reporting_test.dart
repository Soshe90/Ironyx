import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/error_reporting.dart';

/// A trace shaped like the one behind the `_dependents.isEmpty` screen:
/// runtime frames first, then framework frames, with the app's own code
/// far below the part that fits on screen.
const String _trace = '''
#0      _AssertionError._doThrowNew (dart:core-patch/errors_patch.dart:67:4)
#1      _AssertionError._throwNew (dart:core-patch/errors_patch.dart:49:5)
#2      InheritedElement.debugDeactivated (package:flutter/src/widgets/framework.dart:6281:12)
#3      _InactiveElements._deactivateRecursively.<anonymous closure> (package:flutter/src/widgets/framework.dart:2146:15)
#4      _InactiveElements._deactivateRecursively (package:flutter/src/widgets/framework.dart:2148:6)
#5      MultiChildRenderObjectElement.visitChildren (package:flutter/src/widgets/framework.dart:7177:14)
#6      _InactiveElements.add (package:flutter/src/widgets/framework.dart:2157:9)
#7      Element.deactivateChild (package:flutter/src/widgets/framework.dart:4737:30)
#8      Element.updateChildren (package:flutter/src/widgets/framework.dart:4317:9)
#9      _DraftSetRowState._showSetDetails (package:ironyx/features/tracker/presentation/widgets/draft_editor_widgets.dart:915:7)
<asynchronous suspension>
#10     _DraftSetRowState.build.<anonymous closure> (package:ironyx/features/tracker/presentation/widgets/draft_editor_widgets.dart:871:42)
''';

void main() {
  group('ErrorBurst', () {
    late DateTime now;
    late ErrorBurst burst;

    setUp(() {
      now = DateTime(2026, 11, 5, 5, 7);
      burst = ErrorBurst(now: () => now);
    });

    test('names the first error of a run, not the latest', () {
      burst.record(StateError('controller used after dispose'));
      now = now.add(const Duration(milliseconds: 16));
      burst.record(StateError('layout failed'));
      now = now.add(const Duration(milliseconds: 16));
      final Object last = StateError('_dependents.isEmpty');
      burst.record(last);

      expect(
        burst.firstOtherThan(last),
        'Bad state: controller used after dispose',
      );
    });

    test('says nothing when the error on screen is itself the first', () {
      final Object only = StateError('alone');
      burst.record(only);

      expect(burst.firstOtherThan(only), isNull);
      // The same fault thrown again is not news either.
      burst.record(StateError('alone'));
      expect(burst.firstOtherThan(only), isNull);
    });

    test('says nothing before anything was recorded', () {
      expect(burst.firstOtherThan(StateError('x')), isNull);
    });

    test('an error after a quiet gap starts a new burst', () {
      burst.record(StateError('old'));
      now = now.add(const Duration(seconds: 5, milliseconds: 1));
      final Object fresh = StateError('fresh');
      burst.record(fresh);

      expect(burst.firstOtherThan(fresh), isNull);
      now = now.add(const Duration(seconds: 1));
      final Object next = StateError('next');
      burst.record(next);
      expect(burst.firstOtherThan(next), 'Bad state: fresh');
    });

    test('errors exactly a gap apart are still one burst', () {
      burst.record(StateError('first'));
      now = now.add(const Duration(seconds: 5));
      final Object second = StateError('second');
      burst.record(second);

      expect(burst.firstOtherThan(second), 'Bad state: first');
    });

    test('a burst that ended is not reported against a later error', () {
      burst.record(StateError('old'));
      now = now.add(const Duration(minutes: 1));

      expect(burst.firstOtherThan(StateError('unrecorded')), isNull);
    });

    test('keeps one line of a long, multi-line message', () {
      burst.record(StateError('headline\nsecond line\nthird'));
      expect(burst.firstOtherThan(StateError('x')), 'Bad state: headline');

      final ErrorBurst long = ErrorBurst(now: () => now)..record('y' * 5000);
      final String kept = long.firstOtherThan(StateError('x'))!;
      expect(kept.length, lessThan(250));
      expect(kept, endsWith('…'));
    });

    test('a clock that jumps backwards does not throw or lose the burst', () {
      burst.record(StateError('first'));
      now = now.subtract(const Duration(hours: 1));
      final Object second = StateError('second');
      burst.record(second);

      expect(burst.firstOtherThan(second), 'Bad state: first');
    });
  });

  group('debugErrorSummary', () {
    FlutterErrorDetails details({
      StackTrace? stack,
      DiagnosticsNode? context,
    }) =>
        FlutterErrorDetails(
          exception: StateError('boom'),
          stack: stack,
          context: context,
        );

    test('lists what came first, what was happening and the top frames', () {
      final String summary = debugErrorSummary(
        details(
          stack: StackTrace.fromString(_trace),
          context: ErrorDescription('building Overlay'),
        ),
        firstInBurst: 'A TextEditingController was used after being disposed.',
      );
      final List<String> lines = summary.split('\n');

      expect(
        lines[0],
        'First error: A TextEditingController was used after being disposed.',
      );
      expect(lines[1], 'While building Overlay');
      // Runtime frames are skipped; file paths and columns are trimmed.
      expect(
        lines[2],
        'InheritedElement.debugDeactivated (framework.dart:6281)',
      );
      expect(summary, isNot(contains('errors_patch.dart')));
      expect(summary, isNot(contains('package:')));
    });

    test('adds the first frame in app code when it is below the cut', () {
      final List<String> lines = debugErrorSummary(
        details(stack: StackTrace.fromString(_trace)),
      ).split('\n');

      // Six framework frames, then the app's own.
      expect(lines, hasLength(7));
      expect(
        lines.last,
        'App: _DraftSetRowState._showSetDetails '
        '(draft_editor_widgets.dart:915)',
      );
    });

    test('does not repeat an app frame that is already in the top frames', () {
      final String summary = debugErrorSummary(
        details(
          stack: StackTrace.fromString(
            '#0      _Foo.build (package:ironyx/features/foo.dart:10:3)\n'
            '#1      StatelessElement.build '
            '(package:flutter/src/widgets/framework.dart:5800:49)\n',
          ),
        ),
      );

      expect(summary, startsWith('_Foo.build (foo.dart:10)'));
      expect(summary, isNot(contains('App:')));
    });

    test('with no stack and no context there is nothing to add', () {
      expect(debugErrorSummary(details()), isEmpty);
    });

    test('a trace in an unknown format is skipped, not thrown on', () {
      final String summary = debugErrorSummary(
        details(
          stack: StackTrace.fromString('garbage\n\n   at foo.js:1:2\n#x y'),
          context: ErrorDescription('building X'),
        ),
      );

      expect(summary, 'While building X');
    });

    test('an exception whose toString throws still yields a summary', () {
      final String summary = debugErrorSummary(
        FlutterErrorDetails(
          exception: _ThrowsOnToString(),
          stack: StackTrace.fromString(_trace),
        ),
        firstInBurst: 'earlier',
      );

      expect(summary, startsWith('First error: earlier'));
    });

    test('a very long frame is cut short', () {
      final String member = 'M' * 1000;
      final String summary = debugErrorSummary(
        details(
          stack: StackTrace.fromString(
            '#0      $member (package:flutter/a.dart:1:1)\n',
          ),
        ),
      );

      expect(summary.length, lessThan(250));
    });
  });
}

class _ThrowsOnToString {
  @override
  String toString() => throw StateError('no description');
}
