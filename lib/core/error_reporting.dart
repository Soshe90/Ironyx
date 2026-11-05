import 'package:flutter/foundation.dart';

/// The single place every otherwise-uncaught error in the app passes
/// through, wired up in `main()` for [FlutterError.onError],
/// [PlatformDispatcher.instance.onError] and [ErrorWidget.builder].
///
/// Today this only logs, gated by [kDebugMode] the same way
/// `SupabaseAuthService._log` already is — an auth error can carry an email
/// address, and a release build must not write that anywhere. There is no
/// crash reporter wired up yet (see TODO.md's "Crash reporting" item); when
/// one is provisioned, it plugs in here and nowhere else needs to change,
/// since every call site already funnels through this function instead of
/// its own `debugPrint`.
void reportError(Object error, StackTrace? stackTrace, {String? context}) {
  if (!kDebugMode) return;
  final String label = context == null ? '[error]' : '[error] [$context]';
  debugPrint('$label $error');
  if (stackTrace != null) debugPrint('$stackTrace');
}

/// Remembers the first error of a burst, for the debug error screen.
///
/// One fault often throws several times within a frame or two, and the
/// error screen shows whichever of them replaced the most of the screen,
/// which is usually the last. Seen in practice: a text controller used
/// after disposal, followed by Flutter's `_dependents.isEmpty` assertion
/// while the broken route was torn down. The screen showed only the
/// assertion, which says nothing about the cause; the first error named it.
///
/// A burst is a run of errors each within [gap] of the one before.
class ErrorBurst {
  ErrorBurst({
    this.gap = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration gap;
  final DateTime Function() _now;

  String? _first;
  DateTime? _lastAt;

  /// Notes that [error] was just reported.
  void record(Object error) {
    final DateTime at = _now();
    if (_isStale(at)) _first = _firstLine(error);
    _lastAt = at;
  }

  /// The first error of the burst still in progress, or null when there is
  /// none or when it is [error] itself (nothing came before it).
  String? firstOtherThan(Object error) {
    if (_isStale(_now())) return null;
    final String? first = _first;
    return first == null || first == _firstLine(error) ? null : first;
  }

  bool _isStale(DateTime at) {
    final DateTime? last = _lastAt;
    return last == null || at.difference(last) > gap;
  }

  static String _firstLine(Object error) {
    final String line = '$error'.trim().split('\n').first.trim();
    return line.length <= _maxLineLength
        ? line
        : '${line.substring(0, _maxLineLength)}…';
  }
}

/// How many stack frames the debug error screen lists. Enough to see where
/// the error was thrown from; the whole trace is in the console.
const int _maxStackFrames = 6;

/// Longest single line of the summary. A widget's description can run to
/// hundreds of characters (an `Overlay` lists every entry it holds).
const int _maxLineLength = 120;

/// The app's own code, as it appears in a stack frame.
const String _appPackagePrefix = 'package:ironyx/';

final RegExp _stackFrame = RegExp(r'^#\d+\s+(.+?)\s+\((.+)\)$');
final RegExp _dartFileAndLine = RegExp(r'([^/\\]+\.dart):(\d+)(?::\d+)?$');

/// Flutter prints the blamed widget as its name on one line and
/// `Name:file:///path/to/file.dart:line:column` on the next.
final RegExp _relevantWidget = RegExp(
  r'The relevant error-causing widget was:\s+([^\s:]+)'
  r'(?:[^\n]*\n){0,2}?[^\n]*?([^/\\\s:]+\.dart):(\d+)',
);

/// What the debug error screen shows under the exception text: what came
/// first, what the framework was doing, which widget it blames and the top
/// of the stack. Enough that a screenshot of the screen can be diagnosed
/// without the console it was printed to.
///
/// Debug builds only. A release build must not put any of this on screen
/// (see [reportError]). Never throws: this runs while showing an error.
String debugErrorSummary(FlutterErrorDetails details, {String? firstInBurst}) {
  final List<String> lines = <String>[];
  try {
    if (firstInBurst != null) lines.add('First error: $firstInBurst');

    final String? doing = details.context?.toDescription();
    if (doing != null && doing.isNotEmpty) lines.add('While ${_cap(doing)}');

    // The widget the framework blames is not a field of the details; the
    // inspector adds it while the details are rendered as text.
    final RegExpMatch? widget = _relevantWidget.firstMatch(
      details.toString(minLevel: DiagnosticLevel.info),
    );
    if (widget != null) {
      lines.add('Widget: ${widget[1]} (${widget[2]}:${widget[3]})');
    }

    lines.addAll(_topFrames(details.stack));
  } on Object catch (_) {
    // Whatever was gathered before the failure is still worth showing.
  }
  return lines.join('\n');
}

/// The first [_maxStackFrames] frames that are not Dart runtime internals,
/// then the first frame in the app's own code if it was not among them.
List<String> _topFrames(StackTrace? stack) {
  if (stack == null) return const <String>[];
  final List<String> shown = <String>[];
  String? firstAppFrame;
  bool appFrameShown = false;

  for (final String raw in stack.toString().split('\n')) {
    final RegExpMatch? frame = _stackFrame.firstMatch(raw.trim());
    if (frame == null) continue;
    final String location = frame[2]!;
    if (location.startsWith('dart:')) continue;

    final RegExpMatch? file = _dartFileAndLine.firstMatch(location);
    final String where = file == null ? location : '${file[1]}:${file[2]}';
    final String line = _cap('${frame[1]} ($where)');
    final bool isApp = location.startsWith(_appPackagePrefix);

    if (shown.length < _maxStackFrames) {
      shown.add(line);
      appFrameShown = appFrameShown || isApp;
    } else if (isApp) {
      firstAppFrame = line;
      break;
    }
  }
  if (!appFrameShown && firstAppFrame != null) {
    shown.add('App: $firstAppFrame');
  }
  return shown;
}

String _cap(String text) => text.length <= _maxLineLength
    ? text
    : '${text.substring(0, _maxLineLength)}…';
