/// Epley estimated one-rep max. Invalid measurements produce zero rather
/// than a negative or misleading estimate.
double epleyOneRepMax(double weightKg, int reps) {
  if (weightKg <= 0 || reps <= 0) return 0;
  if (reps == 1) return weightKg;
  return weightKg * (1 + reps / 30);
}

/// Volume for a completed set. Bodyweight sets have no external load and are
/// therefore excluded from kilogram volume charts.
/// Whether an estimated lift beats every prior recorded estimate.
bool isPersonalRecord(double estimate, Iterable<double> previous) =>
    estimate > 0 && previous.every((value) => estimate > value);

double setVolumeKg(double weightKg, int reps) {
  if (weightKg <= 0 || reps <= 0) return 0;
  return weightKg * reps;
}
