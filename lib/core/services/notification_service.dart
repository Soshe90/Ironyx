import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Local notifications for timer completion and background alerts (ADR-4).
///
/// ADR-6: on web this is a safe no-op. The platform implementation also
/// degrades gracefully if the plugin has not been configured for a platform
/// (for example, before platform scaffolding is generated).
abstract interface class NotificationService {
  /// Requests notification permission in context (first timer start).
  Future<bool> requestPermission();

  /// Re-checks permission — users revoke it in system settings.
  Future<bool> get isPermissionGranted;

  /// Shows the session-complete notification.
  Future<void> showCompletion({required String title, required String body});

  /// Schedules a phase-boundary notification. Implementations must be
  /// best-effort and never throw.
  Future<void> scheduleBoundary({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  });

  /// Schedules the session-complete notification for when the timer's final
  /// phase ends. [scheduleBoundary] announces the start of each following
  /// phase, so on its own the last phase's end would be silent: a locked
  /// phone would say nothing at exactly the moment the session finishes.
  /// Implementations must be best-effort and never throw.
  Future<void> scheduleCompletion({
    required DateTime at,
    required String title,
    required String body,
  });

  /// Cancels any pending timer notifications (called when a session ends or
  /// the app returns to the foreground).
  Future<void> cancelAll();
}

/// No-op implementation for web and tests.
class NoopNotificationService implements NotificationService {
  const NoopNotificationService();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<bool> get isPermissionGranted async => false;

  @override
  Future<void> showCompletion(
      {required String title, required String body}) async {}

  @override
  Future<void> scheduleBoundary({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> scheduleCompletion({
    required DateTime at,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancelAll() async {}
}

/// Platform implementation backed by `flutter_local_notifications`.
class PlatformNotificationService implements NotificationService {
  PlatformNotificationService() {
    _plugin = FlutterLocalNotificationsPlugin();
    _initialization = _initialize();
  }

  /// Fixed id for the session-complete notification. The controller numbers
  /// boundary notifications from 10000, so this stays clear of them, and a
  /// reschedule replaces the pending one instead of stacking a second.
  static const int _completionNotificationId = 20000;

  late final FlutterLocalNotificationsPlugin _plugin;
  late final Future<void> _initialization;
  bool _initialized = false;

  Future<void> _initialize() async {
    if (!kIsWeb) tz_data.initializeTimeZones();
    if (kIsWeb) return;
    const InitializationSettings settings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    try {
      await _plugin.initialize(settings);
      _initialized = true;
    } on Object {
      // A missing platform configuration (e.g. no Android drawable yet) must
      // not crash the timer. Permission and notifications simply stay off.
      _initialized = false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    await _initialization;
    if (kIsWeb) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final AndroidFlutterLocalNotificationsPlugin? android =
            _plugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final IOSFlutterLocalNotificationsPlugin? ios =
            _plugin.resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(alert: true, sound: true) ?? false;
      }
      return false;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> get isPermissionGranted async {
    await _initialization;
    if (kIsWeb || !_initialized) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final AndroidFlutterLocalNotificationsPlugin? android =
            _plugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        return await android?.areNotificationsEnabled() ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final IOSFlutterLocalNotificationsPlugin? ios =
            _plugin.resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        if (ios == null) return false;
        final NotificationsEnabledOptions? options =
            await ios.checkPermissions();
        return options?.isEnabled ?? false;
      }
      return false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> showCompletion({
    required String title,
    required String body,
  }) async {
    await _initialization;
    if (kIsWeb || !_initialized) return;
    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'timer_complete',
        'Timer completion',
        channelDescription: 'Shown when an interval timer finishes',
        importance: Importance.high,
        priority: Priority.high,
      ),
      // Explicit `present*: true`: iOS otherwise only shows a local
      // notification while the app is backgrounded — silently swallowing it
      // if fired while the timer screen is still open, which given a rest
      // timer someone is actively watching is the common case, not the edge
      // case. Android has no equivalent foreground/background distinction
      // for a shown notification.
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    try {
      await _plugin.show(0, title, body, details);
    } on Object {
      // Notifications are best-effort; a failure must not fail the timer.
    }
  }

  @override
  Future<void> scheduleBoundary({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    await _initialization;
    if (kIsWeb || !_initialized) return;
    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'timer_boundaries',
        'Timer phase changes',
        channelDescription: 'Shown when an interval timer changes phase',
        importance: Importance.high,
        priority: Priority.high,
      ),
      // See the matching comment in `showCompletion` — without this, a
      // boundary notification that fires while the timer screen is still
      // open on iOS is silently dropped rather than shown.
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    await _scheduleAt(
      id: id,
      at: at,
      title: title,
      body: body,
      details: details,
    );
  }

  @override
  Future<void> scheduleCompletion({
    required DateTime at,
    required String title,
    required String body,
  }) async {
    await _initialization;
    if (kIsWeb || !_initialized) return;
    // Same channel as `showCompletion`, so the user sees one "Timer
    // completion" switch in system settings rather than two.
    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'timer_complete',
        'Timer completion',
        channelDescription: 'Shown when an interval timer finishes',
        importance: Importance.high,
        priority: Priority.high,
      ),
      // See the matching comment in `showCompletion`.
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    await _scheduleAt(
      id: _completionNotificationId,
      at: at,
      title: title,
      body: body,
      details: details,
    );
  }

  Future<void> _scheduleAt({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required NotificationDetails details,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(at, tz.local),
        details,
        androidScheduleMode: await _scheduleMode(),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } on Object {
      // Notifications are best-effort; a failure must not fail the timer.
    }
  }

  /// Exact when the OS lets this app schedule exact alarms, inexact otherwise.
  ///
  /// The difference is user-visible: an inexact alarm can be delivered tens of
  /// seconds late (measured at 14 s for a 20 s boundary), which is longer
  /// than a Tabata rest. Exact scheduling needs an exact-alarm permission in
  /// the manifest *and* the OS having granted it, so this asks the OS rather
  /// than assuming — and falls back rather than throwing, so a build without
  /// the permission behaves exactly as it did before.
  Future<AndroidScheduleMode> _scheduleMode() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
    try {
      final AndroidFlutterLocalNotificationsPlugin? android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final bool exact =
          await android?.canScheduleExactNotifications() ?? false;
      return exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } on Object {
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
  }

  @override
  Future<void> cancelAll() async {
    await _initialization;
    if (kIsWeb || !_initialized) return;
    try {
      await _plugin.cancelAll();
    } on Object {
      // Ignore.
    }
  }
}

final Provider<NotificationService> notificationServiceProvider =
    Provider<NotificationService>(
  (ref) =>
      kIsWeb ? const NoopNotificationService() : PlatformNotificationService(),
);
