import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen awake during an active timer session (ADR-4).
///
/// ADR-6: on web there is no wakelock, so the web implementation is a safe
/// no-op rather than a throwing platform call.
abstract interface class WakelockService {
  Future<void> enable();
  Future<void> disable();
}

class PlatformWakelockService implements WakelockService {
  const PlatformWakelockService();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}

class NoopWakelockService implements WakelockService {
  const NoopWakelockService();

  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}

final Provider<WakelockService> wakelockServiceProvider =
    Provider<WakelockService>(
  (ref) =>
      kIsWeb ? const NoopWakelockService() : const PlatformWakelockService(),
);
