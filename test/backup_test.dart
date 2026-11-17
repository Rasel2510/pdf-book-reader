import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_book_reader/core/backup_service.dart';
import 'package:pdf_book_reader/data/repository.dart';

/// A shelf kept in memory, so no database is needed.
class _FakeRepository extends Repository {
  _FakeRepository([this.library = const []]);

  final List<({String path, Map<String, Object?> data})> library;
  final imported = <({Map<String, Object?> book, String path})>[];
  bool failImport = false;

  @override
  Future<List<({String path, Map<String, Object?> data})>>
  exportLibrary() async => library;

  @override
  Future<Set<String>> bookFileNames() async => {
    for (final book in library) p.basename(book.path),
    for (final book in imported) p.basename(book.path),
  };

  @override
  Future<void> importBook(Map<String, Object?> book, String filePath) async {
    if (failImport) throw StateError('database is broken');
    imported.add((book: book, path: filePath));
  }
}

void main() {
  late Directory root;
  late Directory shelf;
  late Directory restored;

  Future<Directory> temp() async => Directory(p.join(root.path, 'temp'));
  Future<Directory> restoreInto() async => restored;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('paperleaf_backup_test');
    await Directory(p.join(root.path, 'temp')).create();
    shelf = await Directory(p.join(root.path, 'shelf')).create();
    restored = Directory(p.join(root.path, 'restored'));
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<_FakeRepository> shelfWithOneBook() async {
    final pdf = File(p.join(shelf.path, '111.pdf'));
    await pdf.writeAsBytes([for (var i = 0; i < 5000; i++) i % 251]);
    await File(p.join(shelf.path, '111.jpg')).writeAsBytes([1, 2, 3, 4]);
    return _FakeRepository([
      (
        path: pdf.path,
        data: {
          'title': 'The Alchemist',
          'file': '111.pdf',
          'last_page': 68,
          'page_count': 136,
          'last_opened': 1700000000000,
          'highlights': [
            {
              'page': 68,
              'text': 'primitive',
              'color': 0xFFFF9100,
              'annotation_marker': 'Paperleaf Reader highlight 1-5',
              'created_at': 1700000000000,
            },
          ],
          'bookmarks': [12, 68],
          'words': [
            {
              'page': 3,
              'word': 'omen',
              'meaning': '(noun) a sign',
              'created_at': 1700000000000,
            },
          ],
          'reading': [
            {'day': '2026-11-16', 'pages': 14, 'seconds': 900},
          ],
        },
      ),
    ]);
  }

  test('a backup restores every book with its files and notes', () async {
    final source = await shelfWithOneBook();
    final zip = await BackupService(source, tempDir: temp).create();
    expect(zip, isNotNull);
    expect(await zip!.exists(), isTrue);

    final target = _FakeRepository();
    final result = await BackupService(
      target,
      tempDir: temp,
      booksDir: restoreInto,
    ).restore(zip.path);

    expect(result, (added: 1, skipped: 0));
    final pdf = File(p.join(restored.path, '111.pdf'));
    expect(
      await pdf.readAsBytes(),
      await File(p.join(shelf.path, '111.pdf')).readAsBytes(),
    );
    expect(await File(p.join(restored.path, '111.jpg')).readAsBytes(), [
      1,
      2,
      3,
      4,
    ]);

    final book = target.imported.single;
    expect(book.path, pdf.path);
    expect(book.book['title'], 'The Alchemist');
    expect(book.book['last_page'], 68);
    expect(book.book['bookmarks'], [12, 68]);
    expect((book.book['highlights']! as List).single['text'], 'primitive');
    expect((book.book['words']! as List).single['word'], 'omen');
    expect((book.book['reading']! as List).single['pages'], 14);
  });

  test('a book already on the shelf is skipped, not duplicated', () async {
    final source = await shelfWithOneBook();
    final service = BackupService(source, tempDir: temp, booksDir: restoreInto);
    final zip = await service.create();

    // The same shelf the backup came from.
    final result = await service.restore(zip!.path);

    expect(result, (added: 0, skipped: 1));
    expect(source.imported, isEmpty);
    expect(await File(p.join(restored.path, '111.pdf')).exists(), isFalse);
  });

  test('a book that cannot be saved leaves no files behind', () async {
    final zip = await BackupService(
      await shelfWithOneBook(),
      tempDir: temp,
    ).create();

    final target = _FakeRepository()..failImport = true;
    await expectLater(
      BackupService(
        target,
        tempDir: temp,
        booksDir: restoreInto,
      ).restore(zip!.path),
      throwsStateError,
    );
    expect(await File(p.join(restored.path, '111.pdf')).exists(), isFalse);
    expect(await File(p.join(restored.path, '111.jpg')).exists(), isFalse);
  });

  test('a file that is not a backup is refused', () async {
    final notZip = File(p.join(root.path, 'notes.zip'));
    await notZip.writeAsString('just some text, not a zip archive at all');

    await expectLater(
      BackupService(
        _FakeRepository(),
        tempDir: temp,
        booksDir: restoreInto,
      ).restore(notZip.path),
      throwsA(isA<BadBackupException>()),
    );
  });

  test('an empty shelf makes no backup file', () async {
    expect(
      await BackupService(_FakeRepository(), tempDir: temp).create(),
      isNull,
    );
  });
}
