import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/db.dart';
import 'models.dart';
import 'reading_stats.dart';

final repositoryProvider = Provider<Repository>((ref) => Repository());

int _now() => DateTime.now().millisecondsSinceEpoch;

class Repository {
  Future<Database> get _db => AppDb.instance;

  // Books
  Future<List<Book>> books() async {
    final rows = await (await _db).query('books', orderBy: 'last_opened DESC');
    return rows.map(Book.fromMap).toList();
  }

  Future<void> addBook(String title, String path, int pageCount) async {
    await (await _db).insert('books', {
      'title': title,
      'file_path': path,
      'page_count': pageCount,
      'last_opened': _now(),
    });
  }

  Future<void> renameBook(int bookId, String title) async {
    await (await _db).update(
      'books',
      {'title': title},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> saveProgress(int bookId, int page) async {
    await (await _db).update(
      'books',
      {'last_page': page, 'last_opened': _now()},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> savePageCount(int bookId, int count) async {
    await (await _db).update(
      'books',
      {'page_count': count},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> deleteBook(Book book) async {
    await (await _db).delete('books', where: 'id = ?', whereArgs: [book.id]);
    // The book is gone from the shelf either way; a file that cannot be
    // removed only wastes space.
    for (final path in [book.filePath, book.coverPath]) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  // Highlights
  Future<List<Highlight>> highlights(int bookId) async {
    final rows = await (await _db).query(
      'highlights',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'page, id',
    );
    return rows.map(Highlight.fromMap).toList();
  }

  Future<int> addHighlight(
    int bookId,
    int page,
    String text, {
    int? color,
    String? annotationMarker,
  }) async {
    return (await _db).insert('highlights', {
      'book_id': bookId,
      'page': page,
      'text': text,
      'color': color,
      'annotation_marker': annotationMarker,
      'created_at': _now(),
    });
  }

  /// Gives a book's highlights of color [from] the color [to] (ARGB).
  Future<int> recolorHighlights(int bookId, int from, int to) async {
    return (await _db).update(
      'highlights',
      {'color': to},
      where: 'book_id = ? AND color = ?',
      whereArgs: [bookId, from],
    );
  }

  Future<void> deleteHighlight(int id) async {
    await (await _db).delete('highlights', where: 'id = ?', whereArgs: [id]);
  }

  // Bookmarks (pages only; the UI keeps them as a Set<int> in memory)
  Future<Set<int>> bookmarkPages(int bookId) async {
    final rows = await (await _db).query(
      'bookmarks',
      columns: ['page'],
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    return {for (final r in rows) r['page'] as int};
  }

  Future<void> setBookmark(int bookId, int page, {required bool on}) async {
    final db = await _db;
    if (on) {
      await db.insert('bookmarks', {
        'book_id': bookId,
        'page': page,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.delete(
        'bookmarks',
        where: 'book_id = ? AND page = ?',
        whereArgs: [bookId, page],
      );
    }
  }

  // Saved words
  Future<List<SavedWord>> words(int bookId) async {
    final rows = await (await _db).query(
      'words',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'id DESC',
    );
    return rows.map(SavedWord.fromMap).toList();
  }

  Future<int> addWord(int bookId, int page, String word) async {
    return (await _db).insert('words', {
      'book_id': bookId,
      'page': page,
      'word': word,
      'created_at': _now(),
    });
  }

  Future<void> setWordMeaning(int id, String? meaning) async {
    await (await _db).update(
      'words',
      {'meaning': meaning},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteWord(int id) async {
    await (await _db).delete('words', where: 'id = ?', whereArgs: [id]);
  }

  // Backup
  /// Every book with all that belongs to it, as plain values for a backup
  /// file. `path` is where its PDF is on this device; `data` names the file
  /// only, because the folder differs from device to device.
  Future<List<({String path, Map<String, Object?> data})>>
  exportLibrary() async {
    final db = await _db;
    final out = <({String path, Map<String, Object?> data})>[];
    for (final book in await db.query('books', orderBy: 'id')) {
      Future<List<Map<String, Object?>>> rows(
        String table,
        List<String> columns,
      ) => db.query(
        table,
        columns: columns,
        where: 'book_id = ?',
        whereArgs: [book['id']],
      );

      final path = book['file_path'] as String;
      out.add((
        path: path,
        data: {
          'title': book['title'],
          'file': p.basename(path),
          'last_page': book['last_page'],
          'page_count': book['page_count'],
          'last_opened': book['last_opened'],
          'highlights': await rows('highlights', [
            'page',
            'text',
            'color',
            'annotation_marker',
            'created_at',
          ]),
          'bookmarks': [
            for (final row in await rows('bookmarks', ['page'])) row['page'],
          ],
          'words': await rows('words', [
            'page',
            'word',
            'meaning',
            'created_at',
          ]),
          'reading': await rows('reading_log', ['day', 'pages', 'seconds']),
        },
      ));
    }
    return out;
  }

  /// File names (not paths) of the PDFs of all books on the shelf.
  Future<Set<String>> bookFileNames() async {
    final rows = await (await _db).query('books', columns: ['file_path']);
    return {for (final row in rows) p.basename(row['file_path'] as String)};
  }

  /// Puts one book from a backup on the shelf with everything that belongs
  /// to it, or nothing at all if any part fails. [book] is one `data` map of
  /// [exportLibrary] (read back from a file, so every value is checked).
  Future<void> importBook(Map<String, Object?> book, String filePath) async {
    int number(Object? value, int fallback) =>
        value is num ? value.toInt() : fallback;
    String? text(Object? value) =>
        value is String && value.isNotEmpty ? value : null;
    Iterable<Map<Object?, Object?>> maps(Object? value) =>
        value is List ? value.whereType<Map<Object?, Object?>>() : const [];

    await (await _db).transaction((txn) async {
      final id = await txn.insert('books', {
        'title': text(book['title']) ?? 'Untitled',
        'file_path': filePath,
        'last_page': number(book['last_page'], 1),
        'page_count': number(book['page_count'], 0),
        'last_opened': number(book['last_opened'], _now()),
      });

      for (final row in maps(book['highlights'])) {
        final words = text(row['text']);
        if (words == null) continue;
        await txn.insert('highlights', {
          'book_id': id,
          'page': number(row['page'], 1),
          'text': words,
          'color': row['color'] is num ? number(row['color'], 0) : null,
          'annotation_marker': text(row['annotation_marker']),
          'created_at': number(row['created_at'], _now()),
        });
      }

      final bookmarks = book['bookmarks'];
      if (bookmarks is List) {
        for (final page in bookmarks.whereType<num>()) {
          await txn.insert('bookmarks', {
            'book_id': id,
            'page': page.toInt(),
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }

      for (final row in maps(book['words'])) {
        final word = text(row['word']);
        if (word == null) continue;
        await txn.insert('words', {
          'book_id': id,
          'page': number(row['page'], 1),
          'word': word,
          'meaning': text(row['meaning']),
          'created_at': number(row['created_at'], _now()),
        });
      }

      for (final row in maps(book['reading'])) {
        final day = text(row['day']);
        if (day == null || DateTime.tryParse(day) == null) continue;
        await txn.insert('reading_log', {
          'day': day,
          'book_id': id,
          'pages': number(row['pages'], 0),
          'seconds': number(row['seconds'], 0),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  // Reading log
  /// Adds to today's totals for [bookId]. (Two steps instead of an upsert:
  /// older Android SQLite versions do not support ON CONFLICT DO UPDATE.)
  Future<void> logReading(int bookId, int pages, int seconds) async {
    final day = dayKey(DateTime.now());
    await (await _db).transaction((txn) async {
      final changed = await txn.rawUpdate(
        'UPDATE reading_log SET pages = pages + ?, seconds = seconds + ? '
        'WHERE day = ? AND book_id = ?',
        [pages, seconds, day, bookId],
      );
      if (changed == 0) {
        await txn.insert('reading_log', {
          'day': day,
          'book_id': bookId,
          'pages': pages,
          'seconds': seconds,
        });
      }
    });
  }

  Future<List<ReadingDay>> readingDays() async {
    final rows = await (await _db).rawQuery(
      'SELECT day, SUM(pages) AS pages, SUM(seconds) AS seconds '
      'FROM reading_log GROUP BY day',
    );
    return [
      for (final r in rows)
        ReadingDay(
          day: DateTime.parse(r['day'] as String),
          pages: (r['pages'] as int?) ?? 0,
          seconds: (r['seconds'] as int?) ?? 0,
        ),
    ];
  }
}
