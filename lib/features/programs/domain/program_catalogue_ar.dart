/// Arabic display names for the seeded built-in programs and their days.
///
/// Kept out of the ARB files for the same reason as
/// `exercise_catalogue_ar.dart`: these are catalogue *data*, keyed by the
/// stable ids `ProgramSeeder` mints, not UI chrome — they change when the
/// seed changes rather than when the copy does.
///
/// Only the three built-in programs are here. A user-created program (or a
/// built-in one the user has edited, which clears `isBuiltIn` — see
/// `ProgramEditorController`'s doc comment) has no entry, and correctly
/// falls back to its own stored name: that text is exactly what the user
/// typed, and translating it would show them words they never wrote.
library;

/// Program display name by `ProgramsTable.id`.
const Map<String, String> kProgramNamesAr = <String, String>{
  'builtin_full_body': 'الجسم بالكامل',
  'builtin_upper_lower': 'علوي / سفلي',
  'builtin_ppl': 'دفع / سحب / أرجل',
};

/// Day display name by `ProgramDay.templateId`.
const Map<String, String> kProgramDayNamesAr = <String, String>{
  'builtin_fb_a': 'التمرين أ',
  'builtin_fb_b': 'التمرين ب',
  'builtin_fb_c': 'التمرين ج',
  'builtin_ul_upper_a': 'علوي أ',
  'builtin_ul_lower_a': 'سفلي أ',
  'builtin_ul_upper_b': 'علوي ب',
  'builtin_ul_lower_b': 'سفلي ب',
  'builtin_ppl_push': 'يوم الدفع',
  'builtin_ppl_pull': 'يوم السحب',
  'builtin_ppl_legs': 'يوم الأرجل',
};
