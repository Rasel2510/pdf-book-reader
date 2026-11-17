import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/cover_service.dart';
import '../../core/file_utils.dart';
import '../../core/preferences.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

final libraryProvider = AsyncNotifierProvider<LibraryController, List<Book>>(
  LibraryController.new,
);

/// True while a PDF is being copied and its cover rendered.
final importingProvider = NotifierProvider<ImportingController, bool>(
  ImportingController.new,
);

class ImportingController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

/// The picked file is not a PDF (wrong or damaged file).
class NotAPdfException implements Exception {
  const NotAPdfException();
}

class LibraryController extends AsyncNotifier<List<Book>> {
  Repository get _repo => ref.read(repositoryProvider);

  @override
  Future<List<Book>> build() async {
    final books = await _repo.books();
    return _tidyOldTitles(books);
  }

  /// Once: books put on the shelf before titles were tidied still carry the
  /// raw file name. Only names without a single space are touched, since
  /// nobody types a title that way. A convenience: it never keeps the shelf
  /// from loading.
  Future<List<Book>> _tidyOldTitles(List<Book> books) async {
    const done = 'titles_tidied_1';
    try {
      final prefs = ref.read(sharedPrefsProvider);
      if (prefs.getBool(done) ?? false) return books;

      final tidied = <Book>[];
      for (final book in books) {
        final title = cleanBookTitle(book.title);
        if (title == book.title || book.title.trim().contains(' ')) {
          tidied.add(book);
        } else {
          await _repo.renameBook(book.id, title);
          tidied.add(book.copyWith(title: title));
        }
      }
      await prefs.setBool(done, true);
      return tidied;
    } catch (_) {
      return books;
    }
  }

  /// Copies the picked PDF into app storage, builds its cover, registers it.
  Future<void> add(PlatformFile file) async {
    await _busy(
      () => _import(name: file.name, path: file.path, bytes: file.readAsBytes),
    );
  }

  /// Puts a PDF that another app handed over ("Open with") on the shelf and
  /// returns its book, ready to open. Opening the same file again must not
  /// fill the shelf with copies: a book with the same title is taken to be
  /// that book and is returned as it is.
  Future<Book?> addIncoming(String path, String name) async {
    final title = _titleFor(name);
    for (final book in await future) {
      if (book.title == title) return book;
    }

    final target = await _busy(() => _import(name: name, path: path));
    for (final book in state.value ?? const <Book>[]) {
      if (book.filePath == target) return book;
    }
    return null;
  }

  /// Shows the progress bar on the shelf while [work] runs.
  Future<T> _busy<T>(Future<T> Function() work) async {
    ref.read(importingProvider.notifier).set(true);
    try {
      return await work();
    } finally {
      ref.read(importingProvider.notifier).set(false);
    }
  }

  String _titleFor(String fileName) {
    final title = cleanBookTitle(p.basenameWithoutExtension(fileName));
    return title.isEmpty ? 'Untitled' : title;
  }

  /// Puts the PDF at [path] (or made of [bytes]) on the shelf and returns
  /// where its copy was stored.
  Future<String> _import({
    required String name,
    String? path,
    Future<List<int>> Function()? bytes,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = await Directory(
      p.join(docs.path, 'books'),
    ).create(recursive: true);
    final target = p.join(
      dir.path,
      '${DateTime.now().millisecondsSinceEpoch}.pdf',
    );

    final cover = '${p.withoutExtension(target)}.jpg';

    try {
      if (path != null) {
        await File(path).copy(target);
      } else if (bytes != null) {
        await File(target).writeAsBytes(await bytes());
      } else {
        throw const NotAPdfException();
      }
      if (!await _looksLikePdf(target)) throw const NotAPdfException();

      // 0 pages: the cover could not be drawn (e.g. a locked PDF). The
      // reader may still open it, and it fills in the page count then.
      final pageCount = await createCover(pdfPath: target, coverPath: cover);
      await _repo.addBook(_titleFor(name), target, pageCount);
    } catch (_) {
      // Leave nothing behind for a book that did not reach the shelf.
      for (final path in [target, cover]) {
        try {
          final leftover = File(path);
          if (await leftover.exists()) await leftover.delete();
        } catch (_) {}
      }
      rethrow;
    }
    await reload();
    return target;
  }

  /// Every PDF has "%PDF" near its start.
  Future<bool> _looksLikePdf(String path) async {
    final head = <int>[];
    await for (final chunk in File(path).openRead(0, 1024)) {
      head.addAll(chunk);
    }
    const magic = [0x25, 0x50, 0x44, 0x46];
    for (var i = 0; i + magic.length <= head.length; i++) {
      var match = true;
      for (var j = 0; j < magic.length; j++) {
        if (head[i + j] != magic[j]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }

  Future<void> rename(Book book, String title) async {
    final name = title.trim();
    if (name.isEmpty || name == book.title) return;
    await _repo.renameBook(book.id, name);
    final books = state.value;
    if (books == null) return;
    state = AsyncData([
      for (final b in books) b.id == book.id ? b.copyWith(title: name) : b,
    ]);
  }

  Future<void> remove(Book book) async {
    await _repo.deleteBook(book);
    await reload();
  }

  /// Called once when the reader closes: updates the shelf in memory instead
  /// of re-querying the table. The DB already has the same values.
  void applyProgress(int bookId, int page, int pageCount) {
    final books = state.value;
    if (books == null) return;
    final i = books.indexWhere((b) => b.id == bookId);
    if (i < 0) return;

    final old = books[i];
    final updated = old.copyWith(
      lastPage: page,
      pageCount: pageCount > 0 ? pageCount : old.pageCount,
    );
    if (updated == old) return;
    // Same order the DB gives (last_opened DESC): a turned page moves it up.
    if (page != old.lastPage) {
      state = AsyncData([updated, ...books.where((b) => b.id != bookId)]);
    } else {
      final next = [...books];
      next[i] = updated;
      state = AsyncData(next);
    }
  }

  Future<void> reload() async {
    state = AsyncData(await _repo.books());
  }
}
