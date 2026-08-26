import 'dart:convert';
import 'dart:io';

import 'package:fittrack/features/library/domain/exercise_catalogue_ar.dart';
import 'package:fittrack/features/library/domain/exercise_catalogue_l10n.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the Arabic catalogue tables against seed drift.
///
/// The tables are keyed by slug and id rather than by row id, so a reseed
/// that renames or drops one would not fail to compile — those exercises
/// would just quietly render in English again. This is the thing that
/// notices.
void main() {
  late Map<String, dynamic> seed;

  setUpAll(() {
    seed = jsonDecode(
      File('assets/data/exercises_seed.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  Set<String> idsOf(String collection) => <String>{
        for (final dynamic row in seed[collection] as List<dynamic>)
          (row as Map<String, dynamic>)[
              collection == 'exercises' ? 'slug' : 'id'] as String,
      };

  group('Arabic exercise catalogue', () {
    test('translates every seeded exercise', () {
      expect(kExerciseNamesAr.keys.toSet(), idsOf('exercises'));
    });

    test('translates every seeded muscle group', () {
      expect(kMuscleNamesAr.keys.toSet(), idsOf('muscles'));
    });

    test('translates every seeded equipment type', () {
      expect(kEquipmentNamesAr.keys.toSet(), idsOf('equipment'));
    });

    test('translates every seeded exercise instruction', () {
      final List<dynamic> exercises = seed['exercises'] as List<dynamic>;
      expect(kExerciseInstructionsAr.keys.toSet(), idsOf('exercises'));

      for (final dynamic value in exercises) {
        final Map<String, dynamic> exercise = value as Map<String, dynamic>;
        final String slug = exercise['slug'] as String;
        final List<dynamic> source = exercise['instructions'] as List<dynamic>;
        final List<String> translated = kExerciseInstructionsAr[slug]!;
        expect(translated.length, source.length, reason: slug);
        for (final String step in translated) {
          expect(step.trim(), isNotEmpty, reason: slug);
        }
      }
    });

    test('has no blank translations', () {
      for (final MapEntry<String, String> entry in <MapEntry<String, String>>[
        ...kExerciseNamesAr.entries,
        ...kMuscleNamesAr.entries,
        ...kEquipmentNamesAr.entries,
      ]) {
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      }
    });

    test('translates the instructions for every seeded exercise', () {
      expect(kExerciseInstructionsAr.keys.toSet(), idsOf('exercises'));
    });

    test('keeps instruction step counts identical to the seed', () {
      // `localizedExerciseInstructions` falls back to the stored English as a
      // whole when the counts differ, so a mismatch here silently reverts
      // that exercise rather than showing half-translated steps.
      for (final dynamic row in seed['exercises'] as List<dynamic>) {
        final Map<String, dynamic> exercise = row as Map<String, dynamic>;
        final String slug = exercise['slug'] as String;
        final List<dynamic> english =
            (exercise['instructions'] as List<dynamic>?) ?? <dynamic>[];
        expect(
          kExerciseInstructionsAr[slug]?.length,
          english.length,
          reason: slug,
        );
      }
    });

    test('leaves no name still in Latin script', () {
      // Catches a row copy-pasted from the seed and never translated. Latin
      // letters are the signal — digits and punctuation are fine, and some
      // names legitimately keep a Latin token (bar "EZ", "T", "V").
      final RegExp latinWord = RegExp(r'[A-Za-z]{3,}');
      for (final MapEntry<String, String> entry in kExerciseNamesAr.entries) {
        expect(
          latinWord.hasMatch(entry.value),
          isFalse,
          reason: '${entry.key} still reads "${entry.value}"',
        );
      }
    });
  });
}
