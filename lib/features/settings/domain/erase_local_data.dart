import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_reporting.dart';
import '../../../core/providers.dart';
import '../../backup/domain/cloud_backup_controller.dart';
import '../../tracker/domain/active_workout_notifier.dart';

/// A step of [eraseLocalData] after the database delete.
enum EraseStep { snapshots, openWorkout, builtInPrograms }

/// The database was erased, but [failed] steps did not finish.
///
/// Each step is safe to run again, so erasing again finishes the job.
class EraseIncompleteException implements Exception {
  const EraseIncompleteException(this.failed);

  final List<EraseStep> failed;

  @override
  String toString() =>
      'EraseIncompleteException(${failed.map((s) => s.name).join(', ')})';
}

/// Removes everything of the user's from this device: the database's user
/// data, the import snapshots, and an open workout; then brings back the
/// built-in programs.
///
/// One function for Settings' "Delete all data" and the account-conflict
/// "erase and continue", which each had their own copy of the steps and
/// both left the same things behind: the snapshots every import keeps (a
/// full copy of the data, name and email included, which Restore snapshot
/// could bring straight back) and the open workout, which is kept outside
/// the database.
///
/// The snapshot folder is found first, so a failure there stops it before
/// anything is deleted. The database delete comes next; if it fails,
/// nothing else is touched and its error is rethrown, so the snapshots stay
/// as a way back to data that is still there.
///
/// After it, each remaining step runs whether or not the one before it
/// failed. They stopped at the first failure, so a snapshot that could not
/// be deleted also left the open workout (and its sets) on the phone. A
/// failure is logged and the function ends with [EraseIncompleteException]
/// naming what is left, rather than either a false "deleted" or a
/// misleading "nothing happened".
Future<void> eraseLocalData(WidgetRef ref) async {
  final String snapshotDir = await ref.read(snapshotDirectoryProvider.future);
  await ref.read(dataExportServiceProvider).deleteAllUserData(
        ref.read(appDatabaseProvider),
      );

  final List<EraseStep> failed = <EraseStep>[];
  Future<void> attempt(EraseStep step, Future<void> Function() run) async {
    try {
      await run();
    } catch (error, stackTrace) {
      reportError(error, stackTrace, context: 'eraseLocalData.${step.name}');
      failed.add(step);
    }
  }

  await attempt(
    EraseStep.snapshots,
    () => ref.read(dataExportServiceProvider).deleteSnapshots(snapshotDir),
  );
  await attempt(
    EraseStep.openWorkout,
    () => ref.read(activeWorkoutProvider.notifier).discard(),
  );
  // Programs (built-in and user) were deleted along with their templates:
  // reset the seed marker and reseed so the built-ins come back, the same
  // way the exercise catalogue survives.
  //
  // This exact reset -> invalidate -> read(...future) sequence once produced
  // a hung `Future` in a widget test under a specific pump interleaving,
  // while `programSeederProvider` was also watched app-wide by `app.dart`.
  // It has not reproduced against the real flow, so it looks like a
  // test-harness artefact, but it was never fully explained. See TODO.md's
  // A2.14 for the reproduction, in case this ever hangs for real.
  await attempt(EraseStep.builtInPrograms, () async {
    await ref.read(programSeederProvider.notifier).resetSeedVersion();
    ref.invalidate(programSeederProvider);
    await ref.read(programSeederProvider.future);
  });

  if (failed.isNotEmpty) throw EraseIncompleteException(failed);
}
