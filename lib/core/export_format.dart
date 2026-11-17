import '../data/models.dart';

/// One CSV field, quoted when it holds a comma, quote or line break.
String csvField(String value) {
  final needsQuotes = value.contains(RegExp(r'[",\n\r]'));
  return needsQuotes ? '"${value.replaceAll('"', '""')}"' : value;
}

/// word,meaning,page — opens in any spreadsheet and imports into most
/// flashcard apps.
String wordsToCsv(List<SavedWord> words) => [
  'word,meaning,page',
  for (final w in words)
    '${csvField(w.word)},${csvField(w.meaning ?? '')},${w.page}',
].join('\n');

/// "word — meaning" per line (just the word when there is no meaning yet).
String wordsWithMeanings(List<SavedWord> words) => [
  for (final w in words)
    w.meaning == null ? w.word : '${w.word} — ${w.meaning}',
].join('\n');
