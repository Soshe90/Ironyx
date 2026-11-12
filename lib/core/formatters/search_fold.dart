/// Matching typed text against names, in English or Arabic.
///
/// Used where the names searched are the ones shown, which for Arabic are
/// translations the database does not hold, so the match is made in memory:
/// the Progress lift picker, and the Library's search when the query is in
/// Arabic.
library;

/// [text] reduced to what a search should compare: lower case, and for
/// Arabic without diacritics or tatweel, with the alef, yeh, waw and teh
/// marbuta variants a keyboard may or may not produce folded together.
String foldForSearch(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[ً-ٰٟـ]'), '')
    .replaceAll(RegExp('[آأإٱ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ئ', 'ي')
    .replaceAll('ؤ', 'و')
    .replaceAll('ة', 'ه');

/// Whether every word of [query] appears in one of [names], after
/// [foldForSearch]. Words may come in any order ("bench barbell" finds
/// "Barbell Bench Press"); an empty query matches everything.
bool matchesSearch(String query, Iterable<String> names) {
  final List<String> words = foldForSearch(query)
      .split(RegExp(r'\s+'))
      .where((String w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return true;
  final List<String> folded = <String>[for (final n in names) foldForSearch(n)];
  return folded.any((String name) => words.every(name.contains));
}

/// Whether [text] has any Arabic letter: the cue that a search is for a
/// translated name, which only an in-memory match can find.
bool containsArabic(String text) => _arabic.hasMatch(text);

final RegExp _arabic = RegExp('[؀-ۿݐ-ݿ]');
