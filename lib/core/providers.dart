import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/data_export_service.dart';
import 'services/program_import_service.dart';

export 'database/database_providers.dart';
export 'services/exercise_seeder.dart';
export 'services/program_seeder.dart';

/// Overridden in `main()` once [SharedPreferences] has been resolved.
///
/// Declared by hand rather than generated: the instance is supplied from
/// outside the container, so there is nothing for a generator to build.
final Provider<SharedPreferences> sharedPreferencesProvider =
    Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in ProviderScope',
  ),
);

/// Stateless — no dependencies to inject, just a seam for tests to override.
final Provider<DataExportService> dataExportServiceProvider =
    Provider<DataExportService>((ref) => const DataExportService());

/// Stateless CSV-to-programs importer.
final Provider<ProgramImportService> programImportServiceProvider =
    Provider<ProgramImportService>((ref) => const ProgramImportService());
