import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_book_reader/core/dictionary_service.dart';
import 'package:pdf_book_reader/core/export_format.dart';
import 'package:pdf_book_reader/data/models.dart';
import 'package:pdf_book_reader/data/reading_stats.dart';
import 'package:pdf_book_reader/features/library/library_sort.dart';

Book _book(int id, String title, int lastPage) => Book(
  id: id,
  title: title,
  filePath: '/tmp/$id.pdf',
  lastPage: lastPage,
  pageCount: 10,
);

ReadingDay _day(DateTime d, {int pages = 5, int seconds = 300}) => ReadingDay(
  day: DateTime(d.year, d.month, d.day),
  pages: pages,
  seconds: seconds,
);

void main() {
  group('reading stats', () {
    final now = DateTime(2026, 11, 15, 20);
    DateTime ago(int days) => DateTime(2026, 11, 15 - days);

    test('streak counts consecutive days ending today', () {
      final stats = ReadingStats.compute([
        _day(ago(0)),
        _day(ago(1)),
        _day(ago(2)),
        _day(ago(4)), // gap: not part of the streak
      ], now);
      expect(stats.streak, 3);
    });

    test('streak is kept alive when only today is still empty', () {
      final stats = ReadingStats.compute([_day(ago(1)), _day(ago(2))], now);
      expect(stats.streak, 2);
    });

    test('streak is 0 after a missed day', () {
      expect(ReadingStats.compute([_day(ago(2))], now).streak, 0);
    });

    test('last seven days are filled, oldest first, ending today', () {
      final stats = ReadingStats.compute([_day(ago(0), pages: 9)], now);
      expect(stats.lastSeven.length, 7);
      expect(stats.lastSeven.last.pages, 9);
      expect(stats.lastSeven.first.pages, 0);
      expect(stats.today.pages, 9);
    });

    test('totals add up across days', () {
      final stats = ReadingStats.compute([
        _day(ago(0), pages: 4, seconds: 60),
        _day(ago(30), pages: 6, seconds: 120),
      ], now);
      expect(stats.totalPages, 10);
      expect(stats.totalSeconds, 180);
      expect(stats.activeDays, 2);
    });

    test('dayKey and duration formatting', () {
      expect(dayKey(DateTime(2026, 3, 5)), '2026-03-05');
      expect(formatDuration(0), '0 min');
      expect(formatDuration(42 * 60), '42 min');
      expect(formatDuration(65 * 60), '1 h 05 min');
    });
  });

  group('export formats', () {
    const words = [
      SavedWord(
        id: 1,
        page: 3,
        word: 'ephemeral',
        meaning: '(adj) short, brief',
      ),
      SavedWord(id: 2, page: 8, word: 'quote"d'),
    ];

    test('csv quotes commas and quotes', () {
      expect(
        wordsToCsv(words),
        'word,meaning,page\n'
        'ephemeral,"(adj) short, brief",3\n'
        '"quote""d",,8',
      );
    });

    test('words with meanings', () {
      expect(
        wordsWithMeanings(words),
        'ephemeral — (adj) short, brief\nquote"d',
      );
    });
  });

  group('dictionary', () {
    test('picks the first usable definition', () {
      const body =
          '[{"word":"run","meanings":['
          '{"partOfSpeech":"verb","definitions":[{"definition":"To move fast."}]}'
          ']}]';
      expect(parseDefinition(body), '(verb) To move fast.');
    });

    test('returns null for errors and junk', () {
      expect(parseDefinition('{"title":"No Definitions Found"}'), isNull);
      expect(parseDefinition('not json'), isNull);
      expect(parseDefinition('[]'), isNull);
    });

    test('only single words are looked up', () {
      expect(DictionaryService.canLookUp('ephemeral'), isTrue);
      expect(DictionaryService.canLookUp("don't"), isTrue);
      expect(DictionaryService.canLookUp('“ephemeral,”'), isTrue);
      expect(DictionaryService.lookupWord('“ephemeral,”'), 'ephemeral');
      expect(DictionaryService.canLookUp('two words'), isFalse);
      expect(DictionaryService.canLookUp('123'), isFalse);
    });
  });

  group('library sort', () {
    final books = [
      _book(1, 'banana', 2),
      _book(2, 'Apple', 9),
      _book(3, 'cherry', 5),
    ];

    test('recent keeps the order the database gave', () {
      expect(sortBooks(books, LibrarySort.recent).map((b) => b.id), [1, 2, 3]);
    });

    test('title is case-insensitive A-Z', () {
      expect(sortBooks(books, LibrarySort.title).map((b) => b.id), [2, 1, 3]);
    });

    test('progress puts the most read first', () {
      expect(sortBooks(books, LibrarySort.progress).map((b) => b.id), [
        2,
        3,
        1,
      ]);
    });

    test('sorting never changes the original list', () {
      sortBooks(books, LibrarySort.title);
      expect(books.map((b) => b.id), [1, 2, 3]);
    });
  });
}
