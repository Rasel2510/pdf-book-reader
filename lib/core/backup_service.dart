import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/repository.dart';

final backupProvider = Provider<BackupService>(
  (ref) => BackupService(ref.read(repositoryProvider)),
);

/// The picked file is not a backup made by this app (or it is damaged).
class BadBackupException implements Exception {
  const BadBackupException();
}

/// Books put on the shelf by a restore, and books left alone because they
/// were on it already.
typedef RestoreResult = ({int added, int skipped});

/// Saves the whole library into one zip file and reads it back.
///
/// The zip holds `backup.json` (every book with its progress, highlights,
/// bookmarks, saved words and reading log) and, under `books/`, each book's
/// PDF (with the highlights drawn into it) and its cover.
///
/// A restore only adds: a book that is already on the shelf is skipped, and
/// nothing on the device is replaced or deleted.
class BackupService {
  BackupService(
    this._repo, {
    Future<Directory> Function()? tempDir,
    Future<Directory> Function()? booksDir,
  }) : _tempDir = tempDir ?? getTemporaryDirectory,
       _booksDir = booksDir ?? _defaultBooksDir;

  static const _manifest = 'backup.json';
  static const _folder = 'books';
  static const _format = 1;

  final Repository _repo;
  final Future<Directory> Function() _tempDir;
  final Future<Directory> Function() _booksDir;

  static Future<Directory> _defaultBooksDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'books'));
  }

  /// Writes the backup into the temp folder and returns it, or null when
  /// there is no book to back up. The caller deletes the file when done.
  Future<File?> create() async {
    final books = await _repo.exportLibrary();
    if (books.isEmpty) return null;

    final temp = await _tempDir();
    final zip = File(p.join(temp.path, 'paperleaf-backup.zip'));
    if (await zip.exists()) await zip.delete();

    // PDFs and JPEGs are compressed already: storing them is fast and the
    // file is no bigger.
    final encoder = ZipFileEncoder()
      ..create(zip.path, level: ZipFileEncoder.store);
    try {
      encoder.addArchiveFile(
        ArchiveFile.string(
          _manifest,
          jsonEncode({
            'format': _format,
            'app': 'Paperleaf Reader',
            'created': DateTime.now().toIso8601String(),
            'books': [for (final book in books) book.data],
          }),
        ),
      );
      for (final book in books) {
        final pdf = File(book.path);
        if (!await pdf.exists()) continue; // listed, but restored as missing
        final name = p.basename(book.path);
        await encoder.addFile(pdf, '$_folder/$name', ZipFileEncoder.store);

        final cover = File('${p.withoutExtension(book.path)}.jpg');
        if (await cover.exists()) {
          await encoder.addFile(
            cover,
            '$_folder/${p.basename(cover.path)}',
            ZipFileEncoder.store,
          );
        }
      }
    } finally {
      await encoder.close();
    }
    return zip;
  }

  /// Adds the books of the backup at [zipPath] that are not on the shelf.
  Future<RestoreResult> restore(String zipPath) async {
    final input = InputFileStream(zipPath);
    try {
      final (archive, books) = _read(input);
      final dir = await (await _booksDir()).create(recursive: true);
      final onShelf = await _repo.bookFileNames();

      var added = 0;
      var skipped = 0;
      for (final raw in books) {
        if (raw is! Map) continue;
        final book = raw.cast<String, Object?>();
        // Only the file name is used, so a backup cannot write elsewhere.
        final name = p.basename('${book['file'] ?? ''}');
        if (p.extension(name).toLowerCase() != '.pdf') continue;
        if (onShelf.contains(name)) {
          skipped++;
          continue;
        }
        final pdf = archive.find('$_folder/$name');
        if (pdf == null) continue;

        final coverName = '${p.withoutExtension(name)}.jpg';
        final target = p.join(dir.path, name);
        final coverTarget = p.join(dir.path, coverName);
        try {
          await _extract(pdf, target);
          final cover = archive.find('$_folder/$coverName');
          if (cover != null) await _extract(cover, coverTarget);
          await _repo.importBook(book, target);
        } catch (_) {
          // Leave nothing behind for a book that did not reach the shelf.
          for (final path in [target, coverTarget]) {
            try {
              final leftover = File(path);
              if (await leftover.exists()) await leftover.delete();
            } catch (_) {}
          }
          rethrow;
        }
        onShelf.add(name);
        added++;
      }
      return (added: added, skipped: skipped);
    } finally {
      await input.close();
    }
  }

  (Archive, List<Object?>) _read(InputFileStream input) {
    try {
      final archive = ZipDecoder().decodeStream(input);
      final manifest = archive.find(_manifest);
      if (manifest == null) throw const BadBackupException();
      final data = jsonDecode(utf8.decode(manifest.content));
      if (data is! Map || data['books'] is! List) {
        throw const BadBackupException();
      }
      return (archive, data['books'] as List<Object?>);
    } on BadBackupException {
      rethrow;
    } catch (_) {
      throw const BadBackupException();
    }
  }

  Future<void> _extract(ArchiveFile entry, String path) async {
    final output = OutputFileStream(path);
    try {
      entry.writeContent(output);
    } finally {
      await output.close();
    }
  }
}
