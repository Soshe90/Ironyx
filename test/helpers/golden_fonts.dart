import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the app's bundled Barlow faces, plus Roboto and MaterialIcons from
/// the SDK, so the screenshots show text and icons instead of the test
/// font's filled boxes.
Future<void> loadGoldenFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The same files `pubspec.yaml` ships; tests run from the project root.
  Future<void> loadBundled(String family, List<String> files) async {
    final FontLoader loader = FontLoader(family);
    for (final String file in files) {
      loader.addFont(Future<ByteData>.value(
        ByteData.sublistView(File('assets/fonts/$file').readAsBytesSync()),
      ));
    }
    await loader.load();
  }

  await loadBundled('Barlow', <String>[
    'Barlow-Regular.ttf',
    'Barlow-Medium.ttf',
    'Barlow-SemiBold.ttf',
    'Barlow-Bold.ttf',
  ]);
  await loadBundled('BarlowCondensed', <String>[
    'BarlowCondensed-SemiBold.ttf',
    'BarlowCondensed-Bold.ttf',
  ]);

  final String? root = _flutterRoot();
  if (root == null) return;
  final Directory dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;

  Future<void> load(String family, List<String> files) async {
    final FontLoader loader = FontLoader(family);
    var any = false;
    for (final String file in files) {
      final File f = File('${dir.path}/$file');
      if (!f.existsSync()) continue;
      loader.addFont(Future<ByteData>.value(
        ByteData.sublistView(f.readAsBytesSync()),
      ));
      any = true;
    }
    if (any) await loader.load();
  }

  await load('Roboto', <String>[
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', <String>['MaterialIcons-Regular.otf']);
}

String? _flutterRoot() {
  // `which flutter` resolves through the snap wrapper, so derive the root
  // from the running Dart executable instead.
  final String exe = Platform.resolvedExecutable;
  final int i = exe.indexOf('/bin/cache/dart-sdk');
  return i < 0 ? Platform.environment['FLUTTER_ROOT'] : exe.substring(0, i);
}
