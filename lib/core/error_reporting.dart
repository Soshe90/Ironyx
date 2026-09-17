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
