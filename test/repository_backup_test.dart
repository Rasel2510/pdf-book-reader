import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_book_reader/core/db.dart';
import 'package:pdf_book_reader/data/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Runs the real SQL of a backup and a restore against a real (desktop)
/// SQLite database.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Start from an empty database file.
    await deleteDatabase(p.join(await getDatabasesPath(), 'reader.db'));
  });

  tearDownAll(() async {
    await (await AppDb.instance).close();
  });

  test('a book read out of the database goes back in complete', () async {
    final repo = Repository();

    await repo.addBook('The Alchemist', '/old/device/books/111.pdf', 136);
    final original = (await repo.books()).single;
    await repo.saveProgress(original.id, 68);
    await repo.addHighlight(
      original.id,
      68,
      'primitive',
      color: 0xFFFF9100,
      annotationMarker: 'Paperleaf Reader highlight 1-5',
    );
    await repo.addHighlight(original.id, 70, 'no color, no tag');
    await repo.setBookmark(original.id, 12, on: true);
    await repo.setBookmark(original.id, 68, on: true);
    final wordId = await repo.addWord(original.id, 3, 'omen');
    await repo.setWordMeaning(wordId, '(noun) a sign');
    await repo.addWord(original.id, 4, 'levanter');
    await repo.logReading(original.id, 14, 900);

    final exported = (await repo.exportLibrary()).single;
    expect(exported.path, '/old/device/books/111.pdf');
    expect(exported.data['file'], '111.pdf');
    expect(await repo.bookFileNames(), {'111.pdf'});

    // Through a file and back, as a restore gets it.
    final fromFile = (jsonDecode(jsonEncode(exported.data)) as Map)
        .cast<String, Object?>();
    await repo.importBook(fromFile, '/new/device/books/111.pdf');

    final books = await repo.books();
    expect(books, hasLength(2));
    final restored = books.firstWhere((book) => book.id != original.id);
    expect(restored.title, 'The Alchemist');
    expect(restored.filePath, '/new/device/books/111.pdf');
    expect(restored.lastPage, 68);
    expect(restored.pageCount, 136);

    final highlights = await repo.highlights(restored.id);
    expect(highlights.map((h) => h.text), ['primitive', 'no color, no tag']);
    expect(highlights.first.page, 68);
    expect(highlights.first.color, 0xFFFF9100);
    expect(highlights.first.annotationMarker, 'Paperleaf Reader highlight 1-5');
    expect(highlights.last.color, isNull);
    expect(highlights.last.annotationMarker, isNull);

    expect(await repo.bookmarkPages(restored.id), {12, 68});

    final words = await repo.words(restored.id);
    expect(words.map((w) => w.word).toSet(), {'omen', 'levanter'});
    expect(words.firstWhere((w) => w.word == 'omen').meaning, '(noun) a sign');
    expect(words.firstWhere((w) => w.word == 'levanter').meaning, isNull);

    // Both copies read 14 pages today.
    final days = await repo.readingDays();
    expect(days.single.pages, 28);
    expect(days.single.seconds, 1800);

    // The original book is untouched.
    expect(await repo.highlights(original.id), hasLength(2));
    expect(await repo.bookmarkPages(original.id), {12, 68});
  });

  test('a damaged entry is left out, the rest of the book is kept', () async {
    final repo = Repository();
    final before = (await repo.books()).length;

    await repo.importBook({
      'title': 42, // not text
      'last_page': 'seven', // not a number
      'highlights': [
        {'page': 5, 'text': 'kept'},
        {'page': 6}, // no words
        'not a highlight',
      ],
      'bookmarks': [3, 'x', 3],
      'words': [
        {'page': 1},
        {'page': 2, 'word': 'kept'},
      ],
      'reading': [
        {'day': 'yesterday', 'pages': 1},
        {'day': '2026-11-01', 'pages': 2, 'seconds': 60},
      ],
    }, '/new/device/books/222.pdf');

    final books = await repo.books();
    expect(books, hasLength(before + 1));
    final book = books.firstWhere((b) => b.filePath.endsWith('222.pdf'));
    expect(book.title, 'Untitled');
    expect(book.lastPage, 1);
    expect((await repo.highlights(book.id)).map((h) => h.text), ['kept']);
    expect(await repo.bookmarkPages(book.id), {3});
    expect((await repo.words(book.id)).map((w) => w.word), ['kept']);
  });
}
