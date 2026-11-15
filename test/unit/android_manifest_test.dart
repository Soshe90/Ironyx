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

  // Not the manifest, but the same kind of guard: a build-file rule no Dart
  // test can observe. Without the suffix, a debug or on-device test build
  // replaces a release install of the real app and Android deletes its data
  // with it. That happened once (2026-09-29); the real proof is the checks
  // in scripts/run_device_tests.sh, and this keeps the rule from going.
  test('debug builds get their own application id', () {
    final String gradle = File('android/app/build.gradle.kts')
        .readAsStringSync()
        .replaceAll(RegExp(r'//[^\n]*'), '');

    expect(gradle, contains('applicationId = "com.soshe90.ironyx"'));
    expect(
      RegExp(r'debug\s*\{\s*applicationIdSuffix = "\.debug"').hasMatch(gradle),
      isTrue,
      reason: 'buildTypes.debug must set applicationIdSuffix = ".debug"',
    );
    // Release keeps the store id.
    final String release =
        RegExp(r'release\s*\{.*', dotAll: true).firstMatch(gradle)!.group(0)!;
    expect(release, isNot(contains('applicationIdSuffix')));
  });

  // The 2026-11-15 rename to Liftanium changed only what users read. The
  // launcher label is set outside Dart, so nothing else notices if it drifts
  // from the in-app title. The ids must NOT follow the name: Play ties the
  // listing to the application id for good, and the auth deep-link scheme
  // is on the Supabase redirect allow-list.
  test('launcher names match the app title; store ids and scheme do not move',
      () {
    final Map<String, dynamic> arb =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final String title = arb['appTitle'] as String;
    expect(title, 'Liftanium');

    expect(manifest, contains('android:label="$title"'));
    expect(manifest, contains('android:scheme="com.soshe90.ironyx"'));

    final String plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      RegExp('<key>CFBundleDisplayName</key>\\s*<string>$title</string>')
          .hasMatch(plist),
      isTrue,
      reason: 'iOS CFBundleDisplayName must match appTitle',
    );
    expect(plist, contains('<string>com.soshe90.ironyx</string>'));
  });

  // The icon vectors are written by scripts/build_app_icons.py. Android
  // draws the status-bar and themed icons as an alpha mask, so a second
  // colour in them shows as nothing, or a solid blob, on the phone only.
  test('icon vectors are generated, and the mask icons are single-colour', () {
    String vector(String name) =>
        File('android/app/src/main/res/drawable/$name.xml').readAsStringSync();
    Set<String> fills(String xml) => RegExp(r'android:fillColor="([^"]+)"')
        .allMatches(xml)
        .map((m) => m.group(1)!)
        .toSet();

    for (final String name in <String>[
      'ic_launcher_foreground',
      'ic_launcher_monochrome',
      'ic_notification',
    ]) {
      expect(vector(name), contains('GENERATED by scripts/build_app_icons.py'),
          reason: '$name.xml was edited by hand; edit the script instead');
    }
    for (final String name in <String>[
      'ic_launcher_monochrome',
      'ic_notification',
    ]) {
      expect(fills(vector(name)), <String>{'#FFFFFF'}, reason: name);
      expect(vector(name), contains('android:fillType="evenOdd"'),
          reason: '$name needs the L as a hole');
    }
  });
}
