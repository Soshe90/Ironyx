/// Volume of one set in kilograms: load times reps, with no load counting
/// as none.
///
/// A weight below zero is assisted work: an assisted pull-up or dip logged
/// as "-20" (20 kg of help), which training logs and the XLSX import keep.
/// It moved no external load, so it adds nothing to volume; counted as
/// load times reps it took volume away, and a session of assisted pull-ups
/// lowered the week's total. Zero (bodyweight) adds nothing either.
///
/// The one rule for every volume in the app: a saved workout's total, the
/// live session, history, and the charts. The SQL equivalent is
/// [kSqlSetVolume].
double setVolumeKg(double weightKg, int reps) {
  if (weightKg <= 0 || reps <= 0) return 0;
  return weightKg * reps;
}

/// [setVolumeKg] in SQL, for a `workout_sets_table` aliased `ws`.
///
/// `MAX(x, 0)` with two arguments is SQLite's scalar maximum, not the
/// aggregate.
const String kSqlSetVolume = 'MAX(ws.weight_kg, 0) * MAX(ws.reps, 0)';
