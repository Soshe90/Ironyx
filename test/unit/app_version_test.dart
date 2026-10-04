import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/services/data_export_service.dart';

/// `kAppVersion` is a hand-kept copy of the pubspec version (see its doc
/// comment). It is written into every export and shown on the licences
/// page, so a release that bumps one and not the other ships a wrong
/// version in both places.
void main() {
  test('kAppVersion matches the version name in pubspec.yaml', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? match =
        RegExp(r'^version:\s*([^+\s]+)', multiLine: true).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml has no version line');
    expect(kAppVersion, match!.group(1));
  });
}
