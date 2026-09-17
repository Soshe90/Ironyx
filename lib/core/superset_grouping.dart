// Pure helpers for superset grouping.
//
// Supersets are stored as a nullable grouping key on each exercise (see
// `TemplateExercisesTable.supersetGroupId` and
// `WorkoutExercisesTable.supersetGroupId`). Exercises sharing the same
// non-null key are performed back-to-back. Rendering needs to translate
// that key back into a human-facing letter within each contiguous run —
// standalone exercises get no letter.

/// Maps each exercise's [groupIds] to a letter label ("A", "B", …) within
/// its contiguous run, or null for standalone exercises.
///
/// [groupIds] is ordered the same way the exercises are displayed. A run is
/// the maximal stretch of consecutive equal non-null ids; each run starts
/// its lettering over at "A". This keeps a superset labelled "A / B / C"
/// even after unrelated exercises are added before it, and degrades safely
/// if a user manually drags members apart (each fragment re-letters on its
/// own).
List<String?> supersetLabels(List<String?> groupIds) {
  final labels = List<String?>.filled(groupIds.length, null);
  var i = 0;
  while (i < groupIds.length) {
    final groupId = groupIds[i];
    if (groupId == null) {
      i++;
      continue;
    }
    var runLength = 0;
    while (
        i + runLength < groupIds.length && groupIds[i + runLength] == groupId) {
      runLength++;
    }
    for (var j = 0; j < runLength; j++) {
      labels[i + j] = _letter(j);
    }
    i += runLength;
  }
  return labels;
}

String _letter(int index) => String.fromCharCode(65 + (index % 26));
