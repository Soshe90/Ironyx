import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Haptic feedback, behind an interface.
///
/// ADR-6: platform capabilities degrade to a no-op rather than throwing.
/// `HapticFeedback` is unimplemented on web; calling it there produces a
/// `MissingPluginException` in some engine versions, so it is gated.
abstract interface class HapticsService {
  Future<void> selection();

  /// Interval boundary, set completed.
  Future<void> impact();

  /// Session start or finish. Deliberately heavier.
  Future<void> heavy();

  bool get isSupported;
}

class PlatformHapticsService implements HapticsService {
  const PlatformHapticsService({this.enabled = true});

  final bool enabled;

  @override
  bool get isSupported => !kIsWeb;

  @override
  Future<void> selection() => _guard(HapticFeedback.selectionClick);

  @override
  Future<void> impact() => _guard(HapticFeedback.mediumImpact);

  @override
  Future<void> heavy() => _guard(HapticFeedback.heavyImpact);

  Future<void> _guard(Future<void> Function() action) async {
    if (!enabled || !isSupported) {
      return;
    }
    try {
      await action();
    } on PlatformException {
      // A device without a vibrator is not an error worth surfacing.
    } on MissingPluginException {
      // Same.
    }
  }
}

/// No-op implementation. Used on web and in tests.
class NoopHapticsService implements HapticsService {
  const NoopHapticsService();

  @override
  bool get isSupported => false;

  @override
  Future<void> selection() async {}

  @override
  Future<void> impact() async {}

  @override
  Future<void> heavy() async {}
}

final Provider<HapticsService> hapticsServiceProvider =
    Provider<HapticsService>(
  (ref) => kIsWeb ? const NoopHapticsService() : const PlatformHapticsService(),
);
