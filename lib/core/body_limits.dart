/// Lowest and highest body measurements the app accepts from a form.
///
/// Wide enough not to exclude anyone real, narrow enough to catch a slip:
/// pounds typed as kilograms, a dropped decimal point, a weight typed into
/// the body-fat field. Shared by Personal details and the measurement
/// dialog on Progress, which both write the same `body_metrics` rows.
///
/// These bound what is typed, not what is stored: a row restored from a
/// backup or written by an older build may lie outside them.
library;

const double kMinBodyWeightKg = 25;
const double kMaxBodyWeightKg = 350;

const double kMinBodyFatPercentage = 2;
const double kMaxBodyFatPercentage = 70;
