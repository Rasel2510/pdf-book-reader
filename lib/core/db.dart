import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

abstract final class AppDb {
  static Future<Database>? _db;

  /// Opened once; concurrent callers share the same future.
  static Future<Database> get instance {
    final existing = _db;
    if (existing != null) return existing;

    final opening = _open();
    _db = opening;
    // A failed open must not be remembered: the next caller tries again.
    opening.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_db, opening)) _db = null;
      },
    );
    return opening;
  }

  static Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'reader.db');
    return openDatabase(
      path,
      version: 5,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await _createIndexes(db);
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE highlights ADD COLUMN color INTEGER');
          await db.execute('ALTER TABLE words ADD COLUMN meaning TEXT');
          await _createReadingLog(db);
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE highlights ADD COLUMN annotation_marker TEXT',
          );
        }
        if (oldVersion < 5) {
          // Word review: how well a word is known and when it is due again.
          await db.execute(
            'ALTER TABLE words ADD COLUMN box INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE words ADD COLUMN due INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE books(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            file_path TEXT NOT NULL,
            last_page INTEGER NOT NULL DEFAULT 1,
            page_count INTEGER NOT NULL DEFAULT 0,
            last_opened INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE highlights(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            page INTEGER NOT NULL,
            text TEXT NOT NULL,
            color INTEGER,
            annotation_marker TEXT,
            created_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE bookmarks(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            page INTEGER NOT NULL,
            UNIQUE(book_id, page)
          )''');
        await db.execute('''
          CREATE TABLE words(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            page INTEGER NOT NULL,
            word TEXT NOT NULL,
            meaning TEXT,
            created_at INTEGER NOT NULL,
            box INTEGER NOT NULL DEFAULT 0,
            due INTEGER NOT NULL DEFAULT 0
          )''');
        await _createIndexes(db);
        await _createReadingLog(db);
      },
    );
  }

  /// One row per day and book: pages turned and seconds spent reading.
  static Future<void> _createReadingLog(Database db) => db.execute('''
    CREATE TABLE IF NOT EXISTS reading_log(
      day TEXT NOT NULL,
      book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      pages INTEGER NOT NULL DEFAULT 0,
      seconds INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(day, book_id)
    )''');

  /// Notes screens filter by book_id; without these every open scans the table.
  static Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_highlights_book ON highlights(book_id, page)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_words_book ON words(book_id)',
    );
  }
}
