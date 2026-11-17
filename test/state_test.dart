import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_book_reader/data/models.dart';
import 'package:pdf_book_reader/data/repository.dart';
import 'package:pdf_book_reader/features/library/library_controller.dart';
import 'package:pdf_book_reader/features/notes/notes_providers.dart';

Book _book(int id, {int lastPage = 1}) => Book(
  id: id,
  title: 'b$id',
  filePath: '/tmp/$id.pdf',
  lastPage: lastPage,
  pageCount: 20,
);

class _FakeRepo extends Repository {
  final saved = <int>{2};
  var bookmarkLoads = 0;

  @override
  Future<List<Book>> books() async => [_book(1), _book(2), _book(3)];

  @override
  Future<Set<int>> bookmarkPages(int bookId) async {
    bookmarkLoads++;
    return {...saved};
  }

  @override
  Future<void> setBookmark(int bookId, int page, {required bool on}) async {
    on ? saved.add(page) : saved.remove(page);
  }
}

void main() {
  late _FakeRepo repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeRepo();
    container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
  });

  group('library applyProgress', () {
    test('a turned page moves the book to the front', () async {
      await container.read(libraryProvider.future);
      container.read(libraryProvider.notifier).applyProgress(2, 7, 20);

      final books = container.read(libraryProvider).value!;
      expect(books.map((b) => b.id), [2, 1, 3]);
      expect(books.first.lastPage, 7);
    });

    test('same page keeps the order', () async {
      await container.read(libraryProvider.future);
      container.read(libraryProvider.notifier).applyProgress(3, 1, 25);

      final books = container.read(libraryProvider).value!;
      expect(books.map((b) => b.id), [1, 2, 3]);
      expect(books.last.pageCount, 25);
    });

    test('unknown book is ignored', () async {
      await container.read(libraryProvider.future);
      container.read(libraryProvider.notifier).applyProgress(99, 5, 20);

      expect(container.read(libraryProvider).value!.length, 3);
    });
  });

  group('bookmarks', () {
    test('load fills the book once', () async {
      final notifier = container.read(bookmarksProvider.notifier);
      await notifier.load(1);
      expect(container.read(bookmarksProvider)[1], {2});

      repo.saved.add(9); // a second load must not re-read
      await notifier.load(1);
      expect(container.read(bookmarksProvider)[1], {2});
    });

    test('concurrent loads share one database query', () async {
      final notifier = container.read(bookmarksProvider.notifier);
      await Future.wait([notifier.load(1), notifier.load(1)]);

      expect(repo.bookmarkLoads, 1);
      expect(container.read(bookmarksProvider)[1], {2});
    });

    test('toggle adds and removes, and persists', () async {
      final notifier = container.read(bookmarksProvider.notifier);

      await notifier.toggle(1, 5);
      expect(container.read(bookmarksProvider)[1], {2, 5});
      expect(repo.saved, {2, 5});

      await notifier.toggle(1, 5);
      expect(container.read(bookmarksProvider)[1], {2});
      expect(repo.saved, {2});
    });

    test('remove drops the page', () async {
      final notifier = container.read(bookmarksProvider.notifier);
      await notifier.load(1);
      await notifier.remove(1, 2);

      expect(container.read(bookmarksProvider)[1], isEmpty);
    });
  });
}
