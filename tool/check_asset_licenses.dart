// Fails the build if the exercise catalogue ships an asset we cannot prove
// we are allowed to redistribute.
//
// The catalogue previously accumulated 41 entries with `"license": null`
// and 49 images hotlinked straight off liftmanual.com, and nothing noticed
// for months — there was no file recording what came from where, so the
// only way to spot it was to read the seed by hand. That is the failure
// this guards: not a licence violation someone argues about, but a licence
// violation nobody can see.
//
// Run: dart run tool/check_asset_licenses.dart

import 'dart:convert';
import 'dart:io';

const String seedPath = 'assets/data/exercises_seed.json';
const String imageRoot = 'assets/images/exercises';
const String licenseDoc = 'ASSETS-LICENSE.md';

/// Source names whose licence terms are recorded in [licenseDoc] and which
/// are cleared for commercial redistribution. Adding a name here without
/// adding it to that file is the mistake this list exists to make visible.
const Set<String> allowedSources = <String>{'free-exercise-db'};

void main() {
  final List<String> failures = <String>[];

  final File seedFile = File(seedPath);
  if (!seedFile.existsSync()) {
    stderr.writeln('$seedPath not found — run from the repository root.');
    exit(2);
  }

  final Map<String, dynamic> seed =
      jsonDecode(seedFile.readAsStringSync()) as Map<String, dynamic>;
  final List<dynamic> exercises = seed['exercises'] as List<dynamic>;

  final Set<String> referenced = <String>{};

  for (final dynamic raw in exercises) {
    final Map<String, dynamic> exercise = raw as Map<String, dynamic>;
    final String name = exercise['name'] as String;

    final List<dynamic> sources =
        exercise['sources'] as List<dynamic>? ?? const <dynamic>[];
    if (sources.isEmpty) {
      failures.add('$name: no sources recorded');
    }
    for (final dynamic rawSource in sources) {
      final Map<String, dynamic> source = rawSource as Map<String, dynamic>;
      final String sourceName = source['sourceName'] as String? ?? '<unnamed>';
      final String? license = source['license'] as String?;
      if (license == null || license.isEmpty) {
        failures.add('$name: source "$sourceName" has no licence');
      }
      if (!allowedSources.contains(sourceName)) {
        failures.add(
          '$name: source "$sourceName" is not in the cleared list '
          '(add it to $licenseDoc and to allowedSources here)',
        );
      }
    }

    final List<dynamic> media =
        exercise['media'] as List<dynamic>? ?? const <dynamic>[];
    for (final dynamic rawMedia in media) {
      final Map<String, dynamic> item = rawMedia as Map<String, dynamic>;
      if (item['type'] != 'image') continue;

      final String? localAsset = item['localAsset'] as String?;
      final String? url = item['url'] as String?;

      // A remote image is someone else's bandwidth and someone else's
      // copyright, served live to every user. Bundle it or drop it.
      if (url != null && url.isNotEmpty) {
        failures.add('$name: image is hotlinked from $url');
      }
      if (localAsset == null || localAsset.isEmpty) {
        if (url == null || url.isEmpty) {
          failures.add('$name: image entry has neither a file nor a url');
        }
        continue;
      }

      referenced.add(localAsset);
      if (!File(localAsset).existsSync()) {
        failures.add('$name: image file is missing: $localAsset');
      }
      final String? license = item['license'] as String?;
      if (license == null || license.isEmpty) {
        failures.add('$name: image $localAsset has no licence');
      }
    }
  }

  // Anything on disk but unreferenced is an asset we ship, pay download
  // size for, and have no provenance record for.
  final Directory images = Directory(imageRoot);
  if (images.existsSync()) {
    for (final FileSystemEntity entity in images.listSync(recursive: true)) {
      if (entity is! File) continue;
      final String path = entity.path;
      if (path.endsWith('.gitkeep')) continue;
      if (!referenced.contains(path)) {
        failures.add('unreferenced image ships in the APK: $path');
      }
    }
  }

  if (!File(licenseDoc).existsSync()) {
    failures.add('$licenseDoc is missing — attribution has to live somewhere');
  }

  if (failures.isEmpty) {
    stdout.writeln(
      'Asset licences OK: ${exercises.length} exercises, '
      '${referenced.length} images, all cleared for redistribution.',
    );
    return;
  }

  stderr.writeln('Asset licence check failed (${failures.length}):');
  for (final String failure in failures) {
    stderr.writeln('  - $failure');
  }
  exit(1);
}
