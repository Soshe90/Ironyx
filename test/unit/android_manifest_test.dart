import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Scheduled timer notifications are armed with AlarmManager, and the alarm
/// is delivered to a receiver *the app's own manifest must declare* —
/// flutter_local_notifications' manifest carries permissions only. When the
/// receiver is missing, Android drops the broadcast without an error anywhere
/// and no scheduled notification ever appears. Nothing in the Dart test suite
/// can see that, so this pins it by reading the manifest itself.
void main() {
  late String manifest;

  setUpAll(() {
    final File file = File('android/app/src/main/AndroidManifest.xml');
    // Comments are stripped so prose that mentions a class name cannot
    // satisfy an assertion meant for the element.
    manifest = utf8
        .decode(file.readAsBytesSync(), allowMalformed: true)
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  });

  /// The full text of the `<receiver>` element whose class ends in [name].
  String receiver(String name) {
    final Match? match = RegExp(
      '<receiver\\b[^>]*$name[^>]*?(?:/>|>.*?</receiver>)',
      dotAll: true,
    ).firstMatch(manifest);
    expect(match, isNotNull, reason: 'AndroidManifest.xml declares no $name');
    return match!.group(0)!;
  }

  test('declares the alarm receiver, not exported', () {
    final String element = receiver('ScheduledNotificationReceiver');

    expect(
      element,
      contains(
        'com.dexterous.flutterlocalnotifications.'
        'ScheduledNotificationReceiver',
      ),
    );
    expect(element, contains('android:exported="false"'));
  });

  test('declares the boot receiver so pending notifications survive a reboot',
      () {
    final String element = receiver('ScheduledNotificationBootReceiver');

    expect(element, contains('android:exported="false"'));
    expect(element, contains('android.intent.action.BOOT_COMPLETED'));
    expect(element, contains('android.intent.action.MY_PACKAGE_REPLACED'));
  });

  test('holds the permissions those receivers and the timer rely on', () {
    for (final String permission in const <String>[
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.RECEIVE_BOOT_COMPLETED',
      'android.permission.WAKE_LOCK',
      // `NotificationService` uses exact alarms only when the OS allows them;
      // this is what makes it allow them from Android 13.
      'android.permission.USE_EXACT_ALARM',
    ]) {
      expect(
        manifest,
        contains('<uses-permission android:name="$permission"'),
        reason: '$permission is missing from AndroidManifest.xml',
      );
    }
  });

  test('requests SCHEDULE_EXACT_ALARM only where USE_EXACT_ALARM cannot apply',
      () {
    final Match? match = RegExp(
      r'<uses-permission\b[^>]*SCHEDULE_EXACT_ALARM[^>]*/?>',
      dotAll: true,
    ).firstMatch(manifest);

    expect(match, isNotNull, reason: 'Android 12/12L would get inexact alarms');
    // Uncapped, it would also be requested on Android 14+, where it is not
    // pre-granted and would need a settings-screen prompt the app lacks.
    expect(match!.group(0), contains('android:maxSdkVersion="32"'));
  });
}
