import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/features/settings/domain/export_envelope.dart';
import 'package:ironyx/features/settings/presentation/import_problem_messages.dart';
import 'package:ironyx/l10n/app_localizations.dart';

/// Every refusal reads in the user's language, not as the English detail.
void main() {
  test('each kind has its own sentence, in English and Arabic', () async {
    final AppLocalizations en =
        await AppLocalizations.delegate.load(const Locale('en'));
    final AppLocalizations ar =
        await AppLocalizations.delegate.load(const Locale('ar'));
    final Set<String> english = <String>{};
    for (final ImportProblem problem in ImportProblem.values) {
      final ImportValidationException e = ImportValidationException(
        'English detail for the log',
        problem: problem,
        subject: 'My Row',
      );
      english.add(e.messageFor(en));
      expect(e.messageFor(ar), isNot(contains('English detail')));
      expect(e.messageFor(ar), matches(RegExp('[\u0600-\u06FF]')),
          reason: '$problem in Arabic');
    }
    expect(english, hasLength(ImportProblem.values.length));
    expect(
      ImportValidationException('x',
              problem: ImportProblem.exerciseConflict, subject: 'My Row')
          .messageFor(ar),
      contains('My Row'),
    );
  });
}
